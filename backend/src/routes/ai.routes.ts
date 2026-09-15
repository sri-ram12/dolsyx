import { Router } from 'express';
import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AIController } from '../controllers/ai.controller.js';

const router = Router();
const JWT_SECRET = process.env.JWT_SECRET || 'dolsyx_super_secret_key_123456';

const optionalAuthMiddleware = (req: Request, _res: Response, next: NextFunction) => {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : req.cookies?.token;

  if (token) {
    try {
      const decoded = jwt.verify(token, JWT_SECRET);
      (req as any).user = decoded;
    } catch (_) {}
  }
  next();
};

const requireAuthMiddleware = (req: Request, res: Response, next: NextFunction) => {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : req.cookies?.token;

  if (!token) {
    res.status(401).json({ error: 'Authentication required' });
    return;
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    (req as any).user = decoded;
    next();
  } catch (_) {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
};

// Core Chat & Generation Endpoints
router.post('/chat', optionalAuthMiddleware, AIController.handleChat);
router.post('/stream', optionalAuthMiddleware, AIController.streamChat);
router.post('/messages/stream', optionalAuthMiddleware, AIController.streamChat); // Legacy alias
router.post('/generate-image', optionalAuthMiddleware, AIController.generateImage);
router.post('/analyze-image', optionalAuthMiddleware, AIController.analyzeImage);
router.post('/summarize-chat', optionalAuthMiddleware, AIController.summarizeChat);
router.post('/context-action', optionalAuthMiddleware, AIController.handleContextAction);
router.post('/classify', optionalAuthMiddleware, AIController.classifyQuery);

// Conversation History Management
router.get('/conversations', optionalAuthMiddleware, AIController.getConversations);
router.post('/conversations', requireAuthMiddleware, AIController.createConversation);
router.get('/conversations/:id', requireAuthMiddleware, AIController.getConversationById);
router.put('/conversations/:id', requireAuthMiddleware, AIController.updateConversation);
router.delete('/conversations/:id', requireAuthMiddleware, AIController.deleteConversation);
router.delete('/conversations/:id/messages', requireAuthMiddleware, AIController.clearConversationMessages);

// Memory Management
router.get('/memories', requireAuthMiddleware, AIController.getMemories);
router.post('/memories', requireAuthMiddleware, AIController.createMemory);
router.delete('/memories/:id', requireAuthMiddleware, AIController.deleteMemory);

// Feedback & Monitoring
router.post('/feedback', optionalAuthMiddleware, AIController.handleFeedback);
router.get('/config', AIController.getConfig);
router.get('/usage', optionalAuthMiddleware, AIController.getUsage);

export default router;
