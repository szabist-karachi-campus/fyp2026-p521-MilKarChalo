import { validationResult } from 'express-validator';
import { pool } from '../config/db.js';
import { randomUUID } from 'crypto';
import { sendNotification, buildMessage } from '../services/notification.service.js';
import { io } from '../index.js';
import { emitChatDisabled, emitRideEvent } from '../socket/chat.socket.js';
import { geocodeAddress, getDirections, getPlacesAutocomplete } from '../services/maps.service.js';
import {
  generateOccurrenceDates,
  insertOccurrences,
  cancelFutureOccurrences,
  getUpcomingOccurrences,
  validateOccurrencePairing,
} from '../services/recurrence.service.js';

const isTruthy = (value) => value === true || value === 'true' || value === 1 || value === '1';

const parseIntSafe = (value, fallback = 0) => {
  const parsed = parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};

const parseFloatSafe = (value, fallback = 0) => {
  const parsed = parseFloat(value);
  return Number.isFinite(parsed) ? parsed : fallback;
};

const parseDateOnly = (value) => {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString().slice(0, 10);
};

async function cancelBookingsInRows(connection, rows) {
  for (const row of rows) {
    if (row.status === 'cancelled') continue;
    await connection.execute(
      `UPDATE bookings SET status = 'cancelled' WHERE id = ?`,
      [row.id]
    );
    await connection.execute(
      `UPDATE rides SET available_seats = available_seats + ? WHERE id = ?`,
      [parseIntSafe(row.seats_booked, 0), row.ride_id]
    );
  }
}

async function getReviewEligibility(connection, bookingId, reviewerId) {
  const [[row]] = await connection.execute(
    `SELECT b.id as booking_id, b.status as booking_status, b.passenger_id,
            r.id as ride_id, r.driver_id, r.status as ride_status
     FROM bookings b
     JOIN rides r ON b.ride_id = r.id
     WHERE b.id = ?
     LIMIT 1`,
    [bookingId]
  );

  if (!row) return { ok: false, status: 404, message: 'Booking not found.' };
  if (row.ride_status !== 'completed') {
    return { ok: false, status: 409, message: 'Reviews can only be submitted after a ride is completed.' };
  }
  if (row.booking_status !== 'accepted' && row.booking_status !== 'completed') {
    return { ok: false, status: 409, message: 'Only accepted or completed bookings can be reviewed.' };
  }

  let revieweeId = null;
  if (reviewerId === row.passenger_id) {
    revieweeId = row.driver_id;
  } else if (reviewerId === row.driver_id) {
    revieweeId = row.passenger_id;
  } else {
    return { ok: false, status: 403, message: 'You can only review a ride you participated in.' };
  }

  if (revieweeId === reviewerId) {
    return { ok: false, status: 400, message: 'You cannot review yourself.' };
  }

  return { ok: true, data: { ...row, revieweeId } };
}

export const postRide = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });

  const driver_id = req.user.uid;
  const {
    pickup_location,
    destination,
    departure_time,
    total_seats,
    fare,
    round_trip_enabled,
    return_departure_time,
    return_total_seats,
    return_fare,
    // Recurring ride fields
    is_recurring,
    recurrence_type,
    recurrence_days,   // array of 1–7 integers
    recurrence_start_date,
    recurrence_end_date,
  } = req.body;

  const roundTripEnabled = isTruthy(round_trip_enabled);
  const recurringEnabled = isTruthy(is_recurring);

  // ── Recurring validation ────────────────────────────────────────────────────
  if (recurringEnabled) {
    if (!recurrence_type || !['daily', 'weekly', 'custom'].includes(recurrence_type)) {
      return res.status(422).json({ message: 'recurrence_type must be daily, weekly, or custom.' });
    }
    if (!recurrence_start_date) {
      return res.status(422).json({ message: 'recurrence_start_date is required for recurring rides.' });
    }
    if (['weekly', 'custom'].includes(recurrence_type)) {
      if (!Array.isArray(recurrence_days) || recurrence_days.length === 0) {
        return res.status(422).json({ message: 'recurrence_days must be a non-empty array for weekly/custom.' });
      }
    }
    if (recurrence_end_date && recurrence_end_date <= recurrence_start_date) {
      return res.status(422).json({ message: 'recurrence_end_date must be after recurrence_start_date.' });
    }
  }

  try {
    // ── Geocode addresses (failure must not abort ride creation) ─────────────
    let pickupCoords = null;
    let destinationCoords = null;
    try {
      [pickupCoords, destinationCoords] = await Promise.all([
        geocodeAddress(pickup_location),
        geocodeAddress(destination),
      ]);
    } catch (_) {
      // geocoding failure must not abort ride creation
    }

    const [driver] = await pool.execute(
      `SELECT verification_status FROM driver_profiles WHERE user_id = ?`,
      [driver_id]
    );
    if (!driver.length || driver[0].verification_status !== 'approved') {
      return res.status(403).json({ message: 'Your account is not yet approved by an admin.' });
    }

    const [vehicle] = await pool.execute(
      `SELECT id FROM vehicles WHERE user_id = ? LIMIT 1`,
      [driver_id]
    );
    if (!vehicle.length) {
      return res.status(400).json({ message: 'Please register a vehicle before posting a ride.' });
    }

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();

      const roundTripGroupId  = roundTripEnabled ? randomUUID() : null;
      const recurrenceGroupId = recurringEnabled  ? randomUUID() : null;
      const departureSeats    = parseIntSafe(total_seats, 1);
      const departureFare     = parseFloatSafe(fare, 0);

      // Extract HH:MM from departure_time (which may be a full ISO datetime or time-only)
      let departureTimeOnly = '08:00:00';
      if (departure_time) {
        const match = departure_time.match(/(\d{2}:\d{2}(:\d{2})?)/);
        if (match) departureTimeOnly = match[1].length === 5 ? match[1] + ':00' : match[1];
      }

      const [departureResult] = await connection.execute(
        `INSERT INTO rides (
          driver_id, vehicle_id, pickup_location, destination, departure_time,
          total_seats, available_seats, fare, status, is_round_trip,
          round_trip_group_id, linked_ride_id, leg_type,
          is_recurring, recurrence_type, recurrence_end_date, recurrence_group_id,
          pickup_lat, pickup_lng, destination_lat, destination_lng
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, 'departure', ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          driver_id,
          vehicle[0].id,
          pickup_location,
          destination,
          departure_time,
          departureSeats,
          departureSeats,
          departureFare,
          roundTripEnabled ? 1 : 0,
          roundTripGroupId,
          null,
          recurringEnabled ? 1 : 0,
          recurringEnabled ? recurrence_type : null,
          recurringEnabled ? (recurrence_end_date || null) : null,
          recurrenceGroupId,
          pickupCoords?.lat ?? null,
          pickupCoords?.lng ?? null,
          destinationCoords?.lat ?? null,
          destinationCoords?.lng ?? null,
        ]
      );

      const departureRideId = departureResult.insertId;

      // ── Save recurrence days (weekly / custom) ────────────────────────────
      if (recurringEnabled && ['weekly', 'custom'].includes(recurrence_type)) {
        for (const day of recurrence_days) {
          await connection.execute(
            `INSERT INTO recurring_ride_days (ride_id, day_of_week) VALUES (?, ?)`,
            [departureRideId, day]
          );
        }
      }

      // ── Generate occurrences ───────────────────────────────────────────────
      if (recurringEnabled) {
        const startDate = recurrence_start_date;
        const endDate   = recurrence_end_date
          || new Date(new Date(startDate).setFullYear(new Date(startDate).getFullYear() + 1))
               .toISOString().slice(0, 10);
        const days = ['weekly', 'custom'].includes(recurrence_type)
          ? recurrence_days.map(Number)
          : [];

        const dates = generateOccurrenceDates(recurrence_type, days, startDate, endDate);
        await insertOccurrences(connection, departureRideId, departureSeats, departureTimeOnly, dates);
      }

      // ── Round-trip return ride ─────────────────────────────────────────────
      let returnRideId = null;
      if (roundTripEnabled) {
        if (!return_departure_time) {
          throw new Error('Return departure time is required for a round trip.');
        }

        const returnSeats = parseIntSafe(return_total_seats, departureSeats);
        const returnFareValue = return_fare === undefined || return_fare === null || return_fare === ''
          ? departureFare
          : parseFloatSafe(return_fare, departureFare);

        const [returnResult] = await connection.execute(
          `INSERT INTO rides (
            driver_id, vehicle_id, pickup_location, destination, departure_time,
            total_seats, available_seats, fare, status, is_round_trip,
            round_trip_group_id, linked_ride_id, leg_type,
            is_recurring, recurrence_type, recurrence_end_date, recurrence_group_id,
            pickup_lat, pickup_lng, destination_lat, destination_lng
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', 1, ?, ?, 'return', ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            driver_id,
            vehicle[0].id,
            destination,
            pickup_location,
            return_departure_time,
            returnSeats,
            returnSeats,
            returnFareValue,
            roundTripGroupId,
            null,
            recurringEnabled ? 1 : 0,
            recurringEnabled ? recurrence_type : null,
            recurringEnabled ? (recurrence_end_date || null) : null,
            recurrenceGroupId,
            destinationCoords?.lat ?? null,
            destinationCoords?.lng ?? null,
            pickupCoords?.lat ?? null,
            pickupCoords?.lng ?? null,
          ]
        );

        returnRideId = returnResult.insertId;

        await connection.execute(
          `UPDATE rides SET linked_ride_id = ? WHERE id = ?`,
          [returnRideId, departureRideId]
        );

        // Generate occurrences for return leg too
        if (recurringEnabled) {
          const startDate = recurrence_start_date;
          const endDate   = recurrence_end_date
            || new Date(new Date(startDate).setFullYear(new Date(startDate).getFullYear() + 1))
                 .toISOString().slice(0, 10);
          const days = ['weekly', 'custom'].includes(recurrence_type)
            ? recurrence_days.map(Number)
            : [];

          let returnTimeOnly = '08:00:00';
          if (return_departure_time) {
            const match = return_departure_time.match(/(\d{2}:\d{2}(:\d{2})?)/);
            if (match) returnTimeOnly = match[1].length === 5 ? match[1] + ':00' : match[1];
          }

          const dates = generateOccurrenceDates(recurrence_type, days, startDate, endDate);
          await insertOccurrences(connection, returnRideId, returnSeats, returnTimeOnly, dates);
        }
      }

      await connection.commit();

      // ── Monitoring: ride creation ──────────────────────────────────────────
      if (recurringEnabled) {
        const occurrencesCreated = recurringEnabled
          ? generateOccurrenceDates(
              recurrence_type,
              ['weekly', 'custom'].includes(recurrence_type) ? recurrence_days.map(Number) : [],
              recurrence_start_date,
              recurrence_end_date
                || new Date(new Date(recurrence_start_date).setFullYear(new Date(recurrence_start_date).getFullYear() + 1))
                     .toISOString().slice(0, 10)
            ).length
          : 0;
        if (roundTripEnabled) {
          console.log('[METRIC] recurring_round_trip_created', {
            recurrence_group_id: recurrenceGroupId,
            departure_ride_id: departureRideId,
            return_ride_id: returnRideId,
            recurrence_type,
            occurrence_count: occurrencesCreated,
            legs: 2,
            total_occurrences: occurrencesCreated * 2,
            driver_id,
          });
        } else {
          console.log('[METRIC] recurring_ride_created', {
            recurrence_group_id: recurrenceGroupId,
            departure_ride_id: departureRideId,
            recurrence_type,
            occurrence_count: occurrencesCreated,
            driver_id,
          });
        }
      }

      res.status(201).json({
        ok: true,
        message: roundTripEnabled
          ? 'Round trip posted successfully!'
          : recurringEnabled
            ? 'Recurring ride posted successfully!'
            : 'Ride posted successfully!',
        data: {
          departure_ride_id: departureRideId,
          return_ride_id: returnRideId,
          round_trip_group_id: roundTripGroupId,
          recurrence_group_id: recurrenceGroupId,
        },
      });
    } catch (txError) {
      await connection.rollback();
      throw txError;
    } finally {
      connection.release();
    }
  } catch (e) {
    console.error('postRide error', e);
    res.status(400).json({ message: e.sqlMessage || e.message || 'Internal server error' });
  }
};

