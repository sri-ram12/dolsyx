import { prisma } from '../config/db.js';
import type {
  AIResponsePayload,
  AIStreamCallbacks,
  AIConversationMetadata,
  ToolExecutionContext,
} from './types.js';
import { AISafetyLayer } from './safety-layer.js';
import { AIRateLimiter } from './rate-limiter.js';
import { AIMemoryManager } from './memory-manager.js';
import { AIContextManager } from './context-manager.js';
import { AIPromptManager } from './prompt-manager.js';
import { AIToolRegistry } from './tools/registry.js';
import { AIProviderRegistry } from './provider-registry.js';
import { AISynthesizer } from './synthesizer.js';

export interface ChatOptions {
  userId?: string | undefined;
  username?: string | undefined;
  conversationId?: string | undefined;
  enableTools?: boolean | undefined;
}

export class AIService {
  /**
   * Main unified Chat completion
   */
  public static async chat(prompt: string, options: ChatOptions = {}): Promise<AIResponsePayload> {
    const userId = options.userId || 'guest_user';
    const rateCheck = AIRateLimiter.checkLimit(userId);
    if (!rateCheck.allowed) {
      throw new Error(`Rate limit exceeded. Please wait ${Math.ceil(rateCheck.resetMs / 1000)} seconds.`);
    }

    const { isSafe, flaggedReason, sanitized } = AISafetyLayer.validateInput(prompt);
    if (!isSafe && flaggedReason) {
      throw new Error(flaggedReason);
    }

    // Resolve or create conversation
    let convId = options.conversationId;
    if (userId !== 'guest_user') {
      if (!convId) {
        const titleSnippet = sanitized.slice(0, 30).trim() || 'New Conversation';
        const newConv = await (prisma as any).aIConversation.create({
          data: {
            userId,
            title: titleSnippet,
          },
        });
        convId = newConv.id;
      }
    }

    // Build context and memory
    const history = convId ? await AIContextManager.buildConversationContext(convId, 8) : [];
    const memories = userId !== 'guest_user' ? await AIMemoryManager.getMemories(userId) : [];

    const messages = AIPromptManager.buildPromptMessages(
      sanitized,
      history,
      memories,
      options.username
    );

    const tools = options.enableTools !== false ? AIToolRegistry.getToolDefinitions() : [];
    const toolContext: ToolExecutionContext = {
      userId,
      username: options.username,
      conversationId: convId,
    };

    let result: { text: string; model: string; tokens: number; toolResults?: any[] | undefined };

    if (!AIProviderRegistry.hasExternalApiKey()) {
      const synthText = await AISynthesizer.synthesize(sanitized, options.username);
      result = {
        text: synthText,
        model: 'dolsyx-ai-synthesizer',
        tokens: Math.ceil(synthText.length / 4),
      };
    } else {
      try {
        const provider = AIProviderRegistry.getActiveProvider();
        result = await provider.generateCompletion(messages, tools, toolContext);

        if (!result.text || AISafetyLayer.isBudgetOrQuotaError(result.text)) {
          console.warn('[AIService] Upstream provider returned empty/quota message. Activating intelligent synthesizer.');
          const synthText = await AISynthesizer.synthesize(sanitized, options.username);
          result = {
            text: synthText,
            model: 'dolsyx-ai-synthesizer',
            tokens: Math.ceil(synthText.length / 4),
          };
        }
      } catch (err) {
        console.warn('[AIService] Provider execution failed, activating intelligent synthesizer fallback:', err);
        const synthText = await AISynthesizer.synthesize(sanitized, options.username);
        result = {
          text: synthText,
          model: 'dolsyx-ai-synthesizer',
          tokens: Math.ceil(synthText.length / 4),
        };
      }
    }

    // Persist messages to database if user is authenticated
    if (userId !== 'guest_user' && convId) {
      try {
        await (prisma as any).aIMessage.createMany({
          data: [
            {
              conversationId: convId,
              sender: 'USER',
              type: 'USER_TEXT',
              content: sanitized,
            },
            {
              conversationId: convId,
              sender: 'AI',
              type: 'AI_TEXT',
              content: result.text,
              model: result.model,
              tokenUsage: result.tokens,
              metadata: result.toolResults ? JSON.stringify(result.toolResults) : null,
            },
          ],
        });

        // Track usage
        await (prisma as any).aIUsage.create({
          data: {
            userId,
            requestType: 'TEXT',
            model: result.model,
            inputTokens: Math.ceil(sanitized.length / 4),
            outputTokens: Math.ceil(result.text.length / 4),
          },
        });
      } catch (err) {
        console.warn('[AIService] Failed to persist messages to DB:', err);
      }
    }

    return {
      ...result,
      metadata: {
        conversationId: convId,
        promptVersion: AIPromptManager.PROMPT_VERSION,
      },
    };
  }

