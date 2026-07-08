import express from 'express';
import cors from 'cors';
import 'dotenv/config';
import { createServer } from 'http';
import { Server } from 'socket.io';
import authRoutes    from './routes/auth.routes.js';
import profileRoutes from './routes/profile.routes.js';
import adminRoutes   from './routes/admin.routes.js';
import rideRoutes         from './routes/ride.routes.js';
import notificationRoutes from './routes/notification.routes.js';
import chatRoutes         from './routes/chat.routes.js';
import sosRoutes          from './routes/sos.routes.js';
import { setupChatSocket } from './socket/chat.socket.js';
import { pool }           from './config/db.js';

const app = express();
app.use(cors());
app.use(express.json());

// ─── Auto-migrate missing columns on every startup ───────────────────────────
// Works on MySQL 5.7+ and 8.0+. Each column is checked via INFORMATION_SCHEMA
// before ALTER so we never get ER_DUP_FIELDNAME errors.
async function addColumnIfMissing(table, column, definition) {
  const [rows] = await pool.execute(
    `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?`,
    [table, column]
  );
  if (rows.length === 0) {
    await pool.execute(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
    console.log(`  ✅ Added column ${table}.${column}`);
  }
}

async function runMigrations() {
  try {
    await addColumnIfMissing('users', 'rating_sum',
      `DECIMAL(10,2) NOT NULL DEFAULT 0.00`);
    await addColumnIfMissing('users', 'review_count',
      `INT NOT NULL DEFAULT 0`);
    await addColumnIfMissing('users', 'average_rating',
      `DECIMAL(3,2) NOT NULL DEFAULT 0.00`);
    await addColumnIfMissing('users', 'fcm_token',
      `VARCHAR(512) NULL DEFAULT NULL`);
    await addColumnIfMissing('bookings', 'status',
      `ENUM('pending','accepted','rejected','cancelled','completed') NOT NULL DEFAULT 'pending'`);
    await addColumnIfMissing('bookings', 'created_at',
      `TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP`);
    await addColumnIfMissing('bookings', 'booking_group_id',
      `VARCHAR(36) NULL DEFAULT NULL`);
    await addColumnIfMissing('rides', 'status',
      `ENUM('active','started','completed','cancelled') NOT NULL DEFAULT 'active'`);
    // Ensure 'started' is in the ENUM — alter if column already exists
    await pool.execute(
      `ALTER TABLE rides MODIFY COLUMN status ENUM('active','started','completed','cancelled') NOT NULL DEFAULT 'active'`
    );
    await addColumnIfMissing('rides', 'started_at',
      `TIMESTAMP NULL DEFAULT NULL`);
    await addColumnIfMissing('rides', 'is_round_trip',
      `TINYINT(1) NOT NULL DEFAULT 0`);
    await addColumnIfMissing('rides', 'round_trip_group_id',
      `VARCHAR(36) NULL DEFAULT NULL`);
    await addColumnIfMissing('rides', 'linked_ride_id',
      `INT NULL DEFAULT NULL`);
    await addColumnIfMissing('rides', 'leg_type',
      `ENUM('departure','return') NOT NULL DEFAULT 'departure'`);
    // ── Recurring rides ──────────────────────────────────────────────────────
    await addColumnIfMissing('rides', 'is_recurring',
      `TINYINT(1) NOT NULL DEFAULT 0`);
    await addColumnIfMissing('rides', 'recurrence_type',
      `ENUM('daily','weekly','custom') NULL DEFAULT NULL`);
    await addColumnIfMissing('rides', 'recurrence_end_date',
      `DATE NULL DEFAULT NULL`);
    await addColumnIfMissing('rides', 'recurrence_group_id',
      `VARCHAR(36) NULL DEFAULT NULL`);
    // ── Coordinate columns for geocoding / ETA ───────────────────────────────
    await addColumnIfMissing('rides', 'pickup_lat',      `DECIMAL(10,7) NULL DEFAULT NULL`);
    await addColumnIfMissing('rides', 'pickup_lng',      `DECIMAL(10,7) NULL DEFAULT NULL`);
    await addColumnIfMissing('rides', 'destination_lat', `DECIMAL(10,7) NULL DEFAULT NULL`);
    await addColumnIfMissing('rides', 'destination_lng', `DECIMAL(10,7) NULL DEFAULT NULL`);
    await addColumnIfMissing('bookings', 'occurrence_id',
      `BIGINT NULL DEFAULT NULL`);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS recurring_ride_days (
        id      BIGINT       NOT NULL AUTO_INCREMENT,
        ride_id BIGINT       NOT NULL,
        day_of_week TINYINT  NOT NULL COMMENT '1=Mon … 7=Sun',
        PRIMARY KEY (id),
        KEY idx_rrd_ride (ride_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS ride_occurrences (
        id                BIGINT       NOT NULL AUTO_INCREMENT,
        ride_id           BIGINT       NOT NULL,
        occurrence_date   DATE         NOT NULL,
        departure_datetime DATETIME    NOT NULL,
        available_seats   INT          NOT NULL,
        status            ENUM('active','cancelled','completed') NOT NULL DEFAULT 'active',
        created_at        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_occurrence_date (occurrence_date),
        KEY idx_ride_occurrence  (ride_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS reviews (
        id          BIGINT          NOT NULL AUTO_INCREMENT,
        ride_id     BIGINT          NOT NULL,
        booking_id  BIGINT          NOT NULL,
        reviewer_id BIGINT          NOT NULL,
        reviewee_id BIGINT          NOT NULL,
        rating      TINYINT UNSIGNED NOT NULL,
        comment     TEXT            NULL,
        created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_reviews_booking_reviewer (booking_id, reviewer_id),
        KEY idx_reviews_reviewee_created (reviewee_id, created_at),
        KEY idx_reviews_ride_created (ride_id, created_at)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS notifications (
        id           INT            NOT NULL AUTO_INCREMENT,
        user_id      INT            NOT NULL,
        type         ENUM(
          'booking_request','booking_accepted','booking_rejected',
          'booking_cancelled','ride_started','ride_completed',
          'ride_cancelled','driver_approved','driver_rejected','driver_suspended'
        )                           NOT NULL,
        title        VARCHAR(255)   NOT NULL,
        body         TEXT           NOT NULL,
        is_read      TINYINT(1)     NOT NULL DEFAULT 0,
        payload      JSON           NULL,
        created_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY  (id),
        KEY idx_notifications_user_created (user_id, created_at DESC)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    await pool.execute(
      `ALTER TABLE driver_profiles
       MODIFY COLUMN verification_status ENUM('pending','approved','rejected','suspended')
       NOT NULL DEFAULT 'pending'`
    );
    // Fix reviews table column types — must match BIGINT IDs used everywhere else
    await pool.execute(`ALTER TABLE reviews MODIFY COLUMN id BIGINT NOT NULL AUTO_INCREMENT`);
    await pool.execute(`ALTER TABLE reviews MODIFY COLUMN ride_id BIGINT NOT NULL`);
    await pool.execute(`ALTER TABLE reviews MODIFY COLUMN booking_id BIGINT NOT NULL`);
    await pool.execute(`ALTER TABLE reviews MODIFY COLUMN reviewer_id BIGINT NOT NULL`);
    await pool.execute(`ALTER TABLE reviews MODIFY COLUMN reviewee_id BIGINT NOT NULL`);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS conversations (
        id          BIGINT          NOT NULL AUTO_INCREMENT,
        booking_id  BIGINT          NOT NULL,
        created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_conversations_booking (booking_id),
        CONSTRAINT fk_conversations_booking
          FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS messages (
        id              BIGINT          NOT NULL AUTO_INCREMENT,
        conversation_id BIGINT          NOT NULL,
        sender_id       BIGINT          NOT NULL,
        content         TEXT            NOT NULL,
        sent_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_messages_conversation (conversation_id),
        CONSTRAINT fk_messages_conversation
          FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        CONSTRAINT fk_messages_sender
          FOREIGN KEY (sender_id) REFERENCES users(id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS emergency_contacts (
        id           BIGINT        NOT NULL AUTO_INCREMENT,
        user_id      BIGINT        NOT NULL,
        name         VARCHAR(100)  NOT NULL,
        phone        VARCHAR(30)   NOT NULL,
        relationship VARCHAR(50)   NULL,
        created_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_ec_user (user_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS sos_events (
        id             BIGINT        NOT NULL AUTO_INCREMENT,
        user_id        BIGINT        NOT NULL,
        booking_id     BIGINT        NOT NULL,
        ride_id        BIGINT        NOT NULL,
        role           ENUM('passenger','driver') NOT NULL,
        status         ENUM('active','resolved','auto_closed') NOT NULL DEFAULT 'active',
        latitude       DECIMAL(10,7) NULL,
        longitude      DECIMAL(10,7) NULL,
        activated_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
        deactivated_at DATETIME      NULL,
        PRIMARY KEY (id),
        KEY idx_sos_user_booking (user_id, booking_id),
        KEY idx_sos_booking (booking_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS sos_locations (
        id         BIGINT        NOT NULL AUTO_INCREMENT,
        sos_id     BIGINT        NOT NULL,
        latitude   DECIMAL(10,7) NOT NULL,
        longitude  DECIMAL(10,7) NOT NULL,
        recorded_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_sos_loc_sos (sos_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ DB migrations checked');
  } catch (e) {
    console.warn('⚠️  Migration warning (non-fatal):', e.sqlMessage || e.message);
  }
}

pool.getConnection()
  .then(async (connection) => {
    console.log('✅ Database connected successfully');
    connection.release();
    await runMigrations();
  })
  .catch((err) => {
    console.error('❌ Database connection failed:', err.message);
  });

app.get('/health', (_, res) => res.json({ ok: true }));
app.use('/uploads', express.static('uploads'));
app.use('/auth',    authRoutes);
app.use('/profile', profileRoutes);
app.use('/admin',   adminRoutes);
app.use('/rides',         rideRoutes);
app.use('/notifications', notificationRoutes);
app.use('/chat',          chatRoutes);
app.use('/sos',           sosRoutes);

// Global error handler — always return JSON
app.use((err, req, res, next) => {
  console.error('Global error:', err?.stack || err);
  res.status(err?.statusCode || 500).json({ message: err?.message || 'Internal server error' });
});

const port = process.env.PORT || 4000;
export const httpServer = createServer(app);
export const io = new Server(httpServer, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
});
setupChatSocket(io);
httpServer.listen(port, () => console.log(`🚀 API running on http://localhost:${port}`));
