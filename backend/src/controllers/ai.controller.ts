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
          sender: 'DOLSYX AI',
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

        const imageRes = await ImagePipelineEngine.generateVerifiedImage(prompt, preset || 'photorealistic', parentPrompt);

        if (!imageRes.success) {
          res.json({
            reply: imageRes.error || 'Failed to generate image. Please try a different prompt.',
            type: 'text',
            error: imageRes.error,
            sender: 'DOLSYX AI',
            createdAt: new Date().toISOString(),
          });
          return;
        }

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
          reply: imageRes.text,
          type: 'image_result',
          imageUrl: imageRes.imageUrl,
          imagePrompt: prompt,
          enhancedPrompt: imageRes.enhancedPrompt,
          media: {
            url: imageRes.imageUrl,
            width: imageRes.width,
            height: imageRes.height,
          },
          imageId: imageRecord?.id || null,
          sender: 'DOLSYX AI',
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
        sender: 'DOLSYX AI',
        createdAt: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message || 'AI Engine Error' });
    }
  }

  /**
   * Real Token-by-Token SSE Server-Sent Events Streaming Endpoint
   */
  public static async streamChat(req: Request, res: Response): Promise<void> {
    const { prompt, conversationId } = req.body;
    if (!prompt) {
      res.status(400).json({ error: 'Prompt is required' });
      return;
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    let history: any[] = [];
    if (conversationId) {
      history = await AIOrchestrator.buildConversationContext(conversationId);
    }

    const cancel = AIOrchestrator.streamTextResponse(
      prompt,
      history,
      (token) => {
        res.write(`data: ${JSON.stringify({ token })}\n\n`);
      },
      (fullText) => {
        res.write(`data: [DONE]\n\n`);
        res.end();
      },
      (err) => {
        console.error('[AIController] Stream error:', err);
        res.write(`data: ${JSON.stringify({ error: err.message || 'Streaming failed' })}\n\n`);
        res.end();
      }
    );

    req.on('close', () => {
      cancel();
    });
  }

  /**
   * Intent Classification endpoint for Main Search Bar
   */
  public static async classifyQuery(req: Request, res: Response): Promise<void> {
    try {
      const { query, hasAttachment } = req.body;
      if (!query || typeof query !== 'string') {
        res.status(400).json({ error: 'Query string is required' });
        return;
      }

      const classification = AIOrchestrator.classifyIntent(query, !!hasAttachment);
      res.json(classification);
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  /**
   * Multimodal Vision Image Understanding Endpoint
   */
  public static async analyzeImage(req: Request, res: Response): Promise<void> {
    try {
      const { prompt, imageUrl } = req.body;
      if (!imageUrl) {
        res.status(400).json({ error: 'Image URL or data is required' });
        return;
      }

      const result = await AIOrchestrator.analyzeImage(prompt || 'Analyze this image in detail', imageUrl);
      res.json({
        reply: result.text,
        model: result.model,
        sender: 'DOLSYX AI',
        createdAt: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  /**
   * Authorized Chat Summarization & Intelligence Endpoint
   */
  public static async summarizeChat(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const { conversationId, query } = req.body;
      if (!conversationId) {
        res.status(400).json({ error: 'Conversation ID is required' });
        return;
      }

      // Security Check: Caller must be a participant of the conversation
      if (user?.id) {
        const isParticipant = await (prisma as any).participant.findFirst({
          where: { conversationId, userId: user.id },
        });
        if (!isParticipant) {
          res.status(403).json({ error: 'Access denied: You are not a participant in this conversation.' });
          return;
        }
      }

      // Fetch recent messages
      const rawMessages = await (prisma as any).message.findMany({
        where: { conversationId },
        orderBy: { createdAt: 'desc' },
        take: 30,
        include: { sender: { select: { username: true } } },
      });

      if (!rawMessages || rawMessages.length === 0) {
        res.json({ summary: 'No messages found in this conversation to summarize.', messageCount: 0 });
        return;
      }

      const formattedTranscript = rawMessages
        .reverse()
        .map((m: any) => `${m.sender?.username || 'User'}: ${m.content}`)
        .join('\n');

      const userPrompt = query || 'Provide a concise, structured summary of what was discussed, key decisions made, and any action items.';
      const contextPrompt = `Conversation Transcript:\n${formattedTranscript}\n\nTask: ${userPrompt}`;

      const aiReply = await AIOrchestrator.generateTextResponse(contextPrompt);
      res.json({
        summary: aiReply.text,
        messageCount: rawMessages.length,
        sender: 'DOLSYX AI',
        createdAt: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message || 'Failed to summarize conversation' });
    }
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
      res.json({ reply: aiReply.text, type: 'chat_summary', sender: 'DOLSYX AI' });
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

  public static async generateImage(req: Request, res: Response): Promise<void> {
    try {
      const { prompt, preset, parentPrompt } = req.body;
      if (!prompt || typeof prompt !== 'string') {
        res.status(400).json({ error: 'Prompt is required', success: false });
        return;
      }
      const imageRes = await ImagePipelineEngine.generateVerifiedImage(prompt, preset || 'photorealistic', parentPrompt);
      if (!imageRes.success) {
        res.status(500).json({ error: imageRes.error || 'Image generation failed', success: false });
        return;
      }
      res.json({
        success: true,
        imageUrl: imageRes.imageUrl,
        enhancedPrompt: imageRes.enhancedPrompt,
        text: imageRes.text,
        sender: 'DOLSYX AI',
        createdAt: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message || 'Image generation failed', success: false });
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
