import { Router } from 'express';
import {
  registerFcmToken, getInbox, getUnreadCount, markRead, markReadBulk
} from '../controllers/notification.controller.js';
import { authRequired } from '../middlewares/auth.js';

const r = Router();

r.post('/fcm-token',    authRequired, registerFcmToken);
r.get('/',              authRequired, getInbox);
r.get('/unread-count',  authRequired, getUnreadCount);
r.post('/read-bulk',    authRequired, markReadBulk);
r.post('/:id/read',     authRequired, markRead);

export default r;
