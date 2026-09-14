import { Router } from 'express';
import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AIController } from '../controllers/ai.controller.js';

const router = Router();
const JWT_SECRET = process.env.JWT_SECRET || 'dolsyx_super_secret_key_123456';

const optionalAuthMiddleware = (req: Request, res: Response, next: NextFunction) => {
  const token = req.headers.authorization?.split(' ')[1];
  if (token) {
    try {
      const decoded = jwt.verify(token, JWT_SECRET);
      (req as any).user = decoded;
    } catch (_) {}
  }
  next();
};

router.post('/chat', optionalAuthMiddleware, AIController.handleChat);
router.post('/generate-image', optionalAuthMiddleware, AIController.generateImage);
router.post('/messages/stream', optionalAuthMiddleware, AIController.streamChat);
router.post('/chat-context', optionalAuthMiddleware, AIController.handleChatContext);
router.post('/classify', optionalAuthMiddleware, AIController.classifyQuery);
router.post('/analyze-image', optionalAuthMiddleware, AIController.analyzeImage);
router.post('/summarize-chat', optionalAuthMiddleware, AIController.summarizeChat);

router.get('/conversations', optionalAuthMiddleware, AIController.getConversations);
router.post('/conversations', optionalAuthMiddleware, AIController.createConversation);
router.delete('/conversations/:id', optionalAuthMiddleware, AIController.deleteConversation);

router.get('/usage', optionalAuthMiddleware, AIController.getUsage);

export default router;
