import { pool } from '../config/db.js';
import { messaging } from '../config/firebase.js';

// ---------------------------------------------------------------------------
// buildMessage — pure helper, no I/O
// ---------------------------------------------------------------------------

/**
 * Assembles { title, body, payload } for a given notification type.
 * @param {string} type  - One of the 10 notification type strings.
 * @param {object} data  - Template variables for the body string.
 * @returns {{ title: string, body: string, payload: object }}
 */
export function buildMessage(type, data = {}) {
  switch (type) {
    case 'booking_request':
      return {
        title: 'New Booking Request',
        body: `${data.passenger_name} wants to book ${data.seats} seat(s): ${data.pickup} → ${data.destination}`,
        payload: { booking_id: data.booking_id, ride_id: data.ride_id },
      };

    case 'booking_accepted':
      return {
        title: 'Booking Accepted',
        body: `Your booking is confirmed! ${data.pickup} → ${data.destination} on ${data.departure_time}`,
        payload: { booking_id: data.booking_id, ride_id: data.ride_id },
      };

    case 'booking_rejected':
      return {
        title: 'Booking Rejected',
        body: `Your booking for ${data.pickup} → ${data.destination} was rejected.`,
        payload: { booking_id: data.booking_id, ride_id: data.ride_id },
      };

    case 'booking_cancelled':
      return {
        title: 'Booking Cancelled',
        body: `${data.passenger_name} cancelled their booking (${data.seats} seat(s)): ${data.pickup} → ${data.destination}`,
        payload: { booking_id: data.booking_id, ride_id: data.ride_id },
      };

    case 'ride_started':
      return {
        title: 'Ride Started',
        body: `${data.driver_name} has started the ride: ${data.pickup} → ${data.destination}`,
        payload: { ride_id: data.ride_id },
      };

    case 'ride_completed':
      return {
        title: 'Ride Completed',
        body: `${data.driver_name} completed the ride: ${data.pickup} → ${data.destination}. Leave a review!`,
        payload: { ride_id: data.ride_id },
      };

    case 'ride_cancelled':
      return {
        title: 'Ride Cancelled',
        body: `Your ride ${data.pickup} → ${data.destination} (departs ${data.departure_time}) has been cancelled.`,
        payload: { ride_id: data.ride_id },
      };

    case 'driver_approved':
      return {
        title: 'Account Approved',
        body: 'Your driver account has been approved. You can now post rides.',
        payload: { driver_id: data.driver_id },
      };

    case 'driver_rejected':
      return {
        title: 'Account Rejected',
        body: 'Your driver account has been rejected. Please contact support for more information.',
        payload: { driver_id: data.driver_id },
      };

    case 'driver_suspended':
      return {
        title: 'Account Suspended',
        body: 'Your driver account has been suspended. Please contact support.',
        payload: { driver_id: data.driver_id },
      };

    default:
      throw new Error(`Unknown notification type: ${type}`);
  }
}

// ---------------------------------------------------------------------------
// sendWithRetry — FCM delivery with exponential back-off
// ---------------------------------------------------------------------------

const STALE_TOKEN_ERRORS = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

const MAX_ATTEMPTS  = 3;
const BASE_DELAY_MS = 5_000;   // 5 s
const MAX_DELAY_MS  = 60_000;  // 60 s cap

/**
 * Attempts to deliver a push notification via FCM, retrying on transient
 * failures with exponential back-off.
 *
 * @param {string} token          - FCM registration token.
 * @param {{ title, body, payload }} message
 * @param {number} notificationId - DB row ID (for logging).
 * @param {number} userId         - User whose token this is (for stale-token cleanup).
 * @param {number} [attempt=1]    - Current attempt number (1-indexed).
 */
