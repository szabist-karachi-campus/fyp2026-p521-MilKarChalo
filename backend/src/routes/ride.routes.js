import { Router } from 'express';
import {
  postRide, searchRides, bookRide,
  getDriverBookingRequests, respondToBooking, getPassengerBookings, getDriverRides,
  getDriverRideDetails, startDriverRide, cancelDriverRide, cancelDriverRoundTrip, endDriverRide,
  submitRideReview, getReceivedReviews,
  cancelPassengerBooking, cancelPassengerBookingGroup,
  getRideOccurrences, cancelOccurrence, cancelRecurringSeries,
  getEta, getPlaces,
} from '../controllers/ride.controller.js';
import { authRequired } from '../middlewares/auth.js';
import { body } from 'express-validator';

const r = Router();

r.post('/post', authRequired, [
  body('pickup_location').notEmpty(),
  body('destination').notEmpty(),
  body('departure_time').isISO8601(),
  body('total_seats').isInt({ min: 1 }),
  body('fare').isDecimal(),
  body('round_trip_enabled').optional().isBoolean(),
  body('return_departure_time').optional().isISO8601(),
  body('return_total_seats').optional().isInt({ min: 1 }),
  body('return_fare').optional().isDecimal(),
  // Recurring ride fields
  body('is_recurring').optional().isBoolean(),
  body('recurrence_type').optional().isIn(['daily','weekly','custom']),
  body('recurrence_days').optional().isArray(),
  body('recurrence_days.*').optional().isInt({ min: 1, max: 7 }),
  body('recurrence_start_date').optional().isDate(),
  body('recurrence_end_date').optional().isDate(),
], postRide);

r.get('/search',            authRequired, searchRides);
r.get('/booking-requests',  authRequired, getDriverBookingRequests);
r.get('/my-bookings',       authRequired, getPassengerBookings);
r.get('/my-rides',          authRequired, getDriverRides);
r.get('/my-rides/:rideId',   authRequired, getDriverRideDetails);
r.get('/eta',               authRequired, getEta);
r.get('/places',            authRequired, getPlaces);

r.post('/book', authRequired, [
  body('ride_id').optional().isInt({ min: 1 }),
  body('ride_ids').optional().isArray({ min: 1 }),
  body('ride_ids.*').optional().isInt({ min: 1 }),
  body('seats_requested').optional().isInt({ min: 1 }),
  body('occurrence_id').optional().isInt({ min: 1 }),
], bookRide);

r.post('/respond-booking', authRequired, [
  body('booking_id').isInt({ min: 1 }),
  body('action').isIn(['accepted', 'rejected']),
], respondToBooking);

r.post('/bookings/:bookingId/cancel', authRequired, cancelPassengerBooking);
r.post('/booking-groups/:groupId/cancel', authRequired, cancelPassengerBookingGroup);

// ── Recurring ride endpoints ──────────────────────────────────────────────────
r.get('/my-rides/:rideId/occurrences',            authRequired, getRideOccurrences);
r.post('/my-rides/:rideId/cancel-recurring',       authRequired, cancelRecurringSeries);
r.post('/occurrences/:occurrenceId/cancel',        authRequired, cancelOccurrence);

r.post('/reviews', authRequired, [
  body('booking_id').isInt({ min: 1 }),
  body('rating').isInt({ min: 1, max: 5 }),
  body('comment').optional().isString().isLength({ max: 1000 }),
], submitRideReview);
r.get('/reviews/received', authRequired, getReceivedReviews);

r.post('/my-rides/:rideId/start', authRequired, startDriverRide);
r.post('/my-rides/:rideId/cancel', authRequired, cancelDriverRide);
r.post('/my-rides/:rideId/cancel-round-trip', authRequired, cancelDriverRoundTrip);
r.post('/my-rides/:rideId/end', authRequired, endDriverRide);

// Must be after all fixed-path routes to avoid swallowing them
r.get('/:rideId/occurrences', authRequired, getRideOccurrences);

export default r;
