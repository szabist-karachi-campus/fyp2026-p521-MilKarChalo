import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { validationResult } from 'express-validator';
import { pool } from '../config/db.js';
import { env } from '../config/env.js';
import { generateOtp, createOrReplaceActiveOtp, canResend, touchResent, verifyOtp } from '../utils/otp.js';
import { sendOtpMail } from '../config/mailer.js';

const bailIfInvalid = (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) { res.status(422).json({ errors: errors.array() }); return true; }
  return false;
};

export const register = async (req, res) => {
  try {
    if (bailIfInvalid(req, res)) return;
    const { role, name, email, phone, gender, city, password } = req.body;

    const [dup] = await pool.execute(`SELECT 1 FROM users WHERE email=? OR phone=? LIMIT 1`, [email, phone]);
    if (dup.length) return res.status(409).json({ message: 'Email or phone already exists' });

    const password_hash = await bcrypt.hash(password, 10);
    const [result] = await pool.execute(
      `INSERT INTO users (role,name,email,phone,gender,city,password_hash,email_verified,onboarding_status)
       VALUES (?,?,?,?,?,?,?,0,'email_verified')`,
      [role, name, email, phone, gender, city, password_hash]
    );
    const userId = result.insertId;

    const code = generateOtp();
    const otp = await createOrReplaceActiveOtp(userId, 'signup', code);
    await sendOtpMail({ to: email, code, purpose: 'signup' });

    return res.status(201).json({ ok: true, user_id: userId, otp_id: otp.id, message: 'Signup OTP sent' });
  } catch (e) {
    console.error('register error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const adminLogin = async (req, res) => {
  try {
    const { email, password } = req.body;
    
    const [u] = await pool.execute(
      `SELECT id, role, name, password_hash FROM users WHERE email=? LIMIT 1`, 
      [email]
    );

    if (!u.length || u[0].role !== 'admin') {
      return res.status(401).json({ message: 'Unauthorized: Admin access only' });
    }

    const isPasswordCorrect = await bcrypt.compare(password, u[0].password_hash);
    if (!isPasswordCorrect) {
      return res.status(401).json({ message: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { uid: u[0].id, role: u[0].role }, 
      process.env.JWT_SECRET, 
      { expiresIn: '1d' }
    );

    return res.json({ 
      ok: true, 
      token, 
      user: { name: u[0].name, role: u[0].role } 
    });
  } catch (e) {
    console.error('adminLogin error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const verifyEmailOtp = async (req, res) => {
  try {
    if (bailIfInvalid(req, res)) return;
    const { email, code } = req.body;
    
    const [u] = await pool.execute(`SELECT id, role FROM users WHERE email=? LIMIT 1`, [email]);
    if (!u.length) return res.status(404).json({ message: 'User not found' });
    const userId = u[0].id;
    const userRole = u[0].role;

    const result = await verifyOtp(userId, 'signup', code);
    if (!result.ok) return res.status(401).json({ ok: false, reason: result.reason });

    const next = userRole === 'driver' ? 'driver_profile_pending' : 'passenger_profile_pending';
    
    await pool.execute(`UPDATE users SET email_verified=1, email_verified_at=NOW(), onboarding_status=? WHERE id=?`, [next, userId]);

    const token = jwt.sign(
      { uid: userId, role: userRole }, 
      process.env.JWT_SECRET || env.jwt?.secret || 'devsecret', 
      { expiresIn: '7d' }
    );

    return res.json({ ok: true, next, token });
  } catch (e) {
    console.error('verifyEmailOtp error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const resendSignupOtp = async (req, res) => {
  try {
    if (bailIfInvalid(req, res)) return;
    const { email } = req.body;
    const [u] = await pool.execute(`SELECT id FROM users WHERE email=? LIMIT 1`, [email]);
    if (!u.length) return res.status(404).json({ message: 'User not found' });
    const userId = u[0].id;

    const cooldown = await canResend(userId, 'signup');
    if (!cooldown.ok) return res.status(429).json({ ok: false, retry_after_seconds: cooldown.retryAfter });

    const code = generateOtp();
    const otp = await createOrReplaceActiveOtp(userId, 'signup', code);
    await touchResent(otp.id);
    await sendOtpMail({ to: email, code, purpose: 'signup' });
    return res.json({ ok: true, otp_id: otp.id });
  } catch (e) {
    console.error('resendSignupOtp error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const login = async (req, res) => {
  try {
    if (bailIfInvalid(req, res)) return;
    const { email, password } = req.body;
    const [u] = await pool.execute(`SELECT id, role, password_hash FROM users WHERE email=? LIMIT 1`, [email]);
    if (!u.length) return res.status(401).json({ message: 'Invalid credentials' });
    const ok = await bcrypt.compare(password, u[0].password_hash);
    if (!ok) return res.status(401).json({ message: 'Invalid credentials' });

    const code = generateOtp();
    const otp = await createOrReplaceActiveOtp(u[0].id, 'login', code);
    await sendOtpMail({ to: email, code, purpose: 'login' });
    return res.json({ ok: true, otp_id: otp.id, message: 'Login OTP sent' });
  } catch (e) {
    console.error('login error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const verifyLoginOtp = async (req, res) => {
  try {
    if (bailIfInvalid(req, res)) return;
    const { email, code } = req.body;

    // 1. Fetch user + ALL linked profile and vehicle data
    const [rows] = await pool.execute(
      `SELECT u.id, u.role, u.onboarding_status, u.name, u.email,
              d.emergency_contact_name as d_emg_name, d.emergency_contact_phone as d_emg_phone, 
              d.address as d_addr, d.cnic, d.driving_license_no, d.insurance_no, d.image_url as d_image,
              p.emergency_contact_name as p_emg_name, p.emergency_contact_phone as p_emg_phone, 
              p.address as p_addr, p.gender_preference, p.image_url as p_image,
              v.make, v.model, v.color, v.plate_no, v.seats
       FROM users u
       LEFT JOIN driver_profiles d ON u.id = d.user_id
       LEFT JOIN passenger_profiles p ON u.id = p.user_id
       LEFT JOIN vehicles v ON u.id = v.user_id
       WHERE u.email=? LIMIT 1`, [email]
    );

    if (!rows.length) return res.status(404).json({ message: 'User not found' });
    const data = rows[0];

    const result = await verifyOtp(data.id, 'login', code);
    if (!result.ok) return res.status(401).json({ ok: false, reason: result.reason });

    const token = jwt.sign({ uid: data.id, role: data.role }, process.env.JWT_SECRET, { expiresIn: '7d' });

    // 2. Return structured objects for Flutter to save
    return res.json({
      ok: true,
      token,
      next: data.onboarding_status,
      role: data.role,
      user: { 
        name: data.name, 
        email: data.email, 
        image_url: data.role === 'driver' ? data.d_image : data.p_image 
      },
      driver: data.role === 'driver' ? {
        emergency_contact_name: data.d_emg_name,
        emergency_contact_phone: data.d_emg_phone,
        address: data.d_addr,
        cnic: data.cnic,
        driving_license_no: data.driving_license_no,
        insurance_no: data.insurance_no
      } : null,
      passenger: data.role === 'passenger' ? {
        emergency_contact_name: data.p_emg_name,
        emergency_contact_phone: data.p_emg_phone,
        address: data.p_addr,
        gender_preference: data.gender_preference
      } : null,
      vehicle: data.make ? {
        make: data.make,
        model: data.model,
        color: data.color,
        plate_no: data.plate_no,
        total_seats: data.seats
      } : null
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};
export const resendLoginOtp = async (req, res) => {
  try {
    if (bailIfInvalid(req, res)) return;
    const { email } = req.body;
    const [u] = await pool.execute(`SELECT id FROM users WHERE email=? LIMIT 1`, [email]);
    if (!u.length) return res.status(404).json({ message: 'User not found' });
    const cooldown = await canResend(u[0].id, 'login');
    if (!cooldown.ok) return res.status(429).json({ ok: false, retry_after_seconds: cooldown.retryAfter });

    const code = generateOtp();
    const otp = await createOrReplaceActiveOtp(u[0].id, 'login', code);
    await touchResent(otp.id);
    await sendOtpMail({ to: email, code, purpose: 'login' });
    return res.json({ ok: true, otp_id: otp.id });
  } catch (e) {
    console.error('resendLoginOtp error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const forgotPassword = async (req, res) => {
  try {
    if (bailIfInvalid(req, res)) return;
    const { email } = req.body;
    const [u] = await pool.execute(`SELECT id FROM users WHERE email=? LIMIT 1`, [email]);
    if (!u.length) return res.status(404).json({ message: 'User not found' });

    const code = generateOtp();
    const otp = await createOrReplaceActiveOtp(u[0].id, 'reset', code);
    await sendOtpMail({ to: email, code, purpose: 'reset' });
    return res.json({ ok: true, otp_id: otp.id, message: 'Reset OTP sent' });
  } catch (e) {
    console.error('forgotPassword error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const verifyResetOtp = async (req, res) => {
  try {
    if (bailIfInvalid(req, res)) return;
    const { email, code } = req.body;
    const [u] = await pool.execute(`SELECT id FROM users WHERE email=? LIMIT 1`, [email]);
    if (!u.length) return res.status(404).json({ message: 'User not found' });

    const result = await verifyOtp(u[0].id, 'reset', code);
    if (!result.ok) return res.status(401).json({ ok: false, reason: result.reason });
    return res.json({ ok: true });
  } catch (e) {
    console.error('verifyResetOtp error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

export const resetPassword = async (req, res) => {
  try {
    if (bailIfInvalid(req, res)) return;
    const { email, password, code } = req.body;
    const [u] = await pool.execute(`SELECT id FROM users WHERE email=? LIMIT 1`, [email]);
    if (!u.length) return res.status(404).json({ message: 'User not found' });

    const result = await verifyOtp(u[0].id, 'reset', code);
    if (!result.ok) return res.status(401).json({ ok: false, reason: result.reason });

    const hash = await bcrypt.hash(password, 10);
    await pool.execute(`UPDATE users SET password_hash=? WHERE id=?`, [hash, u[0].id]);
    return res.json({ ok: true, message: 'Password updated' });
  } catch (e) {
    console.error('resetPassword error', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};
