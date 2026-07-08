import { Router } from 'express';
import { upsertPassengerProfile, upsertDriverProfile, upsertVehicle, getMyProfile } from '../controllers/profile.controller.js';
import { authRequired } from '../middlewares/auth.js';
import { upload } from '../middlewares/upload.js';
import { vVehicle } from '../utils/validators.js';

const r = Router();

r.post('/passenger', authRequired, upload.single('image'), upsertPassengerProfile);
r.post('/driver', authRequired, upload.single('image'), upsertDriverProfile);
r.post('/vehicle', authRequired, vVehicle, upsertVehicle);
// FIX: New endpoint to fetch full profile + vehicle data for profile page display
r.get('/me', authRequired, getMyProfile);

export default r;
