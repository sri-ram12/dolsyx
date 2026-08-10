import { Router } from 'express';
import { AIController } from '../controllers/ai.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.post('/chat', authMiddleware, AIController.handleChat);

export default router;