  /**
   * Token-by-Token SSE Stream
   */
  public static stream(
    prompt: string,
    options: ChatOptions,
    callbacks: AIStreamCallbacks
  ): () => void {
    const userId = options.userId || 'guest_user';
    const rateCheck = AIRateLimiter.checkLimit(userId);
    if (!rateCheck.allowed) {
      callbacks.onError(new Error(`Rate limit exceeded. Try again in ${Math.ceil(rateCheck.resetMs / 1000)}s.`));
      return () => {};
    }

    const { isSafe, flaggedReason, sanitized } = AISafetyLayer.validateInput(prompt);
    if (!isSafe && flaggedReason) {
      callbacks.onError(new Error(flaggedReason));
      return () => {};
    }

    let convId = options.conversationId;
    let historyPromise = convId ? AIContextManager.buildConversationContext(convId, 8) : Promise.resolve([]);
    let memoriesPromise = userId !== 'guest_user' ? AIMemoryManager.getMemories(userId) : Promise.resolve([]);

    let activeCancel: (() => void) | null = null;

    Promise.all([historyPromise, memoriesPromise])
      .then(async ([history, memories]) => {
        if (userId !== 'guest_user' && !convId) {
          try {
            const newConv = await (prisma as any).aIConversation.create({
              data: {
                userId,
                title: sanitized.slice(0, 30).trim() || 'New AI Chat',
              },
            });
            convId = newConv.id;
          } catch (_) {}
        }

        const messages = AIPromptManager.buildPromptMessages(
          sanitized,
          history,
          memories,
          options.username
        );

        const tools = options.enableTools !== false ? AIToolRegistry.getToolDefinitions() : [];
        const toolContext: ToolExecutionContext = {
          userId,
          username: options.username,
          conversationId: convId,
        };

        if (!AIProviderRegistry.hasExternalApiKey()) {
          activeCancel = AISynthesizer.stream(
            sanitized,
            {
              onToken: callbacks.onToken,
              onComplete: async synthText => {
                if (userId !== 'guest_user' && convId) {
                  try {
                    await (prisma as any).aIMessage.createMany({
                      data: [
                        { conversationId: convId, sender: 'USER', type: 'USER_TEXT', content: sanitized },
                        { conversationId: convId, sender: 'AI', type: 'AI_TEXT', content: synthText },
                      ],
                    });
                  } catch (_) {}
                }
                callbacks.onComplete(synthText, { conversationId: convId });
              },
              onError: callbacks.onError,
            },
            options.username
          );
          return;
        }

        const provider = AIProviderRegistry.getActiveProvider();

        let hasReceivedToken = false;
        let isBudgetErrorDetected = false;
        let streamAccumulator = '';

        activeCancel = provider.streamCompletion(
          messages,
          {
            onToken: token => {
              if (isBudgetErrorDetected) return;
              streamAccumulator += token;
              if (AISafetyLayer.isBudgetOrQuotaError(streamAccumulator)) {
                isBudgetErrorDetected = true;
                if (activeCancel) activeCancel();
                AISynthesizer.stream(
                  sanitized,
                  {
                    onToken: callbacks.onToken,
                    onComplete: async synthText => {
                      if (userId !== 'guest_user' && convId) {
                        try {
                          await (prisma as any).aIMessage.createMany({
                            data: [
                              { conversationId: convId, sender: 'USER', type: 'USER_TEXT', content: sanitized },
                              { conversationId: convId, sender: 'AI', type: 'AI_TEXT', content: synthText },
                            ],
                          });
                        } catch (_) {}
                      }
                      callbacks.onComplete(synthText, { conversationId: convId });
                    },
                    onError: callbacks.onError,
                  },
                  options.username
                );
                return;
              }
              hasReceivedToken = true;
              callbacks.onToken(token);
            },
            onToolCall: callbacks.onToolCall,
            onComplete: async fullText => {
              if (isBudgetErrorDetected) return;
              if (AISafetyLayer.isBudgetOrQuotaError(fullText)) {
                const synthText = await AISynthesizer.synthesize(sanitized, options.username);
                callbacks.onComplete(synthText, { conversationId: convId });
                return;
              }
              if (userId !== 'guest_user' && convId) {
                try {
                  await (prisma as any).aIMessage.createMany({
                    data: [
                      { conversationId: convId, sender: 'USER', type: 'USER_TEXT', content: sanitized },
                      { conversationId: convId, sender: 'AI', type: 'AI_TEXT', content: fullText },
                    ],
                  });
                } catch (_) {}
              }
              callbacks.onComplete(fullText, { conversationId: convId });
            },
            onError: err => {
              console.warn('[AIService] Stream error from provider, activating synthesizer fallback:', err);
              if (!hasReceivedToken) {
                AISynthesizer.stream(
                  sanitized,
                  {
                    onToken: callbacks.onToken,
                    onComplete: async synthText => {
                      callbacks.onComplete(synthText, { conversationId: convId });
                    },
                    onError: callbacks.onError,
                  },
                  options.username
                );
              } else {
                callbacks.onError(err);
              }
            },
          },
          tools,
          toolContext
        );
      })
      .catch(err => {
        console.warn('[AIService] Stream initialization failed, activating synthesizer fallback:', err);
        AISynthesizer.stream(
          sanitized,
          {
            onToken: callbacks.onToken,
            onComplete: async synthText => {
              callbacks.onComplete(synthText, { conversationId: convId });
            },
            onError: callbacks.onError,
          },
          options.username
        );
      });

    return () => {
      if (activeCancel) activeCancel();
    };
  }

