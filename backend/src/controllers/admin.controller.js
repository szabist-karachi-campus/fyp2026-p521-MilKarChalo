import { pool } from '../config/db.js';
import { sendNotification, buildMessage } from '../services/notification.service.js';

export const getAdminStats = async (req, res) => {
  try {
    const [[users]] = await pool.execute('SELECT COUNT(*) as count FROM users');
    const [[drivers]] = await pool.execute('SELECT COUNT(*) as count FROM driver_profiles WHERE verification_status="approved"');
    const [[rides]] = await pool.execute('SELECT COUNT(*) as count FROM rides WHERE status="active"');
    
    res.json({ ok: true, stats: { users: users.count, approvedDrivers: drivers.count, activeRides: rides.count } });
  } catch (e) {
    res.status(500).json({ message: 'Error fetching stats' });
  }
};

export const getPendingVerifications = async (req, res) => {
  try {
    const [drivers] = await pool.execute(
      `SELECT u.name, u.email, d.* FROM users u 
       JOIN driver_profiles d ON u.id = d.user_id 
       WHERE d.verification_status = 'pending'`
    );
    res.json({ ok: true, data: drivers });
  } catch (e) {
    res.status(500).json({ message: 'Database error' });
  }
};

export const getPendingDrivers = async (req, res) => {
  try {
    const [drivers] = await pool.execute(
      `SELECT u.id, u.name, u.email, u.phone, d.* FROM users u 
       JOIN driver_profiles d ON u.id = d.user_id 
       WHERE d.verification_status = 'pending'`
    );
    res.json({ ok: true, data: drivers });
  } catch (e) {
    res.status(500).json({ message: 'Database error' });
  }
};

export const updateDriverStatus = async (req, res) => {
  try {
    // Accept both 'userId' (from admin panel Flutter) and 'driver_id' (legacy)
    const driver_id = req.body.userId ?? req.body.driver_id;
    const { status } = req.body;
    
    if (!driver_id) {
      return res.status(400).json({ message: 'driver id is required' });
    }

    if (!['pending', 'approved', 'rejected', 'suspended'].includes(status)) {
      return res.status(400).json({ message: 'Invalid status' });
    }

    await pool.execute(
      'UPDATE driver_profiles SET verification_status = ? WHERE user_id = ?',
      [status, driver_id]
    );

    const notifTypeMap = { approved: 'driver_approved', rejected: 'driver_rejected', suspended: 'driver_suspended' };
    const notifType = notifTypeMap[status];
    if (notifType) {
      (async () => {
        try {
          const { title, body, payload } = buildMessage(notifType, { driver_id: Number(driver_id) });
          await sendNotification(Number(driver_id), { type: notifType, title, body, payload });
        } catch (e) { console.error('[Notification] updateDriverStatus hook error', e); }
      })();
    }

    res.json({ ok: true, message: `Driver ${status} successfully` });
  } catch (e) {
    res.status(500).json({ message: 'Database error' });
  }
};

export const getApprovedDrivers = async (req, res) => {
  try {
    const [drivers] = await pool.execute(
      `SELECT u.id, u.name, u.email, u.phone, u.gender, u.city,
              d.cnic, d.driving_license_no, d.insurance_no, d.address,
              d.image_url, d.verification_status,
              u.average_rating, u.review_count,
              v.make, v.model, v.color, v.plate_no, v.seats,
              COUNT(DISTINCT r.id) AS total_rides
       FROM users u
       JOIN driver_profiles d ON u.id = d.user_id
       LEFT JOIN vehicles v ON u.id = v.user_id
       LEFT JOIN rides r ON u.id = r.driver_id
       WHERE d.verification_status = 'approved'
      GROUP BY u.id, d.cnic, d.driving_license_no, d.insurance_no,
          d.address, d.image_url, d.verification_status,
          u.average_rating, u.review_count,
                v.make, v.model, v.color, v.plate_no, v.seats`
    );
    res.json({ ok: true, data: drivers });
  } catch (e) {
    console.error('getApprovedDrivers error', e);
    res.status(500).json({ message: 'Database error' });
  }
};

export const getAllDrivers = async (req, res) => {
  try {
    const [drivers] = await pool.execute(
      `SELECT u.id, u.name, u.email, u.phone, u.gender, u.city,
              d.cnic, d.driving_license_no, d.insurance_no, d.address,
              d.image_url, d.verification_status,
              u.average_rating, u.review_count,
              v.make, v.model, v.color, v.plate_no, v.seats,
              COUNT(DISTINCT r.id) AS total_rides
       FROM users u
       JOIN driver_profiles d ON u.id = d.user_id
       LEFT JOIN vehicles v ON u.id = v.user_id
       LEFT JOIN rides r ON u.id = r.driver_id
      GROUP BY u.id, d.cnic, d.driving_license_no, d.insurance_no,
          d.address, d.image_url, d.verification_status,
          u.average_rating, u.review_count,
                v.make, v.model, v.color, v.plate_no, v.seats`
    );
    res.json({ ok: true, data: drivers });
  } catch (e) {
    console.error('getAllDrivers error', e);
    res.status(500).json({ message: 'Database error' });
  }
};

