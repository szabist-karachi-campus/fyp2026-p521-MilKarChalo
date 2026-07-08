import { Router } from 'express';
import { getPendingDrivers, updateDriverStatus, getApprovedDrivers, getAllDrivers, getDriverRides, getRideDetailsAdmin, updateBookingStatus, changeRideStatus, exportRideCsv } from '../controllers/admin.controller.js';
import { getAdminReviews } from '../controllers/admin.controller.js';
import { getAdminSosEvents } from '../controllers/sos.controller.js';
import { authRequired } from '../middlewares/auth.js';

const r = Router();

const adminOnly = (req, res, next) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Admin access only' });
  next();
};

r.get('/pending-drivers',  authRequired, adminOnly, getPendingDrivers);
r.get('/approved-drivers', authRequired, adminOnly, getApprovedDrivers);
r.get('/all-drivers',      authRequired, adminOnly, getAllDrivers);
r.post('/verify-driver',   authRequired, adminOnly, updateDriverStatus);
r.get('/drivers/:driverId/rides', authRequired, adminOnly, getDriverRides);
r.get('/rides/:rideId', authRequired, adminOnly, getRideDetailsAdmin);
r.get('/reviews', authRequired, adminOnly, getAdminReviews);
r.post('/bookings/:bookingId/status', authRequired, adminOnly, updateBookingStatus);
r.post('/rides/:rideId/status', authRequired, adminOnly, changeRideStatus);
r.get('/rides/:rideId/export', authRequired, adminOnly, exportRideCsv);
r.get('/sos-events', authRequired, adminOnly, getAdminSosEvents);

export default r;
