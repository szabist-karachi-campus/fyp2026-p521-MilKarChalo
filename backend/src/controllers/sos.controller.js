import { pool } from '../config/db.js';
import { sendSmsToMany } from '../services/sms.service.js';

// ─── Emergency Contacts ───────────────────────────────────────────────────────

export const getEmergencyContacts = async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT id, name, phone, relationship FROM emergency_contacts WHERE user_id = ? ORDER BY id ASC`,
      [req.user.uid]
    );
    res.json({ ok: true, data: rows });
  } catch (e) {
    console.error('getEmergencyContacts error', e);
    res.status(500).json({ message: 'Internal server error' });
  }
};

export const addEmergencyContact = async (req, res) => {
  const { name, phone, relationship } = req.body;
  if (!name || !phone) {
    return res.status(400).json({ message: 'Name and phone are required.' });
  }
  try {
    const [result] = await pool.execute(
      `INSERT INTO emergency_contacts (user_id, name, phone, relationship) VALUES (?, ?, ?, ?)`,
      [req.user.uid, name.trim(), phone.trim(), relationship?.trim() || null]
    );
    res.status(201).json({ ok: true, data: { id: result.insertId, name, phone, relationship } });
  } catch (e) {
    console.error('addEmergencyContact error', e);
    res.status(500).json({ message: 'Internal server error' });
  }
};

export const updateEmergencyContact = async (req, res) => {
  const { id } = req.params;
  const { name, phone, relationship } = req.body;
  if (!name || !phone) {
    return res.status(400).json({ message: 'Name and phone are required.' });
  }
  try {
    const [result] = await pool.execute(
      `UPDATE emergency_contacts SET name = ?, phone = ?, relationship = ? WHERE id = ? AND user_id = ?`,
      [name.trim(), phone.trim(), relationship?.trim() || null, id, req.user.uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ message: 'Contact not found.' });
    res.json({ ok: true, message: 'Contact updated.' });
  } catch (e) {
    console.error('updateEmergencyContact error', e);
    res.status(500).json({ message: 'Internal server error' });
  }
};

export const deleteEmergencyContact = async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await pool.execute(
      `DELETE FROM emergency_contacts WHERE id = ? AND user_id = ?`,
      [id, req.user.uid]
    );
    if (result.affectedRows === 0) return res.status(404).json({ message: 'Contact not found.' });
    res.json({ ok: true, message: 'Contact removed.' });
  } catch (e) {
    console.error('deleteEmergencyContact error', e);
    res.status(500).json({ message: 'Internal server error' });
  }
};

// ─── SOS Events ───────────────────────────────────────────────────────────────

export const activateSos = async (req, res) => {
  const user_id = req.user.uid;
  const { booking_id, latitude, longitude } = req.body;

  if (!booking_id) return res.status(400).json({ message: 'booking_id is required.' });

  try {
    // Verify the user is a participant in this booking
    const [[booking]] = await pool.execute(
      `SELECT b.id, b.ride_id, b.passenger_id, r.driver_id, b.status AS booking_status, r.status AS ride_status
       FROM bookings b JOIN rides r ON r.id = b.ride_id
       WHERE b.id = ?`,
      [booking_id]
    );
    if (!booking) return res.status(404).json({ message: 'Booking not found.' });

    const isParticipant = String(user_id) === String(booking.passenger_id) ||
                          String(user_id) === String(booking.driver_id);
    if (!isParticipant) return res.status(403).json({ message: 'Access denied.' });

    // Only allow SOS on active bookings
    const allowedRideStatuses = ['active', 'started'];
    if (booking.booking_status !== 'accepted' || !allowedRideStatuses.includes(booking.ride_status)) {
      return res.status(403).json({ message: 'SOS is only available during an active ride.' });
    }

    // Prevent duplicate active SOS
    const [[existing]] = await pool.execute(
      `SELECT id FROM sos_events WHERE user_id = ? AND booking_id = ? AND status = 'active'`,
      [user_id, booking_id]
    );
    if (existing) {
      return res.status(409).json({ message: 'SOS is already active for this booking.', sos_id: existing.id });
    }

    const role = String(user_id) === String(booking.passenger_id) ? 'passenger' : 'driver';

    const [result] = await pool.execute(
      `INSERT INTO sos_events (user_id, booking_id, ride_id, role, status, latitude, longitude)
       VALUES (?, ?, ?, ?, 'active', ?, ?)`,
      [user_id, booking_id, booking.ride_id, role, latitude || null, longitude || null]
    );
    const sos_id = result.insertId;

    // Log first location if provided
    if (latitude && longitude) {
      await pool.execute(
        `INSERT INTO sos_locations (sos_id, latitude, longitude) VALUES (?, ?, ?)`,
        [sos_id, latitude, longitude]
      );
    }

    // Fetch emergency contacts + user info for notification
    // Fetch emergency contacts from the existing profile tables
    // passenger_profiles and driver_profiles both have emergency_contact_name + emergency_contact_phone
    let contacts = [];

    // Try passenger profile first
    const [[pp]] = await pool.execute(
      `SELECT emergency_contact_name AS name, emergency_contact_phone AS phone
       FROM passenger_profiles WHERE user_id = ? LIMIT 1`,
      [user_id]
    );
    if (pp && pp.phone) contacts.push(pp);

    // Try driver profile
    const [[dp]] = await pool.execute(
      `SELECT emergency_contact_name AS name, emergency_contact_phone AS phone
       FROM driver_profiles WHERE user_id = ? LIMIT 1`,
      [user_id]
    );
    if (dp && dp.phone) contacts.push(dp);

    // Also check the dedicated emergency_contacts table (if user added any via the app)
    const [ecRows] = await pool.execute(
      `SELECT name, phone FROM emergency_contacts WHERE user_id = ?`,
      [user_id]
    );
    contacts = [...contacts, ...ecRows.filter(c => c.phone)];

    const [[user]] = await pool.execute(`SELECT name FROM users WHERE id = ? LIMIT 1`, [user_id]);

    const now = new Date().toLocaleString('en-US', {
      weekday: 'short', day: 'numeric', month: 'short',
      hour: 'numeric', minute: '2-digit', hour12: true,
    });

    const mapLink = (latitude && longitude)
      ? `https://maps.google.com/?q=${latitude},${longitude}`
      : null;

    const alertMessage = [
      `🚨 SOS EMERGENCY ALERT`,
      ``,
      `${user?.name || 'A user'} (${role}) has activated an emergency alert during an active ride.`,
      ``,
      `Ride ID: ${booking.ride_id}`,
      `Booking ID: ${booking_id}`,
      `Time: ${now}`,
      latitude && longitude ? `Location: ${latitude}, ${longitude}` : `Location: Being fetched...`,
      mapLink ? `Map: ${mapLink}` : `A live location update with map link will follow shortly.`,
      ``,
      `Live location sharing has started. Please check on them immediately.`,
    ].filter(Boolean).join('\n');

    // Send SMS alerts to all emergency contacts
    const phones = contacts.map(c => c.phone).filter(Boolean);
    let contactsNotified = 0;
    if (phones.length > 0) {
      const { sent } = await sendSmsToMany(phones, alertMessage);
      contactsNotified = sent;
    } else {
      console.log(`[SOS] No emergency contacts for user ${user_id} — no SMS sent.`);
    }

    res.status(201).json({
      ok: true,
      message: 'SOS activated. Emergency contacts notified.',
      data: {
        sos_id,
        contacts_notified: contactsNotified,
        alert_message: alertMessage,
      },
    });
  } catch (e) {
    console.error('activateSos error', e);
    res.status(500).json({ message: 'Internal server error' });
  }
};

