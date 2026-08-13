import type { Request, Response } from 'express';
import { prisma } from '../config/db.js';
import { AIOrchestrator } from '../services/ai_orchestrator.js';
import { ImagePipelineEngine } from '../services/image_pipeline_engine.js';

export class AIController {
  /**
   * Main unified chat handler
   */
  public static async handleChat(req: Request, res: Response): Promise<void> {
    try {
      const { prompt, conversationId, preset, parentImageId } = req.body;
      const user = (req as any).user;
      const userId = user?.id || 'guest_user';

      if (!prompt || typeof prompt !== 'string') {
        res.status(400).json({ error: 'Prompt string is required' });
        return;
      }

      // Classify user intent
      const classification = AIOrchestrator.classifyIntent(prompt);

      // Handle Calculator tool intent
      if (classification.intent === 'CALCULATOR') {
        const mathResult = AIOrchestrator.evaluateMathExpression(prompt);
        res.json({
          reply: mathResult,
          type: 'text',
          sender: 'AI Assistant',
          createdAt: new Date().toISOString(),
        });
        return;
      }

      // Handle Image Generation & Editing Intent
      if (classification.intent === 'IMAGE_GENERATION' || classification.intent === 'IMAGE_EDIT') {
        let parentPrompt: string | undefined = undefined;
        if (parentImageId) {
          try {
            const parentImg = await (prisma as any).aIImage.findUnique({ where: { id: parentImageId } });
            if (parentImg) parentPrompt = parentImg.prompt;
          } catch (_) {}
        }

        const imageRes = ImagePipelineEngine.generateImage(prompt, preset || 'photorealistic', parentPrompt);

        // Record metadata in database if user is authenticated
        let imageRecord: any = null;
        if (user?.id) {
          try {
            let convId = conversationId;
            if (!convId) {
              const conv = await (prisma as any).aIConversation.create({
                data: { userId: user.id, title: prompt.slice(0, 30) },
              });
              convId = conv.id;
            }

            imageRecord = await (prisma as any).aIImage.create({
              data: {
                userId: user.id,
                conversationId: convId,
                storageKey: imageRes.imageUrl,
                imageUrl: imageRes.imageUrl,
                prompt: prompt,
                revisedPrompt: imageRes.enhancedPrompt,
                preset: preset || 'photorealistic',
                parentImageId: parentImageId || null,
              },
            });
          } catch (err) {
            console.error('[AIController] Error persisting AIImage record:', err);
          }
        }

        res.json({
          reply: JSON.stringify({
            type: 'image_result',
            text: imageRes.text,
            imageUrl: imageRes.imageUrl,
            imagePrompt: prompt,
            enhancedPrompt: imageRes.enhancedPrompt,
            imageId: imageRecord?.id || null,
          }),
          type: 'image_result',
          imageUrl: imageRes.imageUrl,
          sender: 'AI Assistant',
          createdAt: new Date().toISOString(),
        });
        return;
      }

      // Handle Regular Text Generation
      let history: any[] = [];
      if (conversationId) {
        history = await AIOrchestrator.buildConversationContext(conversationId);
      }

      const textResult = await AIOrchestrator.generateTextResponse(prompt, history, user?.username);

      // Record text message in DB if user is logged in
      if (user?.id && conversationId) {
        try {
          await (prisma as any).aIMessage.createMany({
            data: [
              { conversationId, sender: 'USER', type: 'USER_TEXT', content: prompt },
              { conversationId, sender: 'AI', type: 'AI_TEXT', content: textResult.text, model: textResult.model, tokenUsage: textResult.tokens },
            ],
          });
        } catch (_) {}
      }

      res.json({
        reply: textResult.text,
        type: 'text',
        model: textResult.model,
        sender: 'AI Assistant',
        createdAt: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message || 'AI Engine Error' });
    }
  }

  /**
   * SSE Server-Sent Events Token Streaming Endpoint
   */
  public static async streamChat(req: Request, res: Response): Promise<void> {
    const { prompt } = req.body;
    if (!prompt) {
      res.status(400).json({ error: 'Prompt is required' });
      return;
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    const result = await AIOrchestrator.generateTextResponse(prompt);
    const tokens = result.text.split(' ');

    for (let i = 0; i < tokens.length; i++) {
      const chunk = (i === 0 ? '' : ' ') + tokens[i];
      res.write(`data: ${JSON.stringify({ token: chunk })}\n\n`);
      await new Promise(r => setTimeout(r, 25));
    }

    res.write(`data: [DONE]\n\n`);
    res.end();
  }

  /**
   * "Ask AI About This Chat" context endpoint
   */
  public static async handleChatContext(req: Request, res: Response): Promise<void> {
    try {
      const { conversationId, query } = req.body;
      if (!conversationId) {
        res.status(400).json({ error: 'Conversation ID is required' });
        return;
      }

      // Fetch recent messages from regular chat conversation
      const rawMessages = await (prisma as any).message.findMany({
        where: { conversationId },
        orderBy: { createdAt: 'desc' },
        take: 20,
        include: { sender: { select: { username: true } } },
      });

      const formattedTranscript = rawMessages
        .reverse()
        .map((m: any) => `${m.sender?.username || 'User'}: ${m.content}`)
        .join('\n');

      const userPrompt = query || 'Summarize this conversation and list key takeaways.';
      const contextPrompt = `Context Transcript:\n${formattedTranscript}\n\nTask: ${userPrompt}`;

      const aiReply = await AIOrchestrator.generateTextResponse(contextPrompt);
      res.json({ reply: aiReply.text, type: 'chat_summary' });
    } catch (error: any) {
      res.status(500).json({ error: error.message || 'Failed to process chat context' });
    }
  }

  /**
   * Conversation CRUD
   */
  public static async getConversations(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      if (!user?.id) {
        res.json({ conversations: [] });
        return;
      }

      const list = await (prisma as any).aIConversation.findMany({
        where: { userId: user.id, deletedAt: null },
        orderBy: { updatedAt: 'desc' },
        include: { messages: { take: 1, orderBy: { createdAt: 'desc' } } },
      });

      res.json({ conversations: list });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  public static async createConversation(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const { title, mode } = req.body;
      if (!user?.id) {
        res.status(401).json({ error: 'Unauthorized' });
        return;
      }

      const conv = await (prisma as any).aIConversation.create({
        data: {
          userId: user.id,
          title: title || 'New AI Chat',
          mode: mode || 'NORMAL',
        },
      });

      res.json({ conversation: conv });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  public static async deleteConversation(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      await (prisma as any).aIConversation.update({
        where: { id },
        data: { deletedAt: new Date() },
      });
      res.json({ success: true });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  public static async getUsage(req: Request, res: Response): Promise<void> {
    res.json({
      totalTokens: 14250,
      imageGenerations: 12,
      estimatedCostUSD: 0.045,
      activeModel: 'llama-3.3-70b-versatile',
    });
  }
}
