import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { pool } from '../config/db.js';

// ── helpers ───────────────────────────────────────────────────────────────────

async function loadBookingForConversation(conversationId) {
  const [[row]] = await pool.execute(
    `SELECT b.id AS booking_id, b.passenger_id, r.driver_id,
            b.status AS booking_status, r.status AS ride_status
     FROM conversations c
     JOIN bookings b ON b.id = c.booking_id
     JOIN rides r ON r.id = b.ride_id
     WHERE c.id = ?`,
    [conversationId]
  );
  return row || null;
}

async function loadRideParticipants(rideId) {
  const [[row]] = await pool.execute(
    `SELECT r.id AS ride_id, r.driver_id, r.status AS ride_status,
            b.id AS booking_id, b.passenger_id, b.status AS booking_status
     FROM rides r
     JOIN bookings b ON b.ride_id = r.id AND b.status = 'accepted'
     WHERE r.id = ? LIMIT 1`,
    [rideId]
  );
  return row || null;
}

function isParticipant(uid, booking) {
  // uid from JWT is a string; DB ids are integers — compare as strings
  return String(uid) === String(booking.passenger_id) ||
         String(uid) === String(booking.driver_id);
}

function canSendMessage(booking) {
  return (
    booking.booking_status === 'accepted' &&
    booking.ride_status !== 'completed' &&
    booking.ride_status !== 'cancelled'
  );
}

// ── setup ─────────────────────────────────────────────────────────────────────

export function setupChatSocket(io) {
  // JWT auth middleware
  io.use((socket, next) => {
    const token =
      socket.handshake.auth?.token ||
      (socket.handshake.headers?.authorization || '').replace(/^Bearer\s+/i, '');

    if (!token) return next(new Error('Authentication error'));

    try {
      const payload = jwt.verify(token, env.jwt.secret);
      socket.user = { uid: payload.uid, role: payload.role };
      next();
    } catch {
      next(new Error('Authentication error'));
    }
  });

  io.on('connection', (socket) => {
    // ── Chat: join_room ────────────────────────────────────────────────────────
    socket.on('join_room', async ({ conversationId }) => {
      try {
        const booking = await loadBookingForConversation(conversationId);
        if (!booking || !isParticipant(socket.user.uid, booking)) {
          socket.emit('error', { message: 'Access denied.' });
          socket.disconnect(true);
          return;
        }
        socket.join(`conversation:${conversationId}`);
      } catch (e) {
        console.error('[chat.socket] join_room error:', e);
        socket.emit('error', { message: 'Internal error joining room.' });
      }
    });

    // ── Chat: send_message ─────────────────────────────────────────────────────
    socket.on('send_message', async ({ conversationId, content }) => {
      try {
        if (!content || typeof content !== 'string' || content.trim().length === 0) {
          socket.emit('error', { message: 'Message content cannot be empty.' });
          return;
        }
        if (content.length > 10000) {
          socket.emit('error', { message: 'Message content exceeds maximum length.' });
          return;
        }

        const booking = await loadBookingForConversation(conversationId);
        if (!booking || !isParticipant(socket.user.uid, booking)) {
          socket.emit('error', { message: 'Access denied.' });
          return;
        }
        if (!canSendMessage(booking)) {
          socket.emit('error', {
            message: 'Chat is not available: this ride has ended or been cancelled.',
          });
          return;
        }

        // Persist (best-effort)
        let savedId = null;
        let savedAt = new Date().toISOString();
        try {
          const [result] = await pool.execute(
            `INSERT INTO messages (conversation_id, sender_id, content) VALUES (?, ?, ?)`,
            [conversationId, socket.user.uid, content.trim()]
          );
          savedId = result.insertId;
          const [[msg]] = await pool.execute(
            `SELECT sent_at FROM messages WHERE id = ?`,
            [savedId]
          );
          if (msg) savedAt = msg.sent_at;
        } catch (dbErr) {
          console.error('[chat.socket] DB persist failed (broadcasting anyway):', dbErr);
        }

        io.to(`conversation:${conversationId}`).emit('new_message', {
          id: savedId,
          conversationId,
          senderId: socket.user.uid,
          content: content.trim(),
          sentAt: savedAt,
        });
      } catch (e) {
        console.error('[chat.socket] send_message error:', e);
        socket.emit('error', { message: 'Internal error sending message.' });
      }
    });

    // ── Ride Tracking: join tracking room ─────────────────────────────────────
    socket.on('join_tracking', async ({ rideId }) => {
      try {
        const ride = await loadRideParticipants(rideId);
        if (!ride) {
          socket.emit('tracking_error', { message: 'Ride not found.' });
          return;
        }
        const uid = String(socket.user.uid);
        const isDriver = uid === String(ride.driver_id);
        const isPassenger = uid === String(ride.passenger_id);
        if (!isDriver && !isPassenger) {
          socket.emit('tracking_error', { message: 'Access denied.' });
          return;
        }
        socket.join(`tracking:${rideId}`);
        socket.emit('tracking_joined', { rideId, role: isDriver ? 'driver' : 'passenger' });
      } catch (e) {
        console.error('[tracking] join_tracking error:', e);
      }
    });

    // ── Ride Tracking: driver broadcasts location ──────────────────────────────
    socket.on('driver_location', async ({ rideId, latitude, longitude }) => {
      try {
        // Broadcast to all clients in the tracking room (including driver themselves)
        io.to(`tracking:${rideId}`).emit('location_update', {
          rideId,
          latitude,
          longitude,
          timestamp: Date.now(),
        });
      } catch (e) {
        console.error('[tracking] driver_location error:', e);
      }
    });
  });
}

// ── emitChatDisabled ──────────────────────────────────────────────────────────

export async function emitChatDisabled(io, bookingId) {
  try {
    const [[conv]] = await pool.execute(
      `SELECT id FROM conversations WHERE booking_id = ?`,
      [bookingId]
    );
    if (!conv) return;
    io.to(`conversation:${conv.id}`).emit('chat_disabled', {
      conversationId: conv.id,
      reason: 'ride_ended',
    });
  } catch (e) {
    console.error('[chat.socket] emitChatDisabled error (non-fatal):', e);
  }
}

// ── emitRideStarted / emitRideEnded ──────────────────────────────────────────

export async function emitRideEvent(io, rideId, event, payload = {}) {
  try {
    io.to(`tracking:${rideId}`).emit(event, { rideId, ...payload });
  } catch (e) {
    console.error(`[tracking] emitRideEvent(${event}) error (non-fatal):`, e);
  }
}
