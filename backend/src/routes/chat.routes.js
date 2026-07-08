import { Router } from 'express';
import { authRequired } from '../middlewares/auth.js';
import { getOrCreateConversation, getMessages } from '../controllers/chat.controller.js';

const r = Router();

r.post('/conversations', authRequired, getOrCreateConversation);
r.get('/conversations/:conversationId/messages', authRequired, getMessages);

export default r;