export const deactivateSos = async (req, res) => {
  const user_id = req.user.uid;
  const { sos_id } = req.params;

  try {
    const [[sos]] = await pool.execute(
      `SELECT id, user_id, status FROM sos_events WHERE id = ?`,
      [sos_id]
    );
    if (!sos) return res.status(404).json({ message: 'SOS event not found.' });
    if (String(sos.user_id) !== String(user_id)) {
      return res.status(403).json({ message: 'Access denied.' });
    }
    if (sos.status !== 'active') {
      return res.status(409).json({ message: 'SOS is not currently active.' });
    }

    await pool.execute(
      `UPDATE sos_events SET status = 'resolved', deactivated_at = NOW() WHERE id = ?`,
      [sos_id]
    );
    res.json({ ok: true, message: 'SOS deactivated.' });
  } catch (e) {
    console.error('deactivateSos error', e);
    res.status(500).json({ message: 'Internal server error' });
  }
};

export const getActiveSos = async (req, res) => {
  const user_id = req.user.uid;
  const { booking_id } = req.params;

  try {
    const [[sos]] = await pool.execute(
      `SELECT id, status, latitude, longitude, activated_at
       FROM sos_events WHERE user_id = ? AND booking_id = ? AND status = 'active'
       ORDER BY activated_at DESC LIMIT 1`,
      [user_id, booking_id]
    );
    res.json({ ok: true, data: sos || null });
  } catch (e) {
    console.error('getActiveSos error', e);
    res.status(500).json({ message: 'Internal server error' });
  }
};

