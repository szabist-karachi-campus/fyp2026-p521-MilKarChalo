import { pool } from '../config/db.js';

// Helper: load booking with passenger_id and driver_id
async function loadBooking(bookingId) {
  const [[booking]] = await pool.execute(
    `SELECT b.id, b.passenger_id, r.driver_id, b.status AS booking_status, r.status AS ride_status
     FROM bookings b
     JOIN rides r ON r.id = b.ride_id
     WHERE b.id = ?`,
    [bookingId]
  );
  return booking || null;
}

function isParticipant(uid, booking) {
  // uid from JWT is a string; DB ids are integers — compare loosely
  return String(uid) === String(booking.passenger_id) ||
         String(uid) === String(booking.driver_id);
}

// POST /chat/conversations
// Body: { booking_id }
export const getOrCreateConversation = async (req, res) => {
  try {
    const booking_id = parseInt(req.body.booking_id, 10);
    if (!booking_id || isNaN(booking_id)) {
      return res.status(400).json({ message: 'booking_id is required.' });
    }

    const booking = await loadBooking(booking_id);
    if (!booking) return res.status(404).json({ message: 'Booking not found.' });

    if (!isParticipant(req.user.uid, booking)) {
      return res.status(403).json({ message: 'Access denied.' });
    }

    if (booking.booking_status !== 'accepted') {
      return res.status(403).json({ message: 'Chat is not available: booking is not accepted.' });
    }

    // Upsert: get existing or create new
    await pool.execute(
      `INSERT INTO conversations (booking_id) VALUES (?)
       ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id)`,
      [booking_id]
    );
    const [[conv]] = await pool.execute(
      `SELECT id, booking_id, created_at FROM conversations WHERE booking_id = ?`,
      [booking_id]
    );

    return res.status(200).json(conv);
  } catch (e) {
    console.error('[chat.controller] getOrCreateConversation error:', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};

// GET /chat/conversations/:conversationId/messages
export const getMessages = async (req, res) => {
  try {
    const conversationId = parseInt(req.params.conversationId, 10);
    if (!conversationId || isNaN(conversationId)) {
      return res.status(400).json({ message: 'Invalid conversation ID.' });
    }

    // Load conversation + booking
    const [[conv]] = await pool.execute(
      `SELECT c.id, c.booking_id FROM conversations c WHERE c.id = ?`,
      [conversationId]
    );
    if (!conv) return res.status(404).json({ message: 'Conversation not found.' });

    const booking = await loadBooking(conv.booking_id);
    if (!booking) return res.status(404).json({ message: 'Booking not found.' });

    if (!isParticipant(req.user.uid, booking)) {
      return res.status(403).json({ message: 'Access denied.' });
    }

    if (booking.booking_status === 'pending' || booking.booking_status === 'rejected') {
      return res.status(403).json({ message: 'Chat is not available: booking is not accepted.' });
    }

    const [messages] = await pool.execute(
      `SELECT id, conversation_id, sender_id, content, sent_at
       FROM messages
       WHERE conversation_id = ?
       ORDER BY sent_at ASC`,
      [conversationId]
    );

    return res.status(200).json({ data: messages });
  } catch (e) {
    console.error('[chat.controller] getMessages error:', e);
    return res.status(500).json({ message: 'Internal server error' });
  }
};