export const getDriverRides = async (req, res) => {
  try {
    const driverId = req.params.driverId;
    const [rides] = await pool.execute(
      `SELECT r.id as ride_id, r.driver_id, r.pickup_location, r.destination, r.departure_time,
              r.total_seats, r.available_seats, r.fare, r.status,
              COUNT(b.id) AS booking_count,
              SUM(CASE WHEN b.status = 'accepted' THEN b.seats_booked ELSE 0 END) AS booked_seats,
              SUM(CASE WHEN b.status = 'pending' THEN b.seats_booked ELSE 0 END) AS pending_seats
       FROM rides r
       LEFT JOIN bookings b ON r.id = b.ride_id
       WHERE r.driver_id = ?
       GROUP BY r.id
       ORDER BY r.departure_time ASC`,
      [driverId]
    );
    res.json({ ok: true, data: rides });
  } catch (e) {
    console.error('getDriverRides error', e);
    res.status(500).json({ message: 'Database error' });
  }
};

export const getRideDetailsAdmin = async (req, res) => {
  try {
    const rideId = req.params.rideId;
    const [[rideRows]] = await pool.execute(
      `SELECT r.*, u.name as driver_name, u.email as driver_email
       FROM rides r
       JOIN users u ON r.driver_id = u.id
       WHERE r.id = ? LIMIT 1`,
      [rideId]
    );

    if (!rideRows) return res.status(404).json({ message: 'Ride not found' });

    const [bookings] = await pool.execute(
      `SELECT b.id as booking_id, b.passenger_id, b.status as booking_status, b.seats_booked,
              u.name as passenger_name, u.email as passenger_email, u.phone as passenger_phone
       FROM bookings b
       JOIN users u ON b.passenger_id = u.id
       WHERE b.ride_id = ?
       ORDER BY b.created_at ASC`,
      [rideId]
    );

    res.json({ ok: true, data: { ride: rideRows, bookings } });
  } catch (e) {
    console.error('getRideDetailsAdmin error', e);
    res.status(500).json({ message: 'Database error' });
  }
};

export const updateBookingStatus = async (req, res) => {
  try {
    const bookingId = req.params.bookingId;
    const { status } = req.body;
    if (!['accepted', 'rejected', 'cancelled'].includes(status)) {
      return res.status(400).json({ message: 'Invalid booking status' });
    }

    const [result] = await pool.execute(
      `UPDATE bookings SET status = ? WHERE id = ?`,
      [status, bookingId]
    );

    if (result.affectedRows === 0) return res.status(404).json({ message: 'Booking not found' });

    res.json({ ok: true, message: 'Booking status updated' });
  } catch (e) {
    console.error('updateBookingStatus error', e);
    res.status(500).json({ message: 'Database error' });
  }
};

export const changeRideStatus = async (req, res) => {
  try {
    const rideId = req.params.rideId;
    const { status } = req.body;
    if (!['active', 'started', 'completed', 'canceled', 'cancelled'].includes(status)) {
      return res.status(400).json({ message: 'Invalid ride status' });
    }

    const [[currentRide]] = await pool.execute(
      `SELECT status FROM rides WHERE id = ? LIMIT 1`,
      [rideId]
    );

    if (!currentRide) return res.status(404).json({ message: 'Ride not found' });

    const currentStatus = (currentRide.status || '').toLowerCase();
    if (['completed', 'canceled', 'cancelled'].includes(currentStatus)) {
      return res.status(409).json({ message: 'Completed or canceled rides cannot be modified' });
    }

    const [result] = await pool.execute(
      `UPDATE rides SET status = ? WHERE id = ?`,
      [status, rideId]
    );

    if (result.affectedRows === 0) return res.status(404).json({ message: 'Ride not found' });

    // If ride is cancelled by admin, cancel pending/accepted bookings
    if (status === 'canceled' || status === 'cancelled') {
      const [rideCancelPassengers] = await pool.execute(
        `SELECT id as booking_id, passenger_id FROM bookings WHERE ride_id = ? AND status IN ('pending','accepted')`,
        [rideId]
      );

      await pool.execute(
        `UPDATE bookings SET status = 'cancelled' WHERE ride_id = ? AND status IN ('pending','accepted')`,
        [rideId]
      );

      (async () => {
        try {
          const [[rd]] = await pool.execute(
            `SELECT pickup_location, destination, departure_time FROM rides WHERE id = ? LIMIT 1`,
            [rideId]
          );
          if (rd) {
            for (const b of rideCancelPassengers) {
              const depTime = rd.departure_time
                ? new Date(rd.departure_time).toLocaleString('en-US', { weekday:'short', day:'numeric', month:'short', hour:'numeric', minute:'2-digit', hour12:true })
                : '';
              const { title, body, payload } = buildMessage('ride_cancelled', {
                pickup: rd.pickup_location, destination: rd.destination,
                departure_time: depTime, ride_id: rideId,
              });
              await sendNotification(b.passenger_id, { type: 'ride_cancelled', title, body, payload: { ...payload, booking_id: b.booking_id } });
            }
          }
        } catch (e) { console.error('[Notification] changeRideStatus cancel hook error', e); }
      })();
    }

    res.json({ ok: true, message: 'Ride status updated' });
  } catch (e) {
    console.error('changeRideStatus error', e);
    res.status(500).json({ message: 'Database error' });
  }
};

