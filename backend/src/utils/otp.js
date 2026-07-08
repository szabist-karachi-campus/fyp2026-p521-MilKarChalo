
import crypto from 'crypto';
import { pool } from '../config/db.js';
import { env } from '../config/env.js';

export function generateOtp() {
  const len = env.otp.length || 6;
  const min = 10 ** (len - 1);
  const code = Math.floor(min + Math.random() * (9 * min));
  return String(code).padStart(len, '0');
}
export function hashOtp(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

export async function createOrReplaceActiveOtp(userId, purpose, code) {
  const ttlSeconds = env.otp.ttlSeconds || 600;
  const otpHash = hashOtp(code);

  // Invalidate active OTPs of same purpose
  await pool.execute(
    `UPDATE otps SET consumed=1, consumed_at=NOW() WHERE user_id=? AND purpose=? AND consumed=0 AND expires_at>NOW()`,
    [userId, purpose]
  );

  const expiresAt = new Date(Date.now() + ttlSeconds * 1000);
  const [result] = await pool.execute(
    `INSERT INTO otps (user_id, otp_hash, purpose, attempts, expires_at, consumed, last_sent_at)
     VALUES (?, ?, ?, 0, ?, 0, NOW())`,
    [userId, otpHash, purpose, expiresAt]
  );
  return { id: result.insertId, expires_at: expiresAt };
}

export async function canResend(userId, purpose) {
  const cooldown = env.otp.resendCooldown || 120;
  const [rows] = await pool.execute(
    `SELECT TIMESTAMPDIFF(SECOND, last_sent_at, NOW()) as age
     FROM otps
     WHERE user_id=? AND purpose=?
     ORDER BY id DESC LIMIT 1`,
    [userId, purpose]
  );
  if (!rows.length) return { ok: true };
  const age = rows[0].age;
  if (age < cooldown) return { ok: false, retryAfter: cooldown - age };
  return { ok: true };
}

export async function touchResent(otpId) {
  await pool.execute(`UPDATE otps SET last_sent_at=NOW() WHERE id=?`, [otpId]);
}

export async function verifyOtp(userId, purpose, code) {
  const otpHash = hashOtp(code);
  // Find active, not consumed, not expired
  const [rows] = await pool.execute(
    `SELECT id, attempts FROM otps
     WHERE user_id=? AND purpose=? AND consumed=0 AND expires_at>NOW()
     ORDER BY id DESC LIMIT 1`,
    [userId, purpose]
  );
  if (!rows.length) return { ok: false, reason: 'expired_or_missing' };
  const id = rows[0].id;

  // Compare hash
  const [match] = await pool.execute(`SELECT 1 FROM otps WHERE id=? AND otp_hash=? LIMIT 1`, [id, otpHash]);
  if (!match.length) {
    await pool.execute(`UPDATE otps SET attempts=attempts+1 WHERE id=?`, [id]);
    return { ok: false, reason: 'wrong_code' };
  }
  await pool.execute(`UPDATE otps SET consumed=1, consumed_at=NOW() WHERE id=?`, [id]);
  return { ok: true };
}
