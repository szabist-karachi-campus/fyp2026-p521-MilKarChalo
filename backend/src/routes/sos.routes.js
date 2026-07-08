import { Router } from 'express';
import { authRequired } from '../middlewares/auth.js';
import {
  getEmergencyContacts, addEmergencyContact,
  updateEmergencyContact, deleteEmergencyContact,
  activateSos, deactivateSos, getActiveSos, updateSosLocation,
  getAdminSosEvents,
} from '../controllers/sos.controller.js';

const r = Router();

// Emergency contacts
r.get('/emergency-contacts',           authRequired, getEmergencyContacts);
r.post('/emergency-contacts',          authRequired, addEmergencyContact);
r.put('/emergency-contacts/:id',       authRequired, updateEmergencyContact);
r.delete('/emergency-contacts/:id',    authRequired, deleteEmergencyContact);

// SOS events
r.post('/activate',                    authRequired, activateSos);
r.post('/events/:sos_id/deactivate',   authRequired, deactivateSos);
r.get('/bookings/:booking_id/active',  authRequired, getActiveSos);
r.post('/events/:sos_id/location',     authRequired, updateSosLocation);

// Admin — all SOS events (admin-only enforced via role check in admin.routes.js)
r.get('/admin/events',                 authRequired, getAdminSosEvents);

export default r;
