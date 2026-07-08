/**
 * Recurrence Service
 * ------------------
 * Generates ride_occurrences rows for a recurring ride and handles
 * cancellation of future occurrences.
 */

import { pool } from '../config/db.js';

// ISO weekday: 1 = Monday … 7 = Sunday  (same as spec's day_of_week)
const ISO_DAY = { 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 0 };

/**
 * Return an array of ISO date strings (YYYY-MM-DD) for every occurrence
 * of a recurring ride between startDate and endDate (inclusive).
 *
 * @param {'daily'|'weekly'|'custom'} type
 * @param {number[]} daysOfWeek  1–7 (Mon–Sun), only used for weekly/custom
 * @param {string}   startDate   YYYY-MM-DD
 * @param {string}   endDate     YYYY-MM-DD
 * @returns {string[]}
 */
export function generateOccurrenceDates(type, daysOfWeek, startDate, endDate) {
  const dates = [];
  const end = new Date(endDate + 'T00:00:00Z');
  const cur = new Date(startDate + 'T00:00:00Z');

  // Guard: maximum 12-month window
  const maxEnd = new Date(cur);
  maxEnd.setUTCFullYear(maxEnd.getUTCFullYear() + 1);
  const effectiveEnd = end < maxEnd ? end : maxEnd;

  while (cur <= effectiveEnd) {
    const iso = cur.toISOString().slice(0, 10);

    if (type === 'daily') {
      dates.push(iso);
    } else {
      // weekly / custom — check day-of-week
      // getUTCDay() returns 0=Sun, 1=Mon … 6=Sat
      // convert to spec's 1=Mon … 7=Sun
      const utcDay = cur.getUTCDay();           // 0=Sun
      const specDay = utcDay === 0 ? 7 : utcDay; // 7=Sun
      if (daysOfWeek.includes(specDay)) {
        dates.push(iso);
      }
    }

    cur.setUTCDate(cur.getUTCDate() + 1);
  }

  return dates;
}

/**
 * Insert ride_occurrences rows for a ride.
 *
 * @param {object} connection  MySQL pooled connection (inside a transaction)
 * @param {number} rideId
 * @param {number} totalSeats
 * @param {string} departureTimeStr  HH:MM or HH:MM:SS (the ride's daily departure time)
 * @param {string[]} occurrenceDates Array of YYYY-MM-DD strings
 */
export async function insertOccurrences(connection, rideId, totalSeats, departureTimeStr, occurrenceDates) {
  for (const date of occurrenceDates) {
    const departureDatetime = `${date} ${departureTimeStr}`;
    await connection.execute(
      `INSERT INTO ride_occurrences
         (ride_id, occurrence_date, departure_datetime, available_seats, status)
       VALUES (?, ?, ?, ?, 'active')`,
      [rideId, date, departureDatetime, totalSeats]
    );
  }
  console.log('[METRIC] occurrences_inserted', {
    ride_id: rideId,
    occurrence_count: occurrenceDates.length,
    departure_time: departureTimeStr,
    first_date: occurrenceDates[0] ?? null,
    last_date: occurrenceDates[occurrenceDates.length - 1] ?? null,
  });
}

/**
 * Cancel all future active occurrences for a ride (used when the parent ride
 * or the entire recurring series is cancelled).
 *
 * @param {object} conn      MySQL connection
 * @param {number} rideId
 * @param {string} [fromDate] YYYY-MM-DD  (default: today)
 */
export async function cancelFutureOccurrences(conn, rideId, fromDate) {
  const from = fromDate ?? new Date().toISOString().slice(0, 10);
  await conn.execute(
    `UPDATE ride_occurrences
       SET status = 'cancelled'
     WHERE ride_id = ?
       AND occurrence_date >= ?
       AND status = 'active'`,
    [rideId, from]
  );
}

/**
 * Get upcoming active occurrences for a ride.
 *
 * @param {number} rideId
 * @param {number} [limit=30]
 * @returns {Promise<Array>}
 */
export async function getUpcomingOccurrences(rideId, limit = 30) {
  const today = new Date().toISOString().slice(0, 10);
  const [rows] = await pool.execute(
    `SELECT id,
            DATE_FORMAT(occurrence_date, '%Y-%m-%d') as occurrence_date,
            DATE_FORMAT(departure_datetime, '%Y-%m-%d %H:%i:%s') as departure_datetime,
            available_seats,
            status
       FROM ride_occurrences
      WHERE ride_id = ?
        AND occurrence_date >= ?
        AND status = 'active'
      ORDER BY occurrence_date ASC
      LIMIT ?`,
    [rideId, today, limit]
  );
  return rows;
}

/**
 * Validate that a return occurrence is properly paired with a departure occurrence.
 * Checks that:
 * 1. Both occurrences are on the same calendar date
 * 2. The return occurrence belongs to a ride linked to the departure ride
 *
 * @param {object} connection  MySQL connection
 * @param {number} departureOccurrenceId  ID of the departure occurrence
 * @param {number} returnOccurrenceId     ID of the return occurrence
 * @returns {Promise<{ok: boolean, error?: string}>}  Validation result
 */
export async function validateOccurrencePairing(connection, departureOccurrenceId, returnOccurrenceId) {
  try {
    // Fetch departure occurrence details with its ride info
    const [[depOccurrence]] = await connection.execute(
      `SELECT ro.id, ro.occurrence_date, ro.ride_id, r.linked_ride_id, r.leg_type
       FROM ride_occurrences ro
       JOIN rides r ON ro.ride_id = r.id
       WHERE ro.id = ?`,
      [departureOccurrenceId]
    );

    if (!depOccurrence) {
      return { ok: false, error: 'Departure occurrence not found.' };
    }

    if (depOccurrence.leg_type !== 'departure') {
      return { ok: false, error: 'First occurrence must be from a departure leg.' };
    }

    // Fetch return occurrence details with its ride info
    const [[retOccurrence]] = await connection.execute(
      `SELECT ro.id, ro.occurrence_date, ro.ride_id, r.leg_type, r.linked_ride_id
       FROM ride_occurrences ro
       JOIN rides r ON ro.ride_id = r.id
       WHERE ro.id = ?`,
      [returnOccurrenceId]
    );

    if (!retOccurrence) {
      return { ok: false, error: 'Return occurrence not found.' };
    }

    if (retOccurrence.leg_type !== 'return') {
      return { ok: false, error: 'Second occurrence must be from a return leg.' };
    }

    // Check 1: Same calendar date
    const depDate = depOccurrence.occurrence_date.toISOString ? 
      depOccurrence.occurrence_date.toISOString().slice(0, 10) : 
      depOccurrence.occurrence_date;
    const retDate = retOccurrence.occurrence_date.toISOString ? 
      retOccurrence.occurrence_date.toISOString().slice(0, 10) : 
      retOccurrence.occurrence_date;

    if (depDate !== retDate) {
      return { ok: false, error: `Return occurrence must be from the same date as departure (departure: ${depDate}, return: ${retDate}).` };
    }

    // Check 2: Return ride is linked to departure ride
    if (depOccurrence.linked_ride_id !== retOccurrence.ride_id) {
      return { ok: false, error: 'Return occurrence does not belong to the paired return ride.' };
    }

    return { ok: true };
  } catch (e) {
    return { ok: false, error: e.message || 'Error validating occurrence pairing.' };
  }
}