export const searchRides = async (req, res) => {
  const { pickup, destination, gender_pref, seats_needed, ride_date, ride_time, include_occurrences } = req.query;
  const includeOccurrences = isTruthy(include_occurrences);
  
  try {
    // ── Non-recurring rides (existing behaviour) ─────────────────────────────
    let baseQuery = `
      SELECT r.*, u.name as driver_name, u.gender as driver_gender,
             v.model as car_model, v.make as car_make,
             v.color as car_color, v.plate_no as car_plate,
             dp.image_url as driver_image_url,
             NULL  as occurrence_id,
             NULL  as occurrence_date,
             NULL  as departure_datetime,
             NULL  as paired_return_occurrence_id,
             NULL  as paired_return_occurrence_date,
             NULL  as paired_return_departure_datetime,
             rr.id as return_ride_id,
             rr.departure_time as return_departure_time,
             rr.fare as return_fare,
             rr.available_seats as return_available_seats,
             rr.status as return_status,
             rr.pickup_location as return_pickup_location,
             rr.destination as return_destination
      FROM rides r
      JOIN users u ON r.driver_id = u.id
      JOIN vehicles v ON r.vehicle_id = v.id
      LEFT JOIN driver_profiles dp ON dp.user_id = r.driver_id
      LEFT JOIN rides rr ON rr.id = r.linked_ride_id AND rr.leg_type = 'return'
      WHERE r.status = 'active'
      AND r.is_recurring = 0
      AND r.leg_type = 'departure'
      AND r.available_seats >= ?
      AND r.pickup_location LIKE ?
      AND r.destination LIKE ?`;

    const baseParams = [seats_needed || 1, `%${pickup || ''}%`, `%${destination || ''}%`];

    if (ride_date) {
      baseQuery += ` AND DATE(r.departure_time) = ?`;
      baseParams.push(ride_date);
    }
    if (ride_time) {
      baseQuery += ` AND TIME(r.departure_time) >= ?`;
      baseParams.push(ride_time);
    }
    if (gender_pref && gender_pref !== 'both') {
      baseQuery += ` AND u.gender = ?`;
      baseParams.push(gender_pref);
    }

    // ── Recurring rides — join through occurrences ────────────────────────────
    // For recurring round-trips: join with return ride occurrences to get paired info
    let recurQuery = `
      SELECT r.*, u.name as driver_name, u.gender as driver_gender,
             v.model as car_model, v.make as car_make,
             v.color as car_color, v.plate_no as car_plate,
             dp.image_url as driver_image_url,
             ro.id  as occurrence_id,
             DATE_FORMAT(ro.occurrence_date, '%Y-%m-%d') as occurrence_date,
             DATE_FORMAT(ro.departure_datetime, '%Y-%m-%d %H:%i:%s') as departure_datetime,
             CASE WHEN r.is_round_trip = 1 THEN rro.id ELSE NULL END as paired_return_occurrence_id,
             CASE WHEN r.is_round_trip = 1 THEN DATE_FORMAT(rro.occurrence_date, '%Y-%m-%d') ELSE NULL END as paired_return_occurrence_date,
             CASE WHEN r.is_round_trip = 1 THEN DATE_FORMAT(rro.departure_datetime, '%Y-%m-%d %H:%i:%s') ELSE NULL END as paired_return_departure_datetime,
             rr.id as return_ride_id,
             rr.departure_time as return_departure_time,
             rr.fare as return_fare,
             rr.available_seats as return_available_seats,
             rr.status as return_status,
             rr.pickup_location as return_pickup_location,
             rr.destination as return_destination
      FROM rides r
      JOIN users u ON r.driver_id = u.id
      JOIN vehicles v ON r.vehicle_id = v.id
      LEFT JOIN driver_profiles dp ON dp.user_id = r.driver_id
      JOIN ride_occurrences ro ON ro.ride_id = r.id
      LEFT JOIN rides rr ON rr.id = r.linked_ride_id AND rr.leg_type = 'return'
      LEFT JOIN ride_occurrences rro ON rro.ride_id = rr.id AND rro.occurrence_date = ro.occurrence_date
      WHERE r.status = 'active'
      AND r.is_recurring = 1
      AND r.leg_type = 'departure'
      AND ro.status = 'active'
      AND ro.available_seats >= ?
      AND r.pickup_location LIKE ?
      AND r.destination LIKE ?`;

    const recurParams = [seats_needed || 1, `%${pickup || ''}%`, `%${destination || ''}%`];

    if (ride_date) {
      recurQuery += ` AND ro.occurrence_date = ?`;
      recurParams.push(ride_date);
    } else {
      // Default: only show occurrences from today onwards
      const today = new Date().toISOString().slice(0, 10);
      recurQuery += ` AND ro.occurrence_date >= ?`;
      recurParams.push(today);
    }
    if (ride_time) {
      recurQuery += ` AND TIME(ro.departure_datetime) >= ?`;
      recurParams.push(ride_time);
    }
    if (gender_pref && gender_pref !== 'both') {
      recurQuery += ` AND u.gender = ?`;
      recurParams.push(gender_pref);
    }

    const [nonRecurring] = await pool.execute(baseQuery + ` ORDER BY r.departure_time ASC`, baseParams);
    const [recurring]    = await pool.execute(recurQuery + ` ORDER BY ro.occurrence_date ASC, ro.departure_datetime ASC`, recurParams);

    let rides = [...nonRecurring, ...recurring];

    // If requested, enrich results with all occurrences for recurring rides
    if (includeOccurrences) {
      const recurringRideIds = new Set();
      for (const ride of rides) {
        if (ride.is_recurring) {
          recurringRideIds.add(ride.id);
        }
      }

      const occurrencesByRideId = new Map();
      for (const rideId of recurringRideIds) {
        const [occs] = await pool.execute(
          `SELECT id, occurrence_date, DATE_FORMAT(departure_datetime, '%Y-%m-%d %H:%i:%s') as departure_datetime, available_seats, status
           FROM ride_occurrences WHERE ride_id = ? AND status = 'active' ORDER BY occurrence_date ASC`,
          [rideId]
        );
        occurrencesByRideId.set(rideId, occs);
      }

      for (const ride of rides) {
        if (ride.is_recurring) {
          ride.all_occurrences = occurrencesByRideId.get(ride.id) || [];
        }
      }
    }

    res.json({ ok: true, data: rides });
  } catch (e) {
    console.error('searchRides error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const bookRide = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });

  const passenger_id = req.user.uid;
  const { 
    ride_id, ride_ids, seats_requested, occurrence_id, occurrence_ids,
    include_return_leg, return_occurrence_ids  // NEW: for recurring round-trips
  } = req.body;
  
  const requestedRideIds = Array.isArray(ride_ids) && ride_ids.length
    ? [...new Set(ride_ids.map((id) => parseIntSafe(id, 0)).filter((id) => id > 0))]
    : ride_id
      ? [parseIntSafe(ride_id, 0)]
      : [];

  if (!requestedRideIds.length) {
    return res.status(400).json({ message: 'At least one ride must be selected.' });
  }

  const seatsNeeded = Math.max(parseIntSafe(seats_requested, 1), 1);
  const includeReturnLeg = isTruthy(include_return_leg);

  // Support both single occurrence_id and array of occurrence_ids
  const occurrenceIdVal = occurrence_id ? parseIntSafe(occurrence_id, 0) : null;
  const occurrenceIdsArray = Array.isArray(occurrence_ids) && occurrence_ids.length
    ? [...new Set(occurrence_ids.map((id) => parseIntSafe(id, 0)).filter((id) => id > 0))]
    : occurrenceIdVal
      ? [occurrenceIdVal]
      : [];

  // NEW: For recurring round-trips, get return leg occurrence IDs
  const returnOccurrenceIdsArray = Array.isArray(return_occurrence_ids) && return_occurrence_ids.length
    ? [...new Set(return_occurrence_ids.map((id) => parseIntSafe(id, 0)).filter((id) => id > 0))]
    : [];

  if (includeReturnLeg && returnOccurrenceIdsArray.length > 0 && occurrenceIdsArray.length !== returnOccurrenceIdsArray.length) {
    return res.status(400).json({ message: 'Departure and return occurrence counts must match.' });
  }

  const isMultiOccurrence = occurrenceIdsArray.length > 1;

  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    // ── Validate all requested occurrences ────────────────────────────────────
    const occurrenceRows = [];
    if (occurrenceIdsArray.length > 0) {
      const occPh = occurrenceIdsArray.map(() => '?').join(',');
      const [occs] = await connection.execute(
        `SELECT id, ride_id, available_seats, status, occurrence_date, departure_datetime
           FROM ride_occurrences WHERE id IN (${occPh}) FOR UPDATE`,
        occurrenceIdsArray
      );

      if (occs.length !== occurrenceIdsArray.length) {
        throw new Error('One or more occurrences could not be found.');
      }

      for (const occ of occs) {
        if (occ.status !== 'active') {
          throw new Error(`Occurrence on ${occ.occurrence_date} is no longer available.`);
        }
        if (occ.available_seats < seatsNeeded) {
          throw new Error(`Not enough seats for occurrence on ${occ.occurrence_date}.`);
        }
        if (!requestedRideIds.includes(parseIntSafe(occ.ride_id, 0))) {
          throw new Error('Occurrence does not belong to the selected ride.');
        }
        occurrenceRows.push(occ);
      }
    }

    // ── Validate return occurrences if provided ────────────────────────────────
    const returnOccurrenceRows = [];
    if (includeReturnLeg && returnOccurrenceIdsArray.length > 0) {
      const returnOccPh = returnOccurrenceIdsArray.map(() => '?').join(',');
      const [returnOccs] = await connection.execute(
        `SELECT id, ride_id, available_seats, status, occurrence_date, departure_datetime
           FROM ride_occurrences WHERE id IN (${returnOccPh}) FOR UPDATE`,
        returnOccurrenceIdsArray
      );

      if (returnOccs.length !== returnOccurrenceIdsArray.length) {
        throw new Error('One or more return occurrences could not be found.');
      }

      for (let i = 0; i < returnOccs.length; i++) {
        const returnOcc = returnOccs[i];
        const departureOcc = occurrenceRows[i];

        if (returnOcc.status !== 'active') {
          throw new Error(`Return occurrence on ${returnOcc.occurrence_date} is no longer available.`);
        }
        if (returnOcc.available_seats < seatsNeeded) {
          throw new Error(`Not enough seats for return occurrence on ${returnOcc.occurrence_date}.`);
        }

        // Validate pairing: return occurrence must be from same date as departure
        if (returnOcc.occurrence_date !== departureOcc.occurrence_date) {
          throw new Error(`Return occurrence must be from the same date (${departureOcc.occurrence_date}) as departure.`);
        }

        returnOccurrenceRows.push(returnOcc);
      }
    }

    const placeholders = requestedRideIds.map(() => '?').join(',');
    const [rides] = await connection.execute(
      `SELECT id, available_seats, driver_id, fare, status, round_trip_group_id, linked_ride_id, leg_type, is_recurring
       FROM rides WHERE id IN (${placeholders}) FOR UPDATE`,
      requestedRideIds
    );

    if (rides.length !== requestedRideIds.length) {
      throw new Error('One or more rides could not be found.');
    }

    const rideById = new Map(rides.map((ride) => [parseIntSafe(ride.id, 0), ride]));
    const selectedRides = requestedRideIds.map((id) => rideById.get(id));

    for (const ride of selectedRides) {
      if (!ride || ride.status !== 'active') {
        throw new Error('Ride not found or no longer active.');
      }
      if (ride.driver_id === passenger_id) {
        throw new Error('You cannot book your own ride.');
      }
      if (occurrenceIdsArray.length === 0 && ride.available_seats < seatsNeeded) {
        throw new Error('Not enough seats available.');
      }
    }

    if (selectedRides.length > 1) {
      const groupIds = new Set(selectedRides.map((ride) => ride.round_trip_group_id).filter(Boolean));
      const linkedPair = selectedRides.length === 2 && (
        selectedRides[0].linked_ride_id === selectedRides[1].id ||
        selectedRides[1].linked_ride_id === selectedRides[0].id
      );
      if (groupIds.size > 1 || (!groupIds.size && !linkedPair)) {
        throw new Error('The selected rides are not linked as a round trip.');
      }
    }

    // ── Prevent duplicate bookings ─────────────────────────────────────────────
    if (occurrenceIdsArray.length > 0) {
      const occPh2 = occurrenceIdsArray.map(() => '?').join(',');
      const [existingOcc] = await connection.execute(
        `SELECT occurrence_id FROM bookings WHERE passenger_id = ? AND occurrence_id IN (${occPh2})`,
        [passenger_id, ...occurrenceIdsArray]
      );
      if (existingOcc.length) {
        const dupDate = occurrenceRows.find(o => o.id === existingOcc[0].occurrence_id)?.occurrence_date ?? '';
        throw new Error(`You have already booked the occurrence${dupDate ? ` on ${dupDate}` : ''}.`);
      }

      // Also check for duplicate bookings on return occurrences
      if (includeReturnLeg && returnOccurrenceIdsArray.length > 0) {
        const returnOccPh = returnOccurrenceIdsArray.map(() => '?').join(',');
        const [existingReturnOcc] = await connection.execute(
          `SELECT occurrence_id FROM bookings WHERE passenger_id = ? AND occurrence_id IN (${returnOccPh})`,
          [passenger_id, ...returnOccurrenceIdsArray]
        );
        if (existingReturnOcc.length) {
          const dupDate = returnOccurrenceRows.find(o => o.id === existingReturnOcc[0].occurrence_id)?.occurrence_date ?? '';
          throw new Error(`You have already booked the return occurrence${dupDate ? ` on ${dupDate}` : ''}.`);
        }
      }
    } else {
      const [existing] = await connection.execute(
        `SELECT id, ride_id FROM bookings WHERE passenger_id = ? AND ride_id IN (${placeholders})`,
        [passenger_id, ...requestedRideIds]
      );
      if (existing.length) {
        throw new Error('You have already booked one of these rides.');
      }
    }

    // ── Create bookings ────────────────────────────────────────────────────────
    // For multi-occurrence: one booking per occurrence, all in the same group
    // For recurring round-trips with return: book both departure and return occurrences
    const bookingGroupId = (isMultiOccurrence || requestedRideIds.length > 1 || includeReturnLeg) ? randomUUID() : null;
    const farePerRide = parseFloatSafe(selectedRides[0]?.fare, 0);

    if (occurrenceIdsArray.length > 0) {
      // Insert one booking row per occurrence (departure leg)
      for (let i = 0; i < occurrenceRows.length; i++) {
        const occ = occurrenceRows[i];
        const rideId = parseIntSafe(occ.ride_id, 0);
        await connection.execute(
          `INSERT INTO bookings (ride_id, passenger_id, seats_booked, status, booking_group_id, occurrence_id)
           VALUES (?, ?, ?, 'pending', ?, ?)`,
          [rideId, passenger_id, seatsNeeded, bookingGroupId, occ.id]
        );
        await connection.execute(
          `UPDATE ride_occurrences SET available_seats = available_seats - ? WHERE id = ?`,
          [seatsNeeded, occ.id]
        );

        // NEW: If this is a recurring round-trip, also book the return leg occurrence
        if (includeReturnLeg && returnOccurrenceRows.length > i) {
          const returnOcc = returnOccurrenceRows[i];
          const [[returnRideRow]] = await connection.execute(
            `SELECT r.id FROM rides r
             WHERE r.id = ? AND r.leg_type = 'return' LIMIT 1`,
            [parseIntSafe(returnOcc.ride_id, 0)]
          );
          if (returnRideRow) {
            await connection.execute(
              `INSERT INTO bookings (ride_id, passenger_id, seats_booked, status, booking_group_id, occurrence_id)
               VALUES (?, ?, ?, 'pending', ?, ?)`,
              [returnRideRow.id, passenger_id, seatsNeeded, bookingGroupId, returnOcc.id]
            );
            await connection.execute(
              `UPDATE ride_occurrences SET available_seats = available_seats - ? WHERE id = ?`,
              [seatsNeeded, returnOcc.id]
            );
          }
        }
      }
    } else {
      for (const ride of selectedRides) {
        await connection.execute(
          `INSERT INTO bookings (ride_id, passenger_id, seats_booked, status, booking_group_id, occurrence_id)
           VALUES (?, ?, ?, 'pending', ?, ?)`,
          [ride.id, passenger_id, seatsNeeded, bookingGroupId, null]
        );
        await connection.execute(
          `UPDATE rides SET available_seats = available_seats - ? WHERE id = ?`,
          [seatsNeeded, ride.id]
        );
      }
    }

    await connection.commit();

    // ── Monitoring: booking creation ───────────────────────────────────────
    const depLegCount  = occurrenceIdsArray.length || requestedRideIds.length;
    const retLegCount  = includeReturnLeg ? returnOccurrenceIdsArray.length : 0;
    const totalLegs    = depLegCount + retLegCount;
    if (bookingGroupId) {
      console.log('[METRIC] booking_group_created', {
        booking_group_id: bookingGroupId,
        passenger_id,
        ride_ids: requestedRideIds,
        departure_occurrence_count: depLegCount,
        return_occurrence_count: retLegCount,
        total_leg_count: totalLegs,
        seats_requested: seatsNeeded,
        include_return_leg: includeReturnLeg,
        is_recurring_round_trip: includeReturnLeg && occurrenceIdsArray.length > 0,
      });
    } else {
      console.log('[METRIC] booking_created', {
        passenger_id,
        ride_ids: requestedRideIds,
        seats_requested: seatsNeeded,
      });
    }

    const totalFare = farePerRide * seatsNeeded * (occurrenceIdsArray.length || 1) * (includeReturnLeg ? 2 : 1);

    (async () => {
      try {
        const [[passenger]] = await pool.execute(`SELECT name FROM users WHERE id = ? LIMIT 1`, [passenger_id]);
        const passengerName = passenger?.name ?? 'A passenger';
        const rideIds = selectedRides.map(r => r.id);
        const ph2 = rideIds.map(() => '?').join(',');
        const [rideDetails] = await pool.execute(
          `SELECT id, driver_id, pickup_location, destination FROM rides WHERE id IN (${ph2})`,
          rideIds
        );
        const [bookingRows] = await pool.execute(
          `SELECT id as booking_id, ride_id FROM bookings WHERE passenger_id = ? AND ride_id IN (${ph2}) ORDER BY id DESC`,
          [passenger_id, ...rideIds]
        );
        const bookingByRide = new Map(bookingRows.map(b => [b.ride_id, b.booking_id]));
        for (const rd of rideDetails) {
          const occCount = (occurrenceIdsArray.length || 1) * (includeReturnLeg ? 2 : 1);
          const { title, body, payload } = buildMessage('booking_request', {
            passenger_name: passengerName,
            seats: seatsNeeded,
            pickup: rd.pickup_location,
            destination: rd.destination,
            booking_id: bookingByRide.get(rd.id) ?? null,
            ride_id: rd.id,
            occurrence_count: occCount,
          });
          await sendNotification(rd.driver_id, { type: 'booking_request', title, body, payload });
        }
      } catch (e) { console.error('[Notification] bookRide hook error', e); }
    })();

    const occCount = occurrenceIdsArray.length;
    const messagePrefix = includeReturnLeg && occCount > 0
      ? `${occCount} round-trip occurrences booked`
      : occCount > 1
        ? `${occCount} occurrences booked`
        : requestedRideIds.length > 1
          ? 'Round trip booking request sent'
          : 'Booking request sent';

    res.status(201).json({
      ok: true,
      message: messagePrefix + '! Waiting for driver approval.',
      data: {
        booking_group_id: bookingGroupId,
        ride_ids: requestedRideIds,
        occurrence_ids: occurrenceIdsArray,
        return_occurrence_ids: returnOccurrenceIdsArray,
        occurrence_count: occCount,
        seats_requested: seatsNeeded,
        total_fare: parseFloat(totalFare.toFixed(2)),
        include_return_leg: includeReturnLeg,
      },
    });
  } catch (e) {
    await connection.rollback();
    console.error('bookRide error', e);
    res.status(400).json({ message: e.sqlMessage || e.message || 'Internal server error' });
  } finally {
    connection.release();
  }
};

export const getDriverBookingRequests = async (req, res) => {
  const driver_id = req.user.uid;
  try {
    const [rows] = await pool.execute(
      `SELECT b.id as booking_id, b.seats_booked, b.status as booking_status,
              b.booking_group_id,
              b.created_at as requested_at,
              u.id as passenger_id, u.name as passenger_name,
              u.phone as passenger_phone, u.gender as passenger_gender,
              pp.image_url as passenger_image_url,
              r.id as ride_id, r.pickup_location, r.destination,
              r.departure_time, r.fare, r.available_seats,
              r.leg_type, r.is_round_trip, r.linked_ride_id
       FROM bookings b
       JOIN users u ON b.passenger_id = u.id
       LEFT JOIN passenger_profiles pp ON pp.user_id = b.passenger_id
       JOIN rides r ON b.ride_id = r.id
       WHERE r.driver_id = ? AND b.status = 'pending'
       ORDER BY b.created_at DESC`,
      [driver_id]
    );
    res.json({ ok: true, data: rows });
  } catch (e) {
    console.error('getDriverBookingRequests error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const respondToBooking = async (req, res) => {
  const driver_id = req.user.uid;
  const { booking_id, action } = req.body;

  if (!['accepted', 'rejected'].includes(action)) {
    return res.status(400).json({ message: 'Action must be accepted or rejected' });
  }

  try {
    const [rows] = await pool.execute(
      `SELECT b.id, b.ride_id, b.passenger_id, b.seats_booked, b.status, b.booking_group_id
       FROM bookings b
       JOIN rides r ON b.ride_id = r.id
       WHERE b.id = ? AND r.driver_id = ?`,
      [booking_id, driver_id]
    );

    if (!rows.length) return res.status(404).json({ message: 'Booking not found.' });

    const booking = rows[0];
    if (booking.status !== 'pending') {
      return res.status(409).json({ message: 'This booking has already been responded to.' });
    }

    if (action === 'rejected' && booking.booking_group_id) {
      const [groupRows] = await pool.execute(
        `SELECT b.id, b.ride_id, b.seats_booked, b.status
         FROM bookings b
         JOIN rides r ON b.ride_id = r.id
         WHERE b.booking_group_id = ? AND b.passenger_id = ? AND r.driver_id = ?`,
        [booking.booking_group_id, booking.passenger_id, driver_id]
      );
      await cancelBookingsInRows(pool, groupRows);

      for (const row of groupRows) {
        try { await emitChatDisabled(io, row.id); } catch(e) { /* non-fatal */ }
      }

      (async () => {
        try {
          if (groupRows.length > 0) {
            const gRideIds = groupRows.map(r => r.ride_id);
            const gPh = gRideIds.map(() => '?').join(',');
            const [rdRows] = await pool.execute(
              `SELECT pickup_location, destination FROM rides WHERE id IN (${gPh})`,
              gRideIds
            );
            const routeParts = rdRows.map(r => `${r.pickup_location} → ${r.destination}`).join(' and ');
            const consolidatedBody = `Your round-trip bookings (${routeParts}) were rejected.`;
            await sendNotification(booking.passenger_id, {
              type: 'booking_rejected',
              title: 'Booking Rejected',
              body: consolidatedBody,
              payload: { booking_id: groupRows[0]?.id, ride_id: gRideIds[0] },
            });
          }
        } catch (e) { console.error('[Notification] respondToBooking group reject hook error', e); }
      })();
    } else {
      await pool.execute(`UPDATE bookings SET status = ? WHERE id = ?`, [action, booking_id]);

      if (action === 'rejected') {
        await pool.execute(
          `UPDATE rides SET available_seats = available_seats + ? WHERE id = ?`,
          [booking.seats_booked, booking.ride_id]
        );
        try { await emitChatDisabled(io, booking_id); } catch(e) { /* non-fatal */ }
      }

      if (action === 'accepted') {
        (async () => {
          try {
            const [[rd]] = await pool.execute(
              `SELECT pickup_location, destination, departure_time FROM rides WHERE id = ? LIMIT 1`,
              [booking.ride_id]
            );
            if (rd) {
              const depTime = rd.departure_time
                ? new Date(rd.departure_time).toLocaleString('en-US', { weekday:'short', day:'numeric', month:'short', hour:'numeric', minute:'2-digit', hour12:true })
                : '';
              const { title, body, payload } = buildMessage('booking_accepted', {
                pickup: rd.pickup_location, destination: rd.destination,
                departure_time: depTime, booking_id: booking_id, ride_id: booking.ride_id,
              });
              await sendNotification(booking.passenger_id, { type: 'booking_accepted', title, body, payload });
            }
          } catch (e) { console.error('[Notification] respondToBooking accept hook error', e); }
        })();
      } else if (action === 'rejected') {
        (async () => {
          try {
            const [[rd]] = await pool.execute(
              `SELECT pickup_location, destination FROM rides WHERE id = ? LIMIT 1`,
              [booking.ride_id]
            );
            if (rd) {
              const { title, body, payload } = buildMessage('booking_rejected', {
                pickup: rd.pickup_location, destination: rd.destination,
                booking_id: booking_id, ride_id: booking.ride_id,
              });
              await sendNotification(booking.passenger_id, { type: 'booking_rejected', title, body, payload });
            }
          } catch (e) { console.error('[Notification] respondToBooking reject hook error', e); }
        })();
      }
    }

    res.json({ ok: true, message: `Booking ${action} successfully.` });
  } catch (e) {
    console.error('respondToBooking error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const getPassengerBookings = async (req, res) => {
  const passenger_id = req.user.uid;
  try {
    const [rows] = await pool.execute(
      `SELECT b.id as booking_id, b.seats_booked, b.status as booking_status,
              b.booking_group_id, b.occurrence_id,
              b.created_at as requested_at,
              r.id as ride_id, r.pickup_location, r.destination,
              r.departure_time, r.fare, r.status as ride_status,
              r.leg_type, r.is_round_trip, r.linked_ride_id,
              r.is_recurring, r.recurrence_type,
              r.destination_lat, r.destination_lng,
              DATE_FORMAT(ro.occurrence_date, '%Y-%m-%d') as occurrence_date,
              DATE_FORMAT(ro.departure_datetime, '%Y-%m-%d %H:%i:%s') as departure_datetime,
              u.name as driver_name, u.phone as driver_phone,
              u.average_rating as driver_rating,
              dp.image_url as driver_image_url,
              v.make as car_make, v.model as car_model,
              v.color as car_color, v.plate_no as car_plate,
              rv.id as review_id, rv.rating as review_rating,
              rv.comment as review_comment, rv.created_at as review_created_at
       FROM bookings b
       JOIN rides r ON b.ride_id = r.id
       JOIN users u ON r.driver_id = u.id
       LEFT JOIN driver_profiles dp ON dp.user_id = r.driver_id
       LEFT JOIN vehicles v ON r.vehicle_id = v.id
       LEFT JOIN ride_occurrences ro ON ro.id = b.occurrence_id
       LEFT JOIN reviews rv ON rv.booking_id = b.id AND rv.reviewer_id = b.passenger_id
       WHERE b.passenger_id = ?
       ORDER BY b.created_at DESC`,
      [passenger_id]
    );
    res.json({ ok: true, data: rows });
  } catch (e) {
    console.error('getPassengerBookings error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const cancelPassengerBooking = async (req, res) => {
  const passenger_id = req.user.uid;
  const booking_id = req.params.bookingId;

  try {
    const [rows] = await pool.execute(
      `SELECT b.id, b.ride_id, b.seats_booked, b.status
       FROM bookings b
       WHERE b.id = ? AND b.passenger_id = ?`,
      [booking_id, passenger_id]
    );

    if (!rows.length) return res.status(404).json({ message: 'Booking not found.' });

    const booking = rows[0];
    if (booking.status === 'cancelled') {
      return res.status(409).json({ message: 'This booking is already cancelled.' });
    }

    await pool.execute(
      `UPDATE bookings SET status = 'cancelled' WHERE id = ?`,
      [booking.id]
    );
    await pool.execute(
      `UPDATE rides SET available_seats = available_seats + ? WHERE id = ?`,
      [booking.seats_booked, booking.ride_id]
    );
    try { await emitChatDisabled(io, booking_id); } catch(e) { /* non-fatal */ }

    (async () => {
      try {
        const [[rd]] = await pool.execute(
          `SELECT driver_id, pickup_location, destination FROM rides WHERE id = ? LIMIT 1`,
          [booking.ride_id]
        );
        const [[pax]] = await pool.execute(`SELECT name FROM users WHERE id = ? LIMIT 1`, [passenger_id]);
        if (rd) {
          const { title, body, payload } = buildMessage('booking_cancelled', {
            passenger_name: pax?.name ?? 'A passenger',
            seats: booking.seats_booked,
            pickup: rd.pickup_location, destination: rd.destination,
            booking_id: booking.id, ride_id: booking.ride_id,
          });
          await sendNotification(rd.driver_id, { type: 'booking_cancelled', title, body, payload });
        }
      } catch (e) { console.error('[Notification] cancelPassengerBooking hook error', e); }
    })();

    res.json({ ok: true, message: 'Booking cancelled successfully.' });
  } catch (e) {
    // ── Alert: cancellation failure ────────────────────────────────────────
    console.error('[ALERT] booking_cancellation_failed', {
      booking_id,
      passenger_id,
      error: e.message || e.sqlMessage,
    });
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const cancelPassengerBookingGroup = async (req, res) => {
  const passenger_id = req.user.uid;
  const booking_group_id = req.params.groupId;

  try {
    const [rows] = await pool.execute(
      `SELECT b.id, b.ride_id, b.seats_booked, b.status
       FROM bookings b
       WHERE b.booking_group_id = ? AND b.passenger_id = ?`,
      [booking_group_id, passenger_id]
    );

    if (!rows.length) return res.status(404).json({ message: 'Booking group not found.' });

    await cancelBookingsInRows(pool, rows);

    for (const row of rows) {
      try { await emitChatDisabled(io, row.id); } catch(e) { /* non-fatal */ }
    }

    (async () => {
      try {
        const [[pax]] = await pool.execute(`SELECT name FROM users WHERE id = ? LIMIT 1`, [passenger_id]);
        const passengerName = pax?.name ?? 'A passenger';
        for (const b of rows) {
          if (b.status === 'cancelled') continue;
          const [[rd]] = await pool.execute(
            `SELECT driver_id, pickup_location, destination FROM rides WHERE id = ? LIMIT 1`,
            [b.ride_id]
          );
          if (rd) {
            const { title, body, payload } = buildMessage('booking_cancelled', {
              passenger_name: passengerName,
              seats: b.seats_booked, pickup: rd.pickup_location, destination: rd.destination,
              booking_id: b.id, ride_id: b.ride_id,
            });
            await sendNotification(rd.driver_id, { type: 'booking_cancelled', title, body, payload });
          }
        }
      } catch (e) { console.error('[Notification] cancelPassengerBookingGroup hook error', e); }
    })();

    console.log('[METRIC] booking_group_cancelled', {
      booking_group_id,
      passenger_id,
      cancelled_count: rows.filter(r => r.status !== 'cancelled').length,
    });

    res.json({ ok: true, message: 'Round trip cancelled successfully.' });
  } catch (e) {
    // ── Alert: cancellation failure — transaction rolled back ──────────────
    console.error('[ALERT] booking_group_cancellation_failed', {
      booking_group_id,
      passenger_id,
      error: e.message || e.sqlMessage,
    });
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const getDriverRides = async (req, res) => {
  const driver_id = req.user.uid;
  try {
    // Non-recurring rides — one row per ride
    const [nonRecurring] = await pool.execute(
      `SELECT r.id as ride_id, r.pickup_location, r.destination, r.departure_time,
              r.total_seats, r.available_seats, r.fare, r.status, r.started_at,
              r.is_recurring, r.recurrence_type, r.is_round_trip, r.linked_ride_id as return_ride_id,
              NULL as occurrence_id,
              NULL as occurrence_date,
              NULL as departure_datetime,
              COUNT(CASE WHEN b.status = 'accepted' THEN 1 END) AS accepted_count,
              COUNT(CASE WHEN b.status = 'pending' THEN 1 END) AS pending_count,
              COALESCE(SUM(CASE WHEN b.status = 'accepted' THEN b.seats_booked ELSE 0 END), 0) AS booked_seats,
              COALESCE(SUM(CASE WHEN b.status = 'pending' THEN b.seats_booked ELSE 0 END), 0) AS pending_seats
       FROM rides r
       LEFT JOIN bookings b ON b.ride_id = r.id
       WHERE r.driver_id = ? AND r.is_recurring = 0
       GROUP BY r.id
       ORDER BY r.departure_time ASC`,
      [driver_id]
    );

    // Recurring rides — one row per occurrence (active)
    const [recurring] = await pool.execute(
      `SELECT r.id as ride_id, r.pickup_location, r.destination, r.departure_time,
              r.total_seats, r.fare, r.status, r.started_at,
              r.is_recurring, r.recurrence_type, r.is_round_trip, r.linked_ride_id as return_ride_id,
              ro.id as occurrence_id,
              DATE_FORMAT(ro.occurrence_date, '%Y-%m-%d') as occurrence_date,
              DATE_FORMAT(ro.departure_datetime, '%Y-%m-%d %H:%i:%s') as departure_datetime,
              ro.available_seats,
              ro.status as occurrence_status,
              COUNT(CASE WHEN b.status = 'accepted' THEN 1 END) AS accepted_count,
              COUNT(CASE WHEN b.status = 'pending' THEN 1 END) AS pending_count,
              COALESCE(SUM(CASE WHEN b.status = 'accepted' THEN b.seats_booked ELSE 0 END), 0) AS booked_seats,
              COALESCE(SUM(CASE WHEN b.status = 'pending' THEN b.seats_booked ELSE 0 END), 0) AS pending_seats
       FROM rides r
       JOIN ride_occurrences ro ON ro.ride_id = r.id
       LEFT JOIN bookings b ON b.ride_id = r.id AND b.occurrence_id = ro.id
       WHERE r.driver_id = ? AND r.is_recurring = 1
       GROUP BY ro.id
       ORDER BY ro.occurrence_date ASC, ro.departure_datetime ASC`,
      [driver_id]
    );

    res.json({ ok: true, data: [...nonRecurring, ...recurring] });
  } catch (e) {
    console.error('getDriverRides error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const getDriverRideDetails = async (req, res) => {
  const driver_id = req.user.uid;
  const ride_id = req.params.rideId;
  const occurrence_id = req.query.occurrence_id ? parseIntSafe(req.query.occurrence_id, 0) : null;
  try {
    const [[ride]] = await pool.execute(
      `SELECT r.id as ride_id, r.pickup_location, r.destination, r.departure_time,
              r.total_seats, r.available_seats, r.fare, r.status, r.started_at,
              r.is_recurring, r.recurrence_type,
              r.is_round_trip, r.round_trip_group_id, r.linked_ride_id, r.leg_type,
              v.make, v.model, v.color, v.plate_no, v.seats,
              u.name as driver_name, u.phone as driver_phone
       FROM rides r
       JOIN users u ON r.driver_id = u.id
       LEFT JOIN vehicles v ON r.vehicle_id = v.id
       WHERE r.id = ? AND r.driver_id = ? LIMIT 1`,
      [ride_id, driver_id]
    );

    if (!ride) return res.status(404).json({ message: 'Ride not found.' });

    // If an occurrence_id is provided, fetch only passengers for that occurrence.
    // Otherwise fetch all passengers for the ride.
    let passengersQuery;
    let passengersParams;

    if (occurrence_id) {
      passengersQuery = `
        SELECT b.id as booking_id, b.seats_booked, b.status as booking_status,
               b.created_at as requested_at,
               u.id as passenger_id, u.name as passenger_name,
               u.phone as passenger_phone, u.gender as passenger_gender,
               pp.image_url as passenger_image_url,
               DATE_FORMAT(ro.occurrence_date, '%Y-%m-%d') as occurrence_date,
               DATE_FORMAT(ro.departure_datetime, '%Y-%m-%d %H:%i:%s') as departure_datetime,
               rv.id as review_id, rv.rating as review_rating,
               rv.comment as review_comment, rv.created_at as review_created_at
        FROM bookings b
        JOIN users u ON b.passenger_id = u.id
        LEFT JOIN passenger_profiles pp ON pp.user_id = b.passenger_id
        LEFT JOIN ride_occurrences ro ON ro.id = b.occurrence_id
        LEFT JOIN reviews rv ON rv.booking_id = b.id AND rv.reviewer_id = ?
        WHERE b.ride_id = ? AND b.occurrence_id = ?
        ORDER BY b.created_at ASC`;
      passengersParams = [driver_id, ride_id, occurrence_id];
    } else {
      passengersQuery = `
        SELECT b.id as booking_id, b.seats_booked, b.status as booking_status,
               b.created_at as requested_at,
               u.id as passenger_id, u.name as passenger_name,
               u.phone as passenger_phone, u.gender as passenger_gender,
               pp.image_url as passenger_image_url,
               DATE_FORMAT(ro.occurrence_date, '%Y-%m-%d') as occurrence_date,
               DATE_FORMAT(ro.departure_datetime, '%Y-%m-%d %H:%i:%s') as departure_datetime,
               rv.id as review_id, rv.rating as review_rating,
               rv.comment as review_comment, rv.created_at as review_created_at
        FROM bookings b
        JOIN users u ON b.passenger_id = u.id
        LEFT JOIN passenger_profiles pp ON pp.user_id = b.passenger_id
        LEFT JOIN ride_occurrences ro ON ro.id = b.occurrence_id
        LEFT JOIN reviews rv ON rv.booking_id = b.id AND rv.reviewer_id = ?
        WHERE b.ride_id = ?
        ORDER BY ro.occurrence_date ASC, b.created_at ASC`;
      passengersParams = [driver_id, ride_id];
    }

    const [passengers] = await pool.execute(passengersQuery, passengersParams);

    const bookedSeats = passengers
      .filter((p) => p.booking_status === 'accepted')
      .reduce((sum, p) => sum + (parseInt(p.seats_booked, 10) || 0), 0);
    const pendingSeats = passengers
      .filter((p) => p.booking_status === 'pending')
      .reduce((sum, p) => sum + (parseInt(p.seats_booked, 10) || 0), 0);

    // For recurring rides, also fetch all upcoming occurrences
    let occurrences = [];
    if (ride.is_recurring) {
      const today = new Date().toISOString().slice(0, 10);
      const [occs] = await pool.execute(
        `SELECT id,
                DATE_FORMAT(occurrence_date, '%Y-%m-%d') as occurrence_date,
                DATE_FORMAT(departure_datetime, '%Y-%m-%d %H:%i:%s') as departure_datetime,
                available_seats, status
           FROM ride_occurrences
          WHERE ride_id = ?
          ORDER BY occurrence_date ASC`,
        [ride_id]
      );
      occurrences = occs;
    }

    res.json({
      ok: true,
      data: {
        ride,
        summary: {
          bookedSeats,
          pendingSeats,
          acceptedBookings: passengers.filter((p) => p.booking_status === 'accepted').length,
          pendingBookings: passengers.filter((p) => p.booking_status === 'pending').length,
        },
        passengers,
        occurrences,
      },
    });
  } catch (e) {
    console.error('getDriverRideDetails error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const submitRideReview = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });

  const reviewerId = req.user.uid;
  const bookingId = parseIntSafe(req.body.booking_id, 0);
  const rating = parseIntSafe(req.body.rating, 0);
  const comment = typeof req.body.comment === 'string' ? req.body.comment.trim() : '';

  if (!bookingId) {
    return res.status(400).json({ message: 'Booking is required.' });
  }
  if (rating < 1 || rating > 5) {
    return res.status(422).json({ message: 'Rating must be between 1 and 5.' });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    const eligibility = await getReviewEligibility(connection, bookingId, reviewerId);
    if (!eligibility.ok) {
      await connection.rollback();
      return res.status(eligibility.status).json({ message: eligibility.message });
    }

    const { ride_id, revieweeId } = eligibility.data;

    const [existing] = await connection.execute(
      `SELECT id FROM reviews WHERE booking_id = ? AND reviewer_id = ? LIMIT 1`,
      [bookingId, reviewerId]
    );
    if (existing.length) {
      await connection.rollback();
      return res.status(409).json({ message: 'You have already reviewed this ride.' });
    }

    const [insertResult] = await connection.execute(
      `INSERT INTO reviews (ride_id, booking_id, reviewer_id, reviewee_id, rating, comment)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [ride_id, bookingId, reviewerId, revieweeId, rating, comment || null]
    );

    await connection.execute(
      `UPDATE users
       SET rating_sum = rating_sum + ?,
           review_count = review_count + 1,
           average_rating = ROUND((rating_sum + ?) / (review_count + 1), 2)
       WHERE id = ?`,
      [rating, rating, revieweeId]
    );

    const [[reviewee]] = await connection.execute(
      `SELECT average_rating, review_count FROM users WHERE id = ? LIMIT 1`,
      [revieweeId]
    );

    await connection.commit();

    res.status(201).json({
      ok: true,
      message: 'Review submitted successfully.',
      data: {
        review_id: insertResult.insertId,
        reviewee_id: revieweeId,
        average_rating: reviewee?.average_rating ?? 0,
        review_count: reviewee?.review_count ?? 0,
      },
    });
  } catch (e) {
    await connection.rollback();
    if (e?.errno === 1062) {
      return res.status(409).json({ message: 'You have already reviewed this ride.' });
    }
    console.error('submitRideReview error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  } finally {
    connection.release();
  }
};

export const getReceivedReviews = async (req, res) => {
  const userId = req.user.uid;
  const { from, to, rating } = req.query;
  try {
    const params = [userId];
    let filters = `WHERE rv.reviewee_id = ?`;

    const fromDate = parseDateOnly(from);
    if (fromDate) {
      filters += ` AND DATE(rv.created_at) >= ?`;
      params.push(fromDate);
    }

    const toDate = parseDateOnly(to);
    if (toDate) {
      filters += ` AND DATE(rv.created_at) <= ?`;
      params.push(toDate);
    }

    const ratingValue = parseIntSafe(rating, 0);
    if (ratingValue >= 1 && ratingValue <= 5) {
      filters += ` AND rv.rating = ?`;
      params.push(ratingValue);
    }

    const [rows] = await pool.execute(
      `SELECT rv.id as review_id, rv.ride_id, rv.booking_id, rv.reviewer_id, rv.reviewee_id,
              rv.rating, rv.comment, rv.created_at,
              ru.name as reviewer_name, ru.role as reviewer_role,
              r.pickup_location, r.destination, r.departure_time, r.status as ride_status,
              b.status as booking_status
       FROM reviews rv
       JOIN users ru ON rv.reviewer_id = ru.id
       JOIN rides r ON rv.ride_id = r.id
       JOIN bookings b ON rv.booking_id = b.id
       ${filters}
       ORDER BY rv.created_at DESC`,
      params
    );

    const [[stats]] = await pool.execute(
      `SELECT average_rating, review_count FROM users WHERE id = ? LIMIT 1`,
      [userId]
    );

    res.json({ ok: true, data: rows, stats: stats || { average_rating: 0, review_count: 0 } });
  } catch (e) {
    console.error('getReceivedReviews error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const startDriverRide = async (req, res) => {
  const driver_id = req.user.uid;
  const ride_id = req.params.rideId;

  try {
    const [result] = await pool.execute(
      `UPDATE rides
         SET status = 'started',
             started_at = COALESCE(started_at, NOW())
         WHERE id = ? AND driver_id = ? AND status = 'active'`,
      [ride_id, driver_id]
    );

    if (result.affectedRows === 0) {
      return res.status(400).json({ message: 'Ride cannot be started.' });
    }

    (async () => {
      try {
        const [[driverRow]] = await pool.execute(
          `SELECT u.name, r.pickup_location, r.destination FROM rides r JOIN users u ON r.driver_id = u.id WHERE r.id = ? LIMIT 1`,
          [ride_id]
        );
        const [acceptedBookings] = await pool.execute(
          `SELECT id as booking_id, passenger_id FROM bookings WHERE ride_id = ? AND status = 'accepted'`,
          [ride_id]
        );
        if (driverRow) {
          for (const b of acceptedBookings) {
            const { title, body, payload } = buildMessage('ride_started', {
              driver_name: driverRow.name,
              pickup: driverRow.pickup_location, destination: driverRow.destination,
              ride_id,
            });
            await sendNotification(b.passenger_id, { type: 'ride_started', title, body, payload: { ...payload, booking_id: b.booking_id } });
          }
        }
      } catch (e) { console.error('[Notification] startDriverRide hook error', e); }
    })();

    // Emit real-time ride_started event to all tracking room members
    try { await emitRideEvent(io, ride_id, 'ride_started', { rideId: ride_id }); } catch (_) {}

    res.json({ ok: true, message: 'Ride started successfully.' });
  } catch (e) {
    console.error('startDriverRide error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const cancelDriverRide = async (req, res) => {
  const driver_id = req.user.uid;
  const ride_id = req.params.rideId;

  try {
    const [rideUpdate] = await pool.execute(
      `UPDATE rides
       SET status = 'cancelled',
           available_seats = total_seats
       WHERE id = ? AND driver_id = ? AND status = 'active'`,
      [ride_id, driver_id]
    );

    if (rideUpdate.affectedRows === 0) {
      return res.status(400).json({ message: 'Ride cannot be cancelled.' });
    }

    const [affectedPassengers] = await pool.execute(
      `SELECT id as booking_id, passenger_id FROM bookings WHERE ride_id = ? AND status IN ('pending', 'accepted')`,
      [ride_id]
    );

    await pool.execute(
      `UPDATE bookings
       SET status = 'cancelled'
       WHERE ride_id = ? AND status IN ('pending', 'accepted')`,
      [ride_id]
    );

    for (const b of affectedPassengers) {
      try { await emitChatDisabled(io, b.booking_id); } catch(e) { /* non-fatal */ }
    }

    (async () => {
      try {
        const [[rd]] = await pool.execute(
          `SELECT pickup_location, destination, departure_time FROM rides WHERE id = ? LIMIT 1`,
          [ride_id]
        );
        if (rd) {
          for (const b of affectedPassengers) {
            const depTime = rd.departure_time
              ? new Date(rd.departure_time).toLocaleString('en-US', { weekday:'short', day:'numeric', month:'short', hour:'numeric', minute:'2-digit', hour12:true })
              : '';
            const { title, body, payload } = buildMessage('ride_cancelled', {
              pickup: rd.pickup_location, destination: rd.destination,
              departure_time: depTime, ride_id,
            });
            await sendNotification(b.passenger_id, { type: 'ride_cancelled', title, body, payload: { ...payload, booking_id: b.booking_id } });
          }
        }
      } catch (e) { console.error('[Notification] cancelDriverRide hook error', e); }
    })();

    res.json({ ok: true, message: 'Ride cancelled successfully.' });
  } catch (e) {
    console.error('cancelDriverRide error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

/**
 * POST /rides/my-rides/:rideId/cancel-round-trip
 * Driver cancels both legs of a round trip in one action.
 */
export const cancelDriverRoundTrip = async (req, res) => {
  const driver_id = req.user.uid;
  const ride_id = req.params.rideId;

  try {
    // Get the ride and its round_trip_group_id
    const [[ride]] = await pool.execute(
      `SELECT id, round_trip_group_id FROM rides WHERE id = ? AND driver_id = ? LIMIT 1`,
      [ride_id, driver_id]
    );

    if (!ride) return res.status(404).json({ message: 'Ride not found.' });
    if (!ride.round_trip_group_id) {
      return res.status(400).json({ message: 'This ride is not part of a round trip.' });
    }

    // Cancel ALL rides in this round trip group that belong to this driver
    const [rideUpdate] = await pool.execute(
      `UPDATE rides
       SET status = 'cancelled', available_seats = total_seats
       WHERE round_trip_group_id = ? AND driver_id = ? AND status = 'active'`,
      [ride.round_trip_group_id, driver_id]
    );

    if (rideUpdate.affectedRows === 0) {
      return res.status(400).json({ message: 'Round trip cannot be cancelled.' });
    }

    // Get all ride IDs in the group
    const [groupRides] = await pool.execute(
      `SELECT id FROM rides WHERE round_trip_group_id = ? AND driver_id = ?`,
      [ride.round_trip_group_id, driver_id]
    );
    const groupRideIds = groupRides.map(r => r.id);
    const ph = groupRideIds.map(() => '?').join(',');

    // Cancel all bookings for these rides
    const [affectedPassengers] = await pool.execute(
      `SELECT id as booking_id, passenger_id, ride_id
         FROM bookings WHERE ride_id IN (${ph}) AND status IN ('pending', 'accepted')`,
      groupRideIds
    );

    await pool.execute(
      `UPDATE bookings SET status = 'cancelled'
         WHERE ride_id IN (${ph}) AND status IN ('pending', 'accepted')`,
      groupRideIds
    );

    // Notify affected passengers
    (async () => {
      try {
        for (const b of affectedPassengers) {
          const [[rd]] = await pool.execute(
            `SELECT pickup_location, destination, departure_time FROM rides WHERE id = ? LIMIT 1`,
            [b.ride_id]
          );
          if (rd) {
            const depTime = rd.departure_time
              ? new Date(rd.departure_time).toLocaleString('en-US', { weekday:'short', day:'numeric', month:'short', hour:'numeric', minute:'2-digit', hour12:true })
              : '';
            const { title, body, payload } = buildMessage('ride_cancelled', {
              pickup: rd.pickup_location, destination: rd.destination,
              departure_time: depTime, ride_id: b.ride_id,
            });
            await sendNotification(b.passenger_id, { type: 'ride_cancelled', title, body, payload: { ...payload, booking_id: b.booking_id } });
          }
        }
      } catch (e) { console.error('[Notification] cancelDriverRoundTrip hook error', e); }
    })();

    res.json({ ok: true, message: 'Round trip cancelled successfully.' });
  } catch (e) {
    console.error('cancelDriverRoundTrip error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const endDriverRide = async (req, res) => {
  const driver_id = req.user.uid;
  const ride_id = req.params.rideId;

  try {
    const [result] = await pool.execute(
      `UPDATE rides
       SET status = 'completed'
       WHERE id = ? AND driver_id = ? AND status = 'started'`,
      [ride_id, driver_id]
    );

    if (result.affectedRows === 0) {
      return res.status(400).json({ message: 'Ride cannot be ended.' });
    }

    // Mark all accepted bookings as completed
    await pool.execute(
      `UPDATE bookings SET status = 'completed' WHERE ride_id = ? AND status = 'accepted'`,
      [ride_id]
    );

    // Emit chat_disabled for every booking that was just completed
    const [completedForChat] = await pool.execute(
      `SELECT id FROM bookings WHERE ride_id = ? AND status = 'completed'`,
      [ride_id]
    );
    for (const b of completedForChat) {
      try { await emitChatDisabled(io, b.id); } catch(e) { /* non-fatal */ }
    }

    (async () => {
      try {
        const [[driverRow]] = await pool.execute(
          `SELECT u.name, r.pickup_location, r.destination FROM rides r JOIN users u ON r.driver_id = u.id WHERE r.id = ? LIMIT 1`,
          [ride_id]
        );
        const [completedBookings] = await pool.execute(
          `SELECT id as booking_id, passenger_id FROM bookings WHERE ride_id = ? AND status = 'completed'`,
          [ride_id]
        );
        if (driverRow) {
          for (const b of completedBookings) {
            const { title, body, payload } = buildMessage('ride_completed', {
              driver_name: driverRow.name,
              pickup: driverRow.pickup_location, destination: driverRow.destination,
              ride_id,
            });
            await sendNotification(b.passenger_id, { type: 'ride_completed', title, body, payload: { ...payload, booking_id: b.booking_id } });
          }
        }
      } catch (e) { console.error('[Notification] endDriverRide hook error', e); }
    })();

    // Emit real-time ride_ended event to all tracking room members
    try { await emitRideEvent(io, ride_id, 'ride_ended', { rideId: ride_id }); } catch (_) {}

    res.json({ ok: true, message: 'Ride ended successfully.' });
  } catch (e) {
    console.error('endDriverRide error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// Recurring-ride helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * GET /rides/:rideId/occurrences
 * Returns upcoming active occurrences for a recurring ride.
 * Query param: limit (default 30)
 */
export const getRideOccurrences = async (req, res) => {
  const rideId = parseIntSafe(req.params.rideId, 0);
  const limit  = parseIntSafe(req.query.limit, 30);
  try {
    const [[ride]] = await pool.execute(
      `SELECT id, is_recurring FROM rides WHERE id = ? LIMIT 1`,
      [rideId]
    );
    if (!ride) return res.status(404).json({ message: 'Ride not found.' });
    if (!ride.is_recurring) {
      return res.status(400).json({ message: 'This ride is not a recurring ride.' });
    }
    const occurrences = await getUpcomingOccurrences(rideId, limit);
    res.json({ ok: true, data: occurrences });
  } catch (e) {
    console.error('getRideOccurrences error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

/**
 * POST /rides/occurrences/:occurrenceId/cancel
 * Driver cancels a single occurrence of a recurring ride.
 */
export const cancelOccurrence = async (req, res) => {
  const driver_id    = req.user.uid;
  const occurrenceId = parseIntSafe(req.params.occurrenceId, 0);

  try {
    const [[occ]] = await pool.execute(
      `SELECT ro.id, ro.ride_id, ro.status, ro.occurrence_date, ro.departure_datetime,
              r.driver_id, r.pickup_location, r.destination
       FROM ride_occurrences ro
       JOIN rides r ON ro.ride_id = r.id
       WHERE ro.id = ? AND r.driver_id = ?
       LIMIT 1`,
      [occurrenceId, driver_id]
    );
    if (!occ) return res.status(404).json({ message: 'Occurrence not found.' });
    if (occ.status !== 'active') {
      return res.status(409).json({ message: 'Occurrence is already cancelled or completed.' });
    }

    await pool.execute(
      `UPDATE ride_occurrences SET status = 'cancelled' WHERE id = ?`,
      [occurrenceId]
    );

    // Cancel bookings for this occurrence and notify passengers
    const [affectedBookings] = await pool.execute(
      `SELECT id as booking_id, passenger_id FROM bookings
       WHERE occurrence_id = ? AND status IN ('pending','accepted')`,
      [occurrenceId]
    );
    if (affectedBookings.length) {
      await pool.execute(
        `UPDATE bookings SET status = 'cancelled'
         WHERE occurrence_id = ? AND status IN ('pending','accepted')`,
        [occurrenceId]
      );
      (async () => {
        try {
          const depTime = occ.departure_datetime
            ? new Date(occ.departure_datetime).toLocaleString('en-US', {
                weekday:'short', day:'numeric', month:'short',
                hour:'numeric', minute:'2-digit', hour12:true,
              })
            : '';
          for (const b of affectedBookings) {
            const { title, body, payload } = buildMessage('ride_cancelled', {
              pickup: occ.pickup_location, destination: occ.destination,
              departure_time: depTime, ride_id: occ.ride_id,
            });
            await sendNotification(b.passenger_id, {
              type: 'ride_cancelled', title, body,
              payload: { ...payload, booking_id: b.booking_id },
            });
          }
        } catch (e) { console.error('[Notification] cancelOccurrence hook error', e); }
      })();
    }

    res.json({ ok: true, message: 'Occurrence cancelled successfully.' });
  } catch (e) {
    console.error('cancelOccurrence error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

/**
 * POST /rides/:rideId/cancel-recurring
 * Driver cancels all future occurrences of an entire recurring series.
 */
export const cancelRecurringSeries = async (req, res) => {
  const driver_id = req.user.uid;
  const rideId    = parseIntSafe(req.params.rideId, 0);

  try {
    const [[ride]] = await pool.execute(
      `SELECT id, driver_id, is_recurring, recurrence_group_id,
              pickup_location, destination
       FROM rides WHERE id = ? AND driver_id = ? LIMIT 1`,
      [rideId, driver_id]
    );
    if (!ride) return res.status(404).json({ message: 'Ride not found.' });
    if (!ride.is_recurring) {
      return res.status(400).json({ message: 'This is not a recurring ride.' });
    }

    const today = new Date().toISOString().slice(0, 10);

    // Gather all ride IDs in the same recurrence group (departure + return legs)
    let rideIds = [rideId];
    if (ride.recurrence_group_id) {
      const [siblings] = await pool.execute(
        `SELECT id FROM rides WHERE recurrence_group_id = ?`,
        [ride.recurrence_group_id]
      );
      rideIds = siblings.map(r => r.id);
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      for (const rid of rideIds) {
        await cancelFutureOccurrences(conn, rid, today);
      }

      // Cancel the parent rides
      const ph = rideIds.map(() => '?').join(',');
      await conn.execute(
        `UPDATE rides SET status = 'cancelled' WHERE id IN (${ph})`,
        rideIds
      );

      // Gather and cancel future bookings
      const futureOccIds = [];
      for (const rid of rideIds) {
        const [occs] = await conn.execute(
          `SELECT id FROM ride_occurrences
           WHERE ride_id = ? AND occurrence_date >= ? AND status = 'cancelled'`,
          [rid, today]
        );
        futureOccIds.push(...occs.map(o => o.id));
      }

      if (futureOccIds.length) {
        const ph2 = futureOccIds.map(() => '?').join(',');
        const [affectedBookings] = await conn.execute(
          `SELECT id as booking_id, passenger_id FROM bookings
           WHERE occurrence_id IN (${ph2}) AND status IN ('pending','accepted')`,
          futureOccIds
        );
        if (affectedBookings.length) {
          await conn.execute(
            `UPDATE bookings SET status = 'cancelled'
             WHERE occurrence_id IN (${ph2}) AND status IN ('pending','accepted')`,
            futureOccIds
          );
          (async () => {
            try {
              const depTime = today;
              for (const b of affectedBookings) {
                const { title, body, payload } = buildMessage('ride_cancelled', {
                  pickup: ride.pickup_location, destination: ride.destination,
                  departure_time: depTime, ride_id: rideId,
                });
                await sendNotification(b.passenger_id, {
                  type: 'ride_cancelled', title, body,
                  payload: { ...payload, booking_id: b.booking_id },
                });
              }
            } catch (e) { console.error('[Notification] cancelRecurringSeries hook error', e); }
          })();
        }
      }

      await conn.commit();
      res.json({ ok: true, message: 'Recurring series cancelled successfully.' });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (e) {
    console.error('cancelRecurringSeries error', e);
    res.status(500).json({ message: e.sqlMessage || 'Internal server error' });
  }
};

export const getEta = async (req, res) => {
  const { originLat, originLng, destLat, destLng } = req.query;
  const oLat = parseFloat(originLat);
  const oLng = parseFloat(originLng);
  const dLat = parseFloat(destLat);
  const dLng = parseFloat(destLng);

  if (!Number.isFinite(oLat) || !Number.isFinite(oLng) ||
      !Number.isFinite(dLat) || !Number.isFinite(dLng)) {
    return res.status(400).json({ ok: false, message: 'originLat, originLng, destLat, destLng must be valid numbers' });
  }

  const result = await getDirections(oLat, oLng, dLat, dLng);
  if (!result) {
    return res.status(503).json({ ok: false, message: 'Could not fetch directions' });
  }
  res.json({ ok: true, data: result });
};

// ── Places Autocomplete proxy ─────────────────────────────────────────────────
// Keeps the API key server-side; Flutter never sees it.

export const getPlaces = async (req, res) => {
  const { input } = req.query;
  if (!input || typeof input !== 'string' || input.trim().length < 2) {
    return res.status(400).json({ ok: false, message: 'input must be at least 2 characters' });
  }

  const predictions = await getPlacesAutocomplete(input.trim());
  res.json({ ok: true, data: predictions });
};
