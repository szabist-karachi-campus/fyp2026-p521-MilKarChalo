import { validationResult } from 'express-validator';
import { pool } from '../config/db.js';

export const upsertPassengerProfile = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });

  if (!req.user || !req.user.uid) {
    return res.status(401).json({ message: 'Unauthorized: User ID missing from token' });
  }
  const user_id = req.user.uid; 

  let image_url = null;
  if (req.file) {
    image_url = `/uploads/${req.file.filename}`;
  }

  const { emergency_contact_name, emergency_contact_phone, address, gender_preference } = req.body;

  try {
    const [u] = await pool.execute(`SELECT role FROM users WHERE id=?`, [user_id]);
    if (!u.length || u[0].role !== 'passenger') return res.status(400).json({ message: 'Invalid user/role' });

    await pool.execute(
      `INSERT INTO passenger_profiles (user_id,image_url,emergency_contact_name,emergency_contact_phone,address,gender_preference)
       VALUES (?,?,?,?,?,?)
       ON DUPLICATE KEY UPDATE
         image_url=IF(? IS NOT NULL, ?, image_url), -- Only update image if a new one is sent
         emergency_contact_name=VALUES(emergency_contact_name),
         emergency_contact_phone=VALUES(emergency_contact_phone),
         address=VALUES(address),
         gender_preference=VALUES(gender_preference)`,
      [
        user_id, 
        image_url,
        emergency_contact_name, 
        emergency_contact_phone, 
        address, 
        gender_preference || 'both',
        image_url, image_url
      ]
    );

    await pool.execute(`UPDATE users SET onboarding_status='ready' WHERE id=?`, [user_id]);
    return res.json({ ok: true, next: 'ready', image_url });
  } catch (e) {
    console.error('upsertPassengerProfile error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const upsertDriverProfile = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });

  const user_id = req.user.uid; 

  // Image is mandatory for drivers
  if (!req.file) {
    return res.status(400).json({ ok: false, message: 'Profile/License image is mandatory.' });
  }

  const image_url = `/uploads/${req.file.filename}`;

  // Sanitize inputs to prevent "undefined" errors
  const name = req.body.emergency_contact_name || null;
  const phone = req.body.emergency_contact_phone || null;
  const address = req.body.address || null;
  const cnic = req.body.cnic || null;
  const license = req.body.driving_license_no || null;
  const insurance = req.body.insurance_no || null; // Matches DEFAULT NULL in your SQL 

  try {
    const [u] = await pool.execute(`SELECT role FROM users WHERE id=?`, [user_id]);
    if (!u.length || u[0].role !== 'driver') {
      return res.status(400).json({ message: 'Invalid user or role' });
    }

    // We do NOT manually insert verification_status here; 
    // the database sets it to 'pending' automatically. 
    await pool.execute(
      `INSERT INTO driver_profiles (
        user_id, image_url, emergency_contact_name, emergency_contact_phone, 
        address, cnic, driving_license_no, insurance_no, verification_status
      )
       VALUES (?,?,?,?,?,?,?,?,?)
       ON DUPLICATE KEY UPDATE
         image_url=VALUES(image_url),
         emergency_contact_name=VALUES(emergency_contact_name),
         emergency_contact_phone=VALUES(emergency_contact_phone),
         address=VALUES(address),
         cnic=VALUES(cnic),
         driving_license_no=VALUES(driving_license_no),
         insurance_no=VALUES(insurance_no),
         verification_status='pending'`,
      [user_id, image_url, name, phone, address, cnic, license, insurance, 'pending']
    );
    
    // Move user to next onboarding step
    await pool.execute(`UPDATE users SET onboarding_status='vehicle_pending' WHERE id=?`, [user_id]);
    
    return res.json({ ok: true, next: 'vehicle_pending', image_url });
  } catch (e) {
    console.error('upsertDriverProfile error', e);
    // Check for unique constraint violations (CNIC or License) 
    if (e.errno === 1062) {
      return res.status(409).json({ message: 'CNIC or License number already registered.' });
    }
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const upsertVehicle = async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(422).json({ errors: errors.array() });

  // Use the secure ID from the token, not the request body
  const user_id = req.user.uid; 
  const { make, model, color, plate_no } = req.body;
  const seats = parseInt(req.body.seats, 10); // FIX: force integer — multipart sends strings

  try {
    const [u] = await pool.execute(`SELECT role FROM users WHERE id=?`, [user_id]);
    if (!u.length || u[0].role !== 'driver') return res.status(400).json({ message: 'Invalid user/role' });

    await pool.execute(
      `INSERT INTO vehicles (user_id, make, model, color, plate_no, seats)
       VALUES (?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         make=VALUES(make),
         model=VALUES(model),
         color=VALUES(color),
         plate_no=VALUES(plate_no),
         seats=VALUES(seats)`,
      [user_id, make, model, color, plate_no, seats]
    );

    await pool.execute(
      `UPDATE driver_profiles SET verification_status='pending' WHERE user_id=?`,
      [user_id]
    );

    await pool.execute(`UPDATE users SET onboarding_status='ready' WHERE id=?`, [user_id]);
    return res.json({ ok: true, next: 'ready' });
  } catch (e) {
    console.error('upsertVehicle error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

// FIX: New endpoint — fetch full profile + vehicle data so the profile page
// always shows up-to-date vehicle info even if SharedPreferences is stale.
export const getMyProfile = async (req, res) => {
  const user_id = req.user.uid;
  try {
    const [rows] = await pool.execute(
      `SELECT u.id, u.name, u.email, u.role, u.gender, u.city, u.onboarding_status,
              u.average_rating, u.review_count, u.rating_sum,
              d.emergency_contact_name as d_emg_name, d.emergency_contact_phone as d_emg_phone,
              d.address as d_addr, d.cnic, d.driving_license_no, d.insurance_no,
              d.image_url as d_image, d.verification_status,
              p.emergency_contact_name as p_emg_name, p.emergency_contact_phone as p_emg_phone,
              p.address as p_addr, p.gender_preference, p.image_url as p_image,
              v.make, v.model, v.color, v.plate_no, v.seats
       FROM users u
       LEFT JOIN driver_profiles d ON u.id = d.user_id
       LEFT JOIN passenger_profiles p ON u.id = p.user_id
       LEFT JOIN vehicles v ON u.id = v.user_id
       WHERE u.id = ? LIMIT 1`,
      [user_id]
    );

    if (!rows.length) return res.status(404).json({ message: 'User not found' });
    const data = rows[0];

    return res.json({
      ok: true,
      user: {
        name: data.name,
        email: data.email,
        role: data.role,
        gender: data.gender,
        city: data.city,
        onboarding_status: data.onboarding_status,
        average_rating: data.average_rating,
        review_count: data.review_count,
        image_url: data.role === 'driver' ? data.d_image : data.p_image,
      },
      driver: data.role === 'driver' ? {
        emergency_contact_name: data.d_emg_name,
        emergency_contact_phone: data.d_emg_phone,
        address: data.d_addr,
        cnic: data.cnic,
        driving_license_no: data.driving_license_no,
        insurance_no: data.insurance_no,
        verification_status: data.verification_status,
      } : null,
      passenger: data.role === 'passenger' ? {
        emergency_contact_name: data.p_emg_name,
        emergency_contact_phone: data.p_emg_phone,
        address: data.p_addr,
        gender_preference: data.gender_preference,
      } : null,
      vehicle: data.make ? {
        make: data.make,
        model: data.model,
        color: data.color,
        plate_no: data.plate_no,
        total_seats: data.seats,
      } : null,
    });
  } catch (e) {
    console.error('getMyProfile error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};