export const updateSosLocation = async (req, res) => {
  const user_id = req.user.uid;
  const { sos_id } = req.params;
  const { latitude, longitude } = req.body;

  if (!latitude || !longitude) {
    return res.status(400).json({ message: 'latitude and longitude are required.' });
  }

  try {
    const [[sos]] = await pool.execute(
      `SELECT id, user_id, status FROM sos_events WHERE id = ? AND status = 'active'`,
      [sos_id]
    );
    if (!sos) return res.status(404).json({ message: 'Active SOS not found.' });
    if (String(sos.user_id) !== String(user_id)) {
      return res.status(403).json({ message: 'Access denied.' });
    }

    // Update latest location on the event
    await pool.execute(
      `UPDATE sos_events SET latitude = ?, longitude = ? WHERE id = ?`,
      [latitude, longitude, sos_id]
    );
    // Log to history
    await pool.execute(
      `INSERT INTO sos_locations (sos_id, latitude, longitude) VALUES (?, ?, ?)`,
      [sos_id, latitude, longitude]
    );

    res.json({ ok: true });
  } catch (e) {
    console.error('updateSosLocation error', e);
    res.status(500).json({ message: 'Internal server error' });
  }
};

// ─── Admin: all SOS events ────────────────────────────────────────────────────

export const getAdminSosEvents = async (req, res) => {
  try {
    const { status, from, to, search } = req.query;
    const params = [];
    const clauses = [];

    if (status && ['active', 'resolved'].includes(status)) {
      clauses.push('se.status = ?');
      params.push(status);
    }
    if (from) {
      clauses.push('DATE(se.activated_at) >= ?');
      params.push(from);
    }
    if (to) {
      clauses.push('DATE(se.activated_at) <= ?');
      params.push(to);
    }
    if (search) {
      clauses.push(`(u.name LIKE ? OR u.email LIKE ? OR u.phone LIKE ?)`);
      const like = `%${search}%`;
      params.push(like, like, like);
    }

    const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';

    // Use pool.query (not pool.execute) — dynamic WHERE means the number of ?
    // changes per call, which breaks mysql2's prepared-statement cache in execute().
    const [rows] = await pool.query(
      `SELECT
         se.id           AS sos_id,
         se.user_id,
         se.booking_id,
         se.ride_id,
         se.role,
         se.status,
         se.latitude,
         se.longitude,
         se.activated_at,
         se.deactivated_at,
         u.name          AS user_name,
         u.email         AS user_email,
         u.phone         AS user_phone,
         r.pickup_location,
         r.destination,
         r.departure_time,
         driver.name     AS driver_name,
         driver.phone    AS driver_phone
       FROM sos_events se
       JOIN users u      ON u.id = se.user_id
       LEFT JOIN rides r ON r.id = se.ride_id
       LEFT JOIN users driver ON driver.id = r.driver_id
       ${where}
       ORDER BY se.activated_at DESC
       LIMIT 500`,
      params
    );

    res.json({ ok: true, data: rows });
  } catch (e) {
    console.error('getAdminSosEvents error', e);
    res.status(500).json({ message: 'Internal server error' });
  }
};