async function sendWithRetry(token, message, notificationId, userId, attempt = 1) {
  const { title, body, payload, type } = message;

  const fcmMessage = {
    token,
    notification: { title, body },
    data: {
      // Always include type so the Flutter app can route the tap correctly
      type: String(type ?? ''),
      ...(payload
        ? Object.fromEntries(Object.entries(payload).map(([k, v]) => [k, String(v)]))
        : {}),
    },
    // Android — wake the device and use high-priority delivery
    android: {
      priority: 'high',
      notification: {
        channelId: 'milkarchalo_fcm',
        priority: 'high',
        defaultSound: true,
        defaultVibrateTimings: true,
      },
    },
    // APNs (iOS) — show in foreground and play sound
    apns: {
      headers: {
        'apns-priority': '10',
      },
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
          contentAvailable: true,
        },
      },
    },
  };

  try {
    await messaging.send(fcmMessage);
  } catch (err) {
    const errorCode = err.errorInfo?.code ?? err.code ?? '';

    // -----------------------------------------------------------------------
    // Stale token — clear from DB, do NOT retry
    // -----------------------------------------------------------------------
    if (STALE_TOKEN_ERRORS.has(errorCode)) {
      console.warn(
        `[Notification] Stale FCM token for user ${userId} ` +
        `(notificationId=${notificationId}). Clearing token. Error: ${errorCode}`
      );
      try {
        await pool.query('UPDATE users SET fcm_token = NULL WHERE id = ?', [userId]);
      } catch (dbErr) {
        console.error(
          `[Notification] Failed to clear stale FCM token for user ${userId}: ${dbErr.message}`
        );
      }
      return; // no retry
    }

    // -----------------------------------------------------------------------
    // Transient failure — retry with exponential back-off
    // -----------------------------------------------------------------------
    if (attempt < MAX_ATTEMPTS) {
      const delayMs = Math.min(BASE_DELAY_MS * 2 ** (attempt - 1), MAX_DELAY_MS);
      console.warn(
        `[Notification] FCM send failed (attempt ${attempt}/${MAX_ATTEMPTS}), ` +
        `retrying in ${delayMs / 1000}s. notificationId=${notificationId}. Error: ${err.message}`
      );
      await new Promise((resolve) => setTimeout(resolve, delayMs));
      return sendWithRetry(token, message, notificationId, userId, attempt + 1);
    }

    // -----------------------------------------------------------------------
    // All attempts exhausted — discard push, log final failure
    // -----------------------------------------------------------------------
    console.error(
      `[Notification] All ${MAX_ATTEMPTS} FCM attempts failed for ` +
      `notificationId=${notificationId}. Push discarded. Final error: ${err.message}`
    );
  }
}

// ---------------------------------------------------------------------------
// sendNotification — public API
// ---------------------------------------------------------------------------

/**
 * Persists a notification record and optionally delivers a push via FCM.
 *
 * FCM errors are always caught and logged — they never propagate to the caller.
 *
 * @param {number} userId
 * @param {{ type: string, title: string, body: string, payload?: object }} options
 * @returns {Promise<number>} The inserted notification row ID.
 */
export async function sendNotification(userId, { type, title, body, payload }) {
  // Always persist, regardless of FCM outcome
  const [result] = await pool.query(
    'INSERT INTO notifications (user_id, type, title, body, payload) VALUES (?, ?, ?, ?, ?)',
    [userId, type, title, body, payload ? JSON.stringify(payload) : null]
  );
  const notificationId = result.insertId;

  // Look up FCM token
  const [rows] = await pool.query('SELECT fcm_token FROM users WHERE id = ?', [userId]);
  const fcmToken = rows[0]?.fcm_token ?? null;

  if (fcmToken && messaging) {
    const message = { title, body, payload, type };
    // Fire-and-forget — all FCM errors are handled inside sendWithRetry
    sendWithRetry(fcmToken, message, notificationId, userId).catch((err) => {
      console.error(
        `[Notification] Unexpected error in sendWithRetry for ` +
        `notificationId=${notificationId}: ${err.message}`
      );
    });
  }

  return notificationId;
}
