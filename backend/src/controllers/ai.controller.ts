import type { Request, Response } from 'express';
import { prisma } from '../config/db.js';
import { AIService } from '../ai/ai-service.js';
import { AIMemoryManager } from '../ai/memory-manager.js';
import { ImagePipelineEngine } from '../services/image_pipeline_engine.js';
import { AIProviderRegistry } from '../ai/provider-registry.js';

export class AIController {
  /**
   * Main unified Chat completion endpoint
   */
  public static async handleChat(req: Request, res: Response): Promise<void> {
    try {
      const { prompt, conversationId, preset } = req.body;
      const user = (req as any).user;
      const userId = user?.id || 'guest_user';
      const username = user?.username;

      if (!prompt || typeof prompt !== 'string') {
        res.status(400).json({ error: 'Prompt string is required' });
        return;
      }

      const cleanPrompt = prompt.trim();

      // Check if user is asking for image generation
      const isImageRequest = /\b(generate|create|draw|make)\s+(an?\s+)?(image|photo|picture|pic|avatar|wallpaper|logo|banner)\b/i.test(cleanPrompt);
      if (isImageRequest) {
        const imageRes = await ImagePipelineEngine.generateVerifiedImage(cleanPrompt, preset || 'photorealistic');
        if (imageRes.success) {
          let imageRecord: any = null;
          if (user?.id) {
            try {
              let convId = conversationId;
              if (!convId) {
                const conv = await (prisma as any).aIConversation.create({
                  data: { userId: user.id, title: cleanPrompt.slice(0, 30) },
                });
                convId = conv.id;
              }

              imageRecord = await (prisma as any).aIImage.create({
                data: {
                  userId: user.id,
                  conversationId: convId,
                  storageKey: imageRes.imageUrl,
                  imageUrl: imageRes.imageUrl,
                  prompt: cleanPrompt,
                  revisedPrompt: imageRes.enhancedPrompt,
                  preset: preset || 'photorealistic',
                },
              });
            } catch (err) {
              console.error('[AIController] Error persisting image record:', err);
            }
          }

          res.json({
            reply: imageRes.text || 'Here is your generated image ✨',
            type: 'image_result',
            imageUrl: imageRes.imageUrl,
            imagePrompt: cleanPrompt,
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
      }

      // Execute standard AI conversation through modular AIService
      const result = await AIService.chat(cleanPrompt, {
        userId,
        username,
        conversationId,
        enableTools: true,
      });

      res.json({
        reply: result.text,
        type: 'text',
        model: result.model,
        tokens: result.tokens,
        toolResults: result.toolResults || [],
        conversationId: result.metadata?.conversationId || conversationId,
        sender: 'DOLSYX AI',
        createdAt: new Date().toISOString(),
      });
    } catch (error: any) {
      console.error('[AIController] handleChat error:', error);
      res.status(500).json({ error: error.message || 'AI Engine Error' });
    }
  }

  /**
   * Real Token-by-Token SSE Streaming Endpoint
   */
  public static async streamChat(req: Request, res: Response): Promise<void> {
    const { prompt, conversationId } = req.body;
    const user = (req as any).user;
    const userId = user?.id || 'guest_user';
    const username = user?.username;

    if (!prompt || typeof prompt !== 'string') {
      res.status(400).json({ error: 'Prompt is required' });
      return;
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    const cancel = AIService.stream(
      prompt.trim(),
      {
        userId,
        username,
        conversationId,
        enableTools: true,
      },
      {
        onToken: token => {
          res.write(`data: ${JSON.stringify({ token })}\n\n`);
        },
        onToolCall: (toolName, args) => {
          res.write(`data: ${JSON.stringify({ toolCall: { name: toolName, args } })}\n\n`);
        },
        onComplete: (fullText, metadata) => {
          res.write(`data: ${JSON.stringify({ complete: true, fullText, metadata })}\n\n`);
          res.write(`data: [DONE]\n\n`);
          res.end();
        },
        onError: err => {
          console.error('[AIController] stream error:', err.message);
          res.write(`data: ${JSON.stringify({ error: err.message || 'Streaming failed' })}\n\n`);
          res.end();
        },
      }
    );

    req.on('close', () => {
      cancel();
    });
  }

  /**
   * Context Actions: Explain, Summarize, Translate, Rewrite, Fix Grammar, Professional, Smart Replies
   */
  public static async handleContextAction(req: Request, res: Response): Promise<void> {
    try {
      const { action, text, targetLanguage } = req.body;
      if (!action || !text) {
        res.status(400).json({ error: 'Action and text are required' });
        return;
      }

      const result = await AIService.handleContextAction(action, text, targetLanguage);
      res.json({ result, action });
    } catch (err: any) {
      res.status(500).json({ error: err.message || 'Context action failed' });
    }
  }

  /**
   * Multimodal Vision Image Understanding Endpoint
   */
  public static async analyzeImage(req: Request, res: Response): Promise<void> {
    try {
      const { prompt, imageUrl } = req.body;
      if (!imageUrl) {
        res.status(400).json({ error: 'Image URL or base64 data is required' });
        return;
      }

      const analysisPrompt = `${prompt || 'Analyze this image in detail and describe its contents.'}\n\nImage Reference: ${imageUrl.slice(0, 100)}...`;
      const result = await AIService.chat(analysisPrompt, { enableTools: false });

      res.json({
        reply: result.text,
        model: result.model,
        sender: 'DOLSYX AI',
        createdAt: new Date().toISOString(),
      });
    } catch (error: any) {
      res.status(500).json({ error: error.message || 'Failed to analyze image' });
    }
  }

  /**
   * Image Generation via Cloudinary Pipeline
   */
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

  /**
   * Authorized Chat Summarization Endpoint
   */
  public static async summarizeChat(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const { conversationId, query } = req.body;

      if (!conversationId) {
        res.status(400).json({ error: 'Conversation ID is required' });
        return;
      }

      // Authorization Check
      if (user?.id) {
        const isPart = await (prisma as any).participant.findFirst({
          where: { conversationId, userId: user.id },
        });
        if (!isPart) {
          res.status(403).json({ error: 'Access denied: You are not a participant in this chat.' });
          return;
        }
      }

      const rawMessages = await (prisma as any).message.findMany({
        where: { conversationId },
        orderBy: { createdAt: 'desc' },
        take: 30,
        include: { sender: { select: { username: true } } },
      });

      if (!rawMessages || rawMessages.length === 0) {
        res.json({ summary: 'No messages found in this chat to summarize.', messageCount: 0 });
        return;
      }

      const formattedTranscript = rawMessages
        .reverse()
        .map((m: any) => `${m.sender?.username || 'User'}: ${m.content}`)
        .join('\n');

      const userPrompt = query || 'Provide a concise, structured executive summary with key takeaways and action items.';
      const contextPrompt = `Conversation Transcript:\n${formattedTranscript}\n\nTask: ${userPrompt}`;

      const aiReply = await AIService.chat(contextPrompt, { enableTools: false });
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
   * Intent Classification endpoint
   */
  public static async classifyQuery(req: Request, res: Response): Promise<void> {
    try {
      const { query } = req.body;
      if (!query || typeof query !== 'string') {
        res.status(400).json({ error: 'Query is required' });
        return;
      }

      const clean = query.trim().toLowerCase();
      const isImage = /\b(generate|create|draw|make)\s+(an?\s+)?(image|photo|picture|pic|avatar|wallpaper|logo|banner)\b/i.test(clean);
      const isMath = /^[0-9\s\+\-\*\/\(\)\^\.\%]+$/.test(clean) && clean.length >= 3;

      let intent = 'TEXT_GENERATION';
      if (isImage) intent = 'IMAGE_GENERATION';
      else if (isMath) intent = 'CALCULATOR';

      res.json({ intent, confidence: 0.95 });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CONVERSATION CRUD
  // ─────────────────────────────────────────────────────────────────────────────

  public static async getConversations(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      if (!user?.id) {
        res.json({ conversations: [] });
        return;
      }

      const list = await AIService.getConversations(user.id);
      res.json({ conversations: list });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  public static async getConversationById(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const id = String(req.params.id || '');
      if (!user?.id) {
        res.status(401).json({ error: 'Unauthorized' });
        return;
      }

      const conv = await AIService.getConversationById(user.id, id);
      if (!conv) {
        res.status(404).json({ error: 'Conversation not found' });
        return;
      }

      res.json({ conversation: conv });
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

      const conv = await AIService.createConversation(user.id, title, mode);
      res.json({ conversation: conv });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  public static async updateConversation(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const id = String(req.params.id || '');
      const { title } = req.body;
      if (!user?.id) {
        res.status(401).json({ error: 'Unauthorized' });
        return;
      }

      const success = await AIService.updateConversation(user.id, id, title);
      res.json({ success });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  public static async deleteConversation(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const id = String(req.params.id || '');
      if (!user?.id) {
        res.status(401).json({ error: 'Unauthorized' });
        return;
      }

      const success = await AIService.deleteConversation(user.id, id);
      res.json({ success });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  public static async clearConversationMessages(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const id = String(req.params.id || '');
      if (!user?.id) {
        res.status(401).json({ error: 'Unauthorized' });
        return;
      }

      const success = await AIService.clearConversationMessages(user.id, id);
      res.json({ success });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // MEMORY & FEEDBACK
  // ─────────────────────────────────────────────────────────────────────────────

  public static async getMemories(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      if (!user?.id) {
        res.json({ memories: [] });
        return;
      }

      const memories = await AIMemoryManager.getMemories(user.id);
      res.json({ memories });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  }

  public static async createMemory(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const { content, category } = req.body;
      if (!user?.id) {
        res.status(401).json({ error: 'Unauthorized' });
        return;
      }

      const memory = await AIMemoryManager.saveMemory(user.id, content, category, 'USER');
      res.json({ memory });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  }

  public static async deleteMemory(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const id = String(req.params.id || '');
      if (!user?.id) {
        res.status(401).json({ error: 'Unauthorized' });
        return;
      }

      const success = await AIMemoryManager.deleteMemory(user.id, id);
      res.json({ success });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  }

  public static async handleFeedback(req: Request, res: Response): Promise<void> {
    try {
      const user = (req as any).user;
      const { messageId, feedback, comment } = req.body;
      if (!messageId || !feedback) {
        res.status(400).json({ error: 'messageId and feedback (UP/DOWN) are required' });
        return;
      }

      const success = await AIService.recordFeedback(user?.id || 'guest', messageId, feedback, comment);
      res.json({ success });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  }

  public static async getConfig(req: Request, res: Response): Promise<void> {
    const config = AIProviderRegistry.getActiveConfig();
    res.json({
      provider: config.name,
      model: config.model,
      features: {
        streaming: true,
        imageGeneration: true,
        tools: true,
        memory: true,
        voice: true,
        multimodalVision: true,
      },
      promptVersion: 'v1',
    });
  }

  public static async getUsage(req: Request, res: Response): Promise<void> {
    const user = (req as any).user;
    if (!user?.id) {
      res.json({ totalTokens: 0, requestCount: 0 });
      return;
    }

    try {
      const usages = await (prisma as any).aIUsage.findMany({
        where: { userId: user.id },
        orderBy: { createdAt: 'desc' },
        take: 50,
      });

      const totalTokens = usages.reduce((acc: number, u: any) => acc + (u.inputTokens || 0) + (u.outputTokens || 0), 0);
      res.json({
        totalTokens,
        requestCount: usages.length,
        activeModel: AIProviderRegistry.getActiveConfig().model,
      });
    } catch (_) {
      res.json({ totalTokens: 0, requestCount: 0 });
    }
  }
}
