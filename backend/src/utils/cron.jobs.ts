import cron from 'node-cron';
import { prisma } from '../config/db.js';

// ─── Helper: disappearingTimer → milliseconds ────────────────────────────────
const timerToMs = (timer: string): number | null => {
  if (timer === '24H')  return 24 * 60 * 60 * 1000;
  if (timer === '7D')   return 7  * 24 * 60 * 60 * 1000;
  if (timer === '90D')  return 90 * 24 * 60 * 60 * 1000;
  return null;
};

/**
 * Given a conversation disappearingTimer string, returns the UTC Date
 * at which a message created right now should expire. Returns null if OFF.
 * Exported for use in send_message handler.
 */
export const timerToExpiresAt = (timer: string): Date | null => {
  const ms = timerToMs(timer);
  return ms ? new Date(Date.now() + ms) : null;
};

export const initCronJobs = (io?: any) => {
  // ─── Phase 22: Disappearing Messages Cleanup via Message.expiresAt ───────────
  // Runs every 5 minutes. Deletes messages whose expiresAt has passed and
  // broadcasts `messages_expired` so clients purge their local SQLite copies.
  cron.schedule('*/5 * * * *', async () => {
    console.log('[CRON] Phase 22: Disappearing messages expiresAt cleanup...');
    try {
      const expiredMessages = await prisma.message.findMany({
        where: {
          expiresAt: { lt: new Date() },
          isDeleted: false,
        },
        select: { id: true, conversationId: true },
        take: 500,   // batch cap; runs again in 5m for remainder
      });

      if (expiredMessages.length === 0) {
        console.log('[CRON] Phase 22: No expired messages found.');
        return;
      }

      // Group by conversationId for targeted socket broadcast
      const byConversation = new Map<string, string[]>();
      for (const m of expiredMessages) {
        if (!byConversation.has(m.conversationId)) byConversation.set(m.conversationId, []);
        byConversation.get(m.conversationId)!.push(m.id);
      }

      // Broadcast BEFORE delete so clients can act immediately
      if (io) {
        for (const [conversationId, messageIds] of byConversation.entries()) {
          io.to(conversationId).emit('messages_expired', { conversationId, messageIds });
        }
      }

      const ids = expiredMessages.map((m) => m.id);
      await prisma.message.deleteMany({ where: { id: { in: ids } } });

      console.log(`[CRON] Phase 22: Deleted ${expiredMessages.length} expired messages.`);
    } catch (error) {
      console.error('[CRON] Phase 22 error:', error);
    }
  });

  // ─── Status Expiry Cleanup (24h TTL) ────────────────────────────────────────
  cron.schedule('*/30 * * * *', async () => {
    console.log('[CRON] Running status expiry cleanup job...');
    try {
      const expiredStatuses = await prisma.status.findMany({
        where: { expiresAt: { lt: new Date() } },
        select: { id: true, userId: true },
      });

      if (expiredStatuses.length === 0) {
        console.log('[CRON] No expired statuses found.');
        return;
      }

      if (io) {
        for (const s of expiredStatuses) {
          io.emit('status_deleted', { statusId: s.id, userId: s.userId });
        }
      }

      await prisma.statusView.deleteMany({
        where: { statusId: { in: expiredStatuses.map((s) => s.id) } },
      });

      const result = await prisma.status.deleteMany({
        where: { id: { in: expiredStatuses.map((s) => s.id) } },
      });

      console.log(`[CRON] Status expiry cleanup complete. Deleted ${result.count} expired statuses.`);
    } catch (error) {
      console.error('[CRON] Error during status expiry cleanup:', error);
    }
  });

  // ─── Phase 24: Scheduled Message Delivery ────────────────────────────────────
  // Runs every minute. Delivers PENDING scheduled messages whose scheduledAt <= now().
  cron.schedule('* * * * *', async () => {
    try {
      const due = await prisma.scheduledMessage.findMany({
        where: {
          status: 'PENDING',
          scheduledAt: { lte: new Date() },
        },
        include: {
          sender: { select: { id: true, username: true, avatarUrl: true } },
        },
        take: 50,
      });

      if (due.length === 0) return;

      for (const sched of due) {
        try {
          const messageId = `msg_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
          const conv = await prisma.conversation.findUnique({
            where: { id: sched.conversationId },
            select: { disappearingTimer: true },
          });
          const expiresAt = conv?.disappearingTimer ? timerToExpiresAt(conv.disappearingTimer) : null;

          const dbMessage = await prisma.message.create({
            data: {
              id: messageId,
              content: sched.content,
              conversationId: sched.conversationId,
              senderId: sched.senderId,
              mediaUrl: sched.mediaUrl || null,
              mediaType: (sched.mediaType as any) || 'TEXT',
              expiresAt,
            },
          });

          await prisma.scheduledMessage.update({
            where: { id: sched.id },
            data: { status: 'SENT' },
          });

          if (io) {
            const payload = {
              message: {
                id: dbMessage.id,
                content: dbMessage.content,
                conversationId: dbMessage.conversationId,
                senderId: dbMessage.senderId,
                mediaUrl: dbMessage.mediaUrl,
                mediaType: dbMessage.mediaType,
                isForwarded: false,
                isViewOnce: false,
                createdAt: dbMessage.createdAt.toISOString(),
                expiresAt: dbMessage.expiresAt?.toISOString() ?? null,
                sender: {
                  id: sched.sender.id,
                  username: sched.sender.username,
                  avatarUrl: sched.sender.avatarUrl,
                },
                receipts: [],
                reactions: [],
              },
              conversationId: sched.conversationId,
            };
            io.to(sched.conversationId).emit('new_message', payload);
            const participants = await prisma.participant.findMany({
              where: { conversationId: sched.conversationId },
              select: { userId: true },
            });
            for (const p of participants) {
              io.to(p.userId).except(sched.conversationId).emit('new_message', payload);
            }
          }

          console.log(`[CRON] Phase 24: Delivered scheduled message ${sched.id}`);
        } catch (innerErr) {
          console.error(`[CRON] Phase 24: Failed for ${sched.id}:`, innerErr);
        }
      }
    } catch (error) {
      console.error('[CRON] Phase 24 scheduled delivery error:', error);
    }
  });

  console.log('[CRON] Cron jobs initialized (Phase 22 + 24 active).');
};
