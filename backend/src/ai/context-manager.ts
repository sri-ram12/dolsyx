import { prisma } from '../config/db.js';
import type { ChatMessage } from './types.js';

export class AIContextManager {
  private static readonly MAX_CONTEXT_TOKENS = 6000;
  private static readonly ESTIMATED_CHARS_PER_TOKEN = 4;

  /**
   * Builds conversation context from previous messages stored in database.
   */
  public static async buildConversationContext(
    conversationId: string,
    messageLimit: number = 10
  ): Promise<ChatMessage[]> {
    if (!conversationId) return [];

    try {
      const messages = await (prisma as any).aIMessage.findMany({
        where: { conversationId },
        orderBy: { createdAt: 'desc' },
        take: messageLimit,
      });

      // Reverse so messages are chronological (oldest to newest)
      const chronological = messages.reverse();

      const contextMessages: ChatMessage[] = [];
      let totalTokens = 0;

      for (const msg of chronological) {
        const approxTokens = Math.ceil((msg.content?.length || 0) / this.ESTIMATED_CHARS_PER_TOKEN);
        if (totalTokens + approxTokens > this.MAX_CONTEXT_TOKENS) {
          break;
        }

        totalTokens += approxTokens;
        contextMessages.push({
          role: msg.sender === 'USER' ? 'user' : 'assistant',
          content: msg.content,
        });
      }

      return contextMessages;
    } catch (err) {
      console.warn('[AIContextManager] Error retrieving context history:', err);
      return [];
    }
  }

  /**
   * Formats chat transcript for contextual summarization / Q&A.
   */
  public static formatChatTranscript(
    messages: Array<{ senderName?: string; content: string; createdAt?: Date | string }>
  ): string {
    return messages
      .map(m => {
        const time = m.createdAt ? new Date(m.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
        const sender = m.senderName || 'User';
        return `[${time}] ${sender}: ${m.content}`;
      })
      .join('\n');
  }
}
