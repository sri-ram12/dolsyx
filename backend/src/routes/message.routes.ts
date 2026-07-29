import { Router } from 'express';
import { sendEncryptedMessage, syncEncryptedMessages } from '../controllers/message.controller.js';
import { authenticateToken } from '../middleware/auth.middleware.js';

const router = Router();

router.post('/send', authenticateToken, sendEncryptedMessage);
router.get('/sync', authenticateToken, syncEncryptedMessages);

export default router;
