import { Router } from 'express';
import { uploadKeys, fetchKeys } from '../controllers/key.controller.js';
import { authenticateToken } from '../middleware/auth.middleware.js';

const router = Router();

// Upload public keys (Identity, Signed PreKey, One-Time PreKeys)
router.post('/upload', authenticateToken, uploadKeys);

// Fetch recipient's public keys (Identity, Signed PreKey, and one One-Time PreKey)
router.get('/fetch/:email', authenticateToken, fetchKeys);

export default router;