export const exportRideCsv = async (req, res) => {
  try {
    const rideId = req.params.rideId;
    const [[ride]] = await pool.execute(
      `SELECT r.*, u.name as driver_name, u.email as driver_email FROM rides r JOIN users u ON r.driver_id = u.id WHERE r.id = ? LIMIT 1`,
      [rideId]
    );
    if (!ride) return res.status(404).json({ message: 'Ride not found' });

    const [bookings] = await pool.execute(
      `SELECT b.id as booking_id, b.status as booking_status, b.seats_booked, u.id as passenger_id, u.name as passenger_name, u.email as passenger_email, u.phone as passenger_phone
       FROM bookings b JOIN users u ON b.passenger_id = u.id WHERE b.ride_id = ? ORDER BY b.created_at ASC`,
      [rideId]
    );

    // Build CSV content
    const headers = ['booking_id', 'passenger_id', 'passenger_name', 'passenger_email', 'passenger_phone', 'seats_booked', 'booking_status'];
    const rows = bookings.map(b => headers.map(h => (b[h] ?? '').toString()).join(','));
    const csv = headers.join(',') + '\n' + rows.join('\n');

    res.json({ ok: true, data: { ride, csv } });
  } catch (e) {
    console.error('exportRideCsv error', e);
    res.status(500).json({ message: 'Database error' });
  }
};

export const getAdminReviews = async (req, res) => {
  try {
    const { driverId, rating, from, to, search } = req.query;
    const params = [];
    const clauses = [];

    if (driverId) {
      clauses.push('rv.reviewee_id = ?');
      params.push(driverId);
    }

    const ratingValue = parseInt(rating, 10);
    if (Number.isInteger(ratingValue) && ratingValue >= 1 && ratingValue <= 5) {
      clauses.push('rv.rating = ?');
      params.push(ratingValue);
    }

    if (from) {
      clauses.push('DATE(rv.created_at) >= ?');
      params.push(from);
    }

    if (to) {
      clauses.push('DATE(rv.created_at) <= ?');
      params.push(to);
    }

    if (search) {
      clauses.push(`(
        ru.name LIKE ? OR
        rr.name LIKE ? OR
        r.pickup_location LIKE ? OR
        r.destination LIKE ? OR
        rv.comment LIKE ?
      )`);
      const like = `%${search}%`;
      params.push(like, like, like, like, like);
    }

    const whereClause = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';

    // Use pool.query (not pool.execute) for dynamic WHERE — mysql2's prepared
    // statement cache in execute() breaks when the number of ? changes per call.
    const [rows] = await pool.query(
      `SELECT rv.id as review_id, rv.ride_id, rv.booking_id, rv.reviewer_id, rv.reviewee_id,
              rv.rating, rv.comment, rv.created_at,
              rr.name as reviewee_name, rr.role as reviewee_role,
              ru.name as reviewer_name, ru.role as reviewer_role,
              r.pickup_location, r.destination, r.departure_time, r.status as ride_status,
              u.average_rating as reviewee_average_rating, u.review_count as reviewee_review_count
       FROM reviews rv
       JOIN users rr ON rv.reviewee_id = rr.id
       JOIN users ru ON rv.reviewer_id = ru.id
       JOIN rides r ON rv.ride_id = r.id
       JOIN users u ON rv.reviewee_id = u.id
       ${whereClause}
       ORDER BY rv.created_at DESC`,
      params
    );

    const [[summary]] = await pool.query(
      `SELECT COUNT(*) as review_count, COALESCE(ROUND(AVG(rating), 2), 0) as average_rating
       FROM reviews rv
       ${driverId ? 'WHERE rv.reviewee_id = ?' : ''}`,
      driverId ? [driverId] : []
    );

    res.json({ ok: true, data: rows, summary });
  } catch (e) {
    console.error('getAdminReviews error', e);
    res.status(500).json({ message: 'Database error' });
  }
};
