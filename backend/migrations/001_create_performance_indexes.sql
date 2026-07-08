-- Migration: Create Performance Indexes for Recurring Round Trips Feature
-- Created: 2025
-- Purpose: Optimize queries for recurring round trip functionality
-- 
-- This migration creates four critical indexes to improve performance of:
-- - Booking group bulk queries (for multi-level cancellation)
-- - Duplicate booking detection (ride_id + occurrence_id)
-- - Date-based occurrence queries (for date range filtering and cancellation)
-- - Recurrence group lookups (for finding paired recurring rides)

-- Index 1: Booking Group Lookups
-- Used for: Finding all bookings in a group, bulk cancellation operations
-- Query: SELECT * FROM bookings WHERE booking_group_id = ?
CREATE INDEX IF NOT EXISTS idx_bookings_booking_group_id 
ON bookings(booking_group_id);

-- Index 2: Duplicate Booking Detection & Ride-Occurrence Lookups
-- Used for: Preventing duplicate bookings, finding specific bookings
-- Query: SELECT * FROM bookings WHERE ride_id = ? AND occurrence_id = ?
--        SELECT * FROM bookings WHERE passenger_id = ? AND ride_id = ? AND occurrence_id = ?
CREATE INDEX IF NOT EXISTS idx_bookings_ride_occurrence 
ON bookings(ride_id, occurrence_id);

-- Index 3: Date Range Queries on Occurrences
-- Used for: Date-based filtering, range queries for cancellation from date
-- Query: SELECT * FROM ride_occurrences 
--        WHERE ride_id = ? AND occurrence_date >= ? AND status = 'active'
--        WHERE occurrence_date >= CURDATE() AND status = 'active'
CREATE INDEX IF NOT EXISTS idx_ride_occurrences_date_status 
ON ride_occurrences(ride_id, occurrence_date, status);

-- Index 4: Recurrence Group Queries
-- Used for: Finding paired recurring rides, filtering recurring rides
-- Query: SELECT * FROM rides WHERE recurrence_group_id = ? AND is_recurring = 1
--        SELECT * FROM rides WHERE is_recurring = 1 AND recurrence_group_id = ?
CREATE INDEX IF NOT EXISTS idx_rides_recurrence_group 
ON rides(recurrence_group_id, is_recurring);
