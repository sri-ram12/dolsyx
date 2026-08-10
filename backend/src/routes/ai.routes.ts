import { Router, Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AIController } from '../controllers/ai.controller';

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

export default router;
