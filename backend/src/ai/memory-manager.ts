import { prisma } from '../config/db.js';
import type { AIMemoryItem } from './types.js';

export class AIMemoryManager {
  /**
   * Retrieves active memories for a given user.
   */
  public static async getMemories(userId: string): Promise<AIMemoryItem[]> {
    if (!userId || userId === 'guest_user') return [];

    try {
      const records = await (prisma as any).aIMemory.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        take: 20,
      });

      return records.map((r: any) => ({
        id: r.id,
        userId: r.userId,
        content: r.content,
        category: r.category as 'PREFERENCE' | 'FACT' | 'INSTRUCTION',
        source: r.source,
        createdAt: r.createdAt,
      }));
    } catch (err) {
      console.warn('[AIMemoryManager] Failed to fetch memories:', err);
      return [];
    }
  }

  /**
   * Saves a user memory / preference.
   */
  public static async saveMemory(
    userId: string,
    content: string,
    category: 'PREFERENCE' | 'FACT' | 'INSTRUCTION' = 'PREFERENCE',
    source: string = 'AI_EXTRACTED'
  ): Promise<AIMemoryItem | null> {
    if (!userId || userId === 'guest_user' || !content.trim()) return null;

    try {
      // Avoid duplicate memories with identical content
      const existing = await (prisma as any).aIMemory.findFirst({
        where: { userId, content: content.trim() },
      });

      if (existing) {
        return existing;
      }

      const created = await (prisma as any).aIMemory.create({
        data: {
          userId,
          content: content.trim(),
          category,
          source,
        },
      });

      return created;
    } catch (err) {
      console.error('[AIMemoryManager] Failed to save memory:', err);
      return null;
    }
  }

  /**
   * Deletes a specific memory item.
   */
  public static async deleteMemory(userId: string, memoryId: string): Promise<boolean> {
    if (!userId || !memoryId) return false;

    try {
      await (prisma as any).aIMemory.deleteMany({
        where: { id: memoryId, userId },
      });
      return true;
    } catch (err) {
      console.error('[AIMemoryManager] Failed to delete memory:', err);
      return false;
    }
  }

  /**
   * Clears all memories for a user.
   */
  public static async clearAllMemories(userId: string): Promise<boolean> {
    if (!userId) return false;

    try {
      await (prisma as any).aIMemory.deleteMany({
        where: { userId },
      });
      return true;
    } catch (err) {
      console.error('[AIMemoryManager] Failed to clear memories:', err);
      return false;
    }
  }
}
