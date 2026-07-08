import { pool } from '../config/db.js';

const FCM_TOKEN_MAX_LENGTH = 512;

// Validates that a token is a non-empty string within the allowed length.
// FCM tokens are base64url + colon characters; a simple length check is sufficient.
const isValidFcmToken = (token) =>
  typeof token === 'string' && token.length > 0 && token.length <= FCM_TOKEN_MAX_LENGTH;

// Task 4.1 — Register FCM token for the authenticated user
export const registerFcmToken = async (req, res) => {
  const { fcm_token } = req.body;

  if (!isValidFcmToken(fcm_token)) {
    return res.status(422).json({
      ok: false,
      message: 'fcm_token must be a non-empty string no longer than 512 characters.',
    });
  }

  try {
    await pool.execute(
      `UPDATE users SET fcm_token = ? WHERE id = ?`,
      [fcm_token, req.user.uid]
    );

    return res.status(200).json({ ok: true, message: 'FCM token registered.' });
  } catch (e) {
    console.error('registerFcmToken error', e);
    return res.status(500).json({ ok: false, message: e.sqlMessage || 'Internal server error' });
  }
};

// Task 4.2 — Get the 50 most recent notifications for the authenticated user
export const getInbox = async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT id, type, title, body, is_read, created_at, payload
       FROM notifications
       WHERE user_id = ?
       ORDER BY created_at DESC
       LIMIT 50`,
      [req.user.uid]
    );

    const notifications = rows.map((row) => ({
      ...row,
      payload: row.payload != null ? JSON.parse(row.payload) : null,
    }));

    return res.status(200).json({ ok: true, data: notifications });
  } catch (e) {
    console.error('getInbox error', e);
    return res.status(500).json({ ok: false, message: e.sqlMessage || 'Internal server error' });
  }
};

// Task 4.3 — Get the count of unread notifications for the authenticated user
export const getUnreadCount = async (req, res) => {
  try {
    const [[row]] = await pool.execute(
      `SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0`,
      [req.user.uid]
    );

    return res.status(200).json({ ok: true, count: Number(row.count) });
  } catch (e) {
    console.error('getUnreadCount error', e);
    return res.status(500).json({ ok: false, message: e.sqlMessage || 'Internal server error' });
  }
};

// Task 4.4 — Mark a single notification as read
export const markRead = async (req, res) => {
  const notificationId = req.params.id;

  try {
    const [[notification]] = await pool.execute(
      `SELECT id, user_id FROM notifications WHERE id = ? LIMIT 1`,
      [notificationId]
    );

    if (!notification) {
      return res.status(404).json({ ok: false, message: 'Notification not found.' });
    }

    if (notification.user_id !== req.user.uid) {
      return res.status(403).json({ ok: false, message: 'Forbidden.' });
    }

    await pool.execute(
      `UPDATE notifications SET is_read = 1 WHERE id = ?`,
      [notificationId]
    );

    return res.status(200).json({ ok: true });
  } catch (e) {
    console.error('markRead error', e);
    return res.status(500).json({ ok: false, message: e.sqlMessage || 'Internal server error' });
  }
};

// Task 4.5 — Mark multiple notifications as read (bulk)
export const markReadBulk = async (req, res) => {
  const { ids } = req.body;

  if (!Array.isArray(ids) || ids.length === 0 || ids.length > 100) {
    return res.status(422).json({
      ok: false,
      message: 'ids must be a non-empty array with at most 100 items.',
    });
  }

  try {
    const placeholders = ids.map(() => '?').join(', ');
    const [result] = await pool.execute(
      `UPDATE notifications SET is_read = 1 WHERE id IN (${placeholders}) AND user_id = ?`,
      [...ids, req.user.uid]
    );

    return res.status(200).json({ ok: true, updated: result.affectedRows });
  } catch (e) {
    console.error('markReadBulk error', e);
    return res.status(500).json({ ok: false, message: e.sqlMessage || 'Internal server error' });
  }
};
