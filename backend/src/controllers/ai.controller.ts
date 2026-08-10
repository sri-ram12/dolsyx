import { Request, Response } from 'express';
import { AIService } from '../services/ai.service';

export class AIController {
  public static async handleChat(req: Request, res: Response): Promise<void> {
    try {
      const { prompt } = req.body;
      const user = (req as any).user;

      if (!prompt || typeof prompt !== 'string') {
        res.status(400).json({ error: 'Prompt string is required' });
        return;
      }

      const responseText = await AIService.generateResponse(prompt, user?.username);
      res.json({
        reply: responseText,
        sender: 'DOLSYX AI',
        createdAt: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message || 'AI Service Error' });
    }
  }
}
