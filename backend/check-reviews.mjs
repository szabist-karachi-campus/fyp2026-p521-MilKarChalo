import { pool } from './src/config/db.js';

// Check column types
const [cols] = await pool.execute(`
  SELECT COLUMN_NAME, COLUMN_TYPE 
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'reviews'
  ORDER BY ORDINAL_POSITION
`);
console.log('reviews columns:', cols.map(c => `${c.COLUMN_NAME}:${c.COLUMN_TYPE}`).join(', '));

// Check row count
const [[count]] = await pool.execute(`SELECT COUNT(*) as n FROM reviews`);
console.log('reviews row count:', count.n);

// Sample row
const [rows] = await pool.execute(`SELECT * FROM reviews LIMIT 3`);
console.log('sample rows:', JSON.stringify(rows));

// Test the join used in getPassengerBookings
const [joinTest] = await pool.execute(`
  SELECT b.id as booking_id, rv.id as review_id, rv.rating
  FROM bookings b
  LEFT JOIN reviews rv ON rv.booking_id = b.id AND rv.reviewer_id = b.passenger_id
  WHERE rv.id IS NOT NULL
  LIMIT 5
`);
console.log('join test (should show reviewed bookings):', JSON.stringify(joinTest));

process.exit(0);