  /**
   * Message Contextual Actions ("Ask AI" for messages)
   */
  public static async handleContextAction(
    action: 'explain' | 'summarize' | 'translate' | 'rewrite' | 'fix_grammar' | 'make_professional' | 'generate_reply',
    text: string,
    targetLanguage?: string
  ): Promise<string> {
    let instruction = '';
    switch (action) {
      case 'explain':
        instruction = 'Explain this clearly and concisely:';
        break;
      case 'summarize':
        instruction = 'Provide a crisp bulleted summary of this:';
        break;
      case 'translate':
        instruction = `Translate this into ${targetLanguage || 'Telugu'} accurately:`;
        break;
      case 'rewrite':
        instruction = 'Rewrite this to be engaging, natural, and clear:';
        break;
      case 'fix_grammar':
        instruction = 'Fix all grammar and punctuation errors without altering original meaning:';
        break;
      case 'make_professional':
        instruction = 'Rewrite this in a polished, professional business tone:';
        break;
      case 'generate_reply':
        instruction = 'Generate 3 distinct, natural reply suggestions to this message:';
        break;
    }

    const prompt = `${instruction}\n\n"${text}"`;
    const res = await this.chat(prompt, { enableTools: false });
    return res.text;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CONVERSATION CRUD
  // ─────────────────────────────────────────────────────────────────────────────

  public static async getConversations(userId: string): Promise<AIConversationMetadata[]> {
    if (!userId || userId === 'guest_user') return [];

    try {
      const records = await (prisma as any).aIConversation.findMany({
        where: { userId, deletedAt: null },
        orderBy: { updatedAt: 'desc' },
        include: {
          messages: {
            take: 1,
            orderBy: { createdAt: 'desc' },
            select: { content: true },
          },
        },
      });

      return records.map((r: any) => ({
        id: r.id,
        userId: r.userId,
        title: r.title,
        mode: r.mode,
        createdAt: r.createdAt.toISOString(),
        updatedAt: r.updatedAt.toISOString(),
        lastMessageSnippet: r.messages?.[0]?.content?.slice(0, 60) || '',
      }));
    } catch (err) {
      console.warn('[AIService] Failed to list conversations:', err);
      return [];
    }
  }

  public static async getConversationById(userId: string, conversationId: string): Promise<any> {
    if (!userId || !conversationId) return null;

    try {
      const conv = await (prisma as any).aIConversation.findFirst({
        where: { id: conversationId, userId, deletedAt: null },
        include: {
          messages: {
            orderBy: { createdAt: 'asc' },
          },
        },
      });
      return conv;
    } catch (_) {
      return null;
    }
  }

  public static async createConversation(userId: string, title?: string, mode?: string): Promise<any> {
    if (!userId || userId === 'guest_user') return null;

    return (prisma as any).aIConversation.create({
      data: {
        userId,
        title: title || 'New AI Chat',
        mode: mode || 'NORMAL',
      },
    });
  }

  public static async updateConversation(userId: string, conversationId: string, title: string): Promise<boolean> {
    if (!userId || !conversationId) return false;

    try {
      await (prisma as any).aIConversation.updateMany({
        where: { id: conversationId, userId },
        data: { title },
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  public static async deleteConversation(userId: string, conversationId: string): Promise<boolean> {
    if (!userId || !conversationId) return false;

    try {
      await (prisma as any).aIConversation.updateMany({
        where: { id: conversationId, userId },
        data: { deletedAt: new Date() },
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  public static async clearConversationMessages(userId: string, conversationId: string): Promise<boolean> {
    if (!userId || !conversationId) return false;

    try {
      // Verify user owns conversation
      const conv = await (prisma as any).aIConversation.findFirst({
        where: { id: conversationId, userId },
      });
      if (!conv) return false;

      await (prisma as any).aIMessage.deleteMany({
        where: { conversationId },
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  public static async recordFeedback(userId: string, messageId: string, feedback: 'UP' | 'DOWN', comment?: string): Promise<boolean> {
    try {
      await (prisma as any).aIMessage.update({
        where: { id: messageId },
        data: {
          feedback,
          metadata: comment ? JSON.stringify({ feedbackComment: comment }) : undefined,
        },
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
