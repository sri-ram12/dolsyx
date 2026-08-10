import type { Request, Response } from 'express';
import { DolsyxAiEngine } from '../services/dolsyx_ai_engine.js';

export class AIController {
  public static async handleChat(req: Request, res: Response): Promise<void> {
    try {
      const { prompt, history } = req.body;
      const user = (req as any).user;

      if (!prompt || typeof prompt !== 'string') {
        res.status(400).json({ error: 'Prompt string is required' });
        return;
      }

      const replyText = await DolsyxAiEngine.processQuery(prompt, history || [], user?.username);
      res.json({
        reply: replyText,
        sender: 'DOLSYX AI',
        createdAt: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message || 'DOLSYX AI Engine Error' });
    }
  }
}
