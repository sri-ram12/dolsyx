import type { Response } from "express";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";

const BROADCAST_MARKER = "__DOLSYX_BROADCAST__";

/**
 * Phase 18 – Broadcast Lists (WhatsApp-style)
 *
 * Broadcast lists are stored as group conversations with:
 *   description = "__DOLSYX_BROADCAST__"
 *   isGroup     = true
 *
 * Only the OWNER participant can send messages.
 * Replies are delivered as separate 1-to-1 conversations (each recipient replies privately).
 */

// ── Create Broadcast List ─────────────────────────────────────────────────────
export const createBroadcastList = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { name, recipientIds } = req.body as { name: string; recipientIds: string[] };

    if (!name || !recipientIds || recipientIds.length === 0) {
      res.status(400).json({ message: "Name and at least one recipient are required" });
      return;
    }

    // Deduplicate and remove self
    const uniqueRecipients = [...new Set(recipientIds.filter((id) => id !== userId))];

    const broadcastConversation = await prisma.conversation.create({
      data: {
        name,
        isGroup: true,
        description: BROADCAST_MARKER,
        participants: {
          create: [
            { userId, role: "OWNER" },
            ...uniqueRecipients.map((rid) => ({ userId: rid, role: "MEMBER" })),
          ],
        },
      },
      include: {
        participants: {
          include: { user: { select: { id: true, username: true, avatarUrl: true } } },
        },
      },
    });

    res.status(201).json({
      id: broadcastConversation.id,
      name: broadcastConversation.name,
      isBroadcast: true,
      recipientCount: uniqueRecipients.length,
      participants: broadcastConversation.participants,
      createdAt: broadcastConversation.createdAt,
    });
  } catch (error) {
    console.error("[Broadcast] createBroadcastList error:", error);
    res.status(500).json({ message: "Failed to create broadcast list" });
  }
};

// ── List Broadcast Lists ──────────────────────────────────────────────────────
export const getBroadcastLists = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;

    const lists = await prisma.conversation.findMany({
      where: {
        isGroup: true,
        description: BROADCAST_MARKER,
        participants: { some: { userId, role: "OWNER" } },
      },
      include: {
        participants: {
          include: { user: { select: { id: true, username: true, avatarUrl: true } } },
        },
        messages: {
          orderBy: { createdAt: "desc" },
          take: 1,
          include: { sender: { select: { id: true, username: true } } },
        },
      },
      orderBy: { updatedAt: "desc" },
    });

    const formatted = lists.map((l) => ({
      id: l.id,
      name: l.name,
      isBroadcast: true,
      recipientCount: l.participants.filter((p) => p.role !== "OWNER").length,
      lastMessage: l.messages[0] ?? null,
      updatedAt: l.updatedAt,
    }));

    res.json(formatted);
  } catch (error) {
    console.error("[Broadcast] getBroadcastLists error:", error);
    res.status(500).json({ message: "Failed to fetch broadcast lists" });
  }
};

// ── Send Broadcast Message ────────────────────────────────────────────────────
// Delivers a copy of the message to each recipient's private DM conversation.
// Recipients only see a 1-to-1 chat, not the broadcast group.
export const sendBroadcastMessage = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { broadcastId } = req.params as { broadcastId: string };
    const { content, mediaUrl, mediaType } = req.body;

    if (!content && !mediaUrl) {
      res.status(400).json({ message: "Content or media is required" });
      return;
    }

    // Verify user is OWNER of this broadcast list
    const broadcastConv = await prisma.conversation.findFirst({
      where: {
        id: broadcastId,
        isGroup: true,
        description: BROADCAST_MARKER,
        participants: { some: { userId, role: "OWNER" } },
      },
      include: {
        participants: {
          where: { role: "MEMBER" },
          select: { userId: true },
        },
      },
    });

    if (!broadcastConv) {
      res.status(403).json({ message: "Broadcast list not found or access denied" });
      return;
    }

    const io = (req as any).app.get("io");
    const deliveredTo: string[] = [];

    // For each recipient, find or create a private DM then send the message
    for (const { userId: recipientId } of broadcastConv.participants) {
      try {
        // Find existing DM conversation
        let directConv = await prisma.conversation.findFirst({
          where: {
            isGroup: false,
            participants: { every: { userId: { in: [userId, recipientId] } } },
          },
          include: { participants: true },
        });

        // Create DM if it doesn't exist
        if (!directConv || directConv.participants.length !== 2) {
          directConv = await prisma.conversation.create({
            data: {
              isGroup: false,
              participants: {
                create: [{ userId }, { userId: recipientId }],
              },
            },
            include: { participants: true },
          });
        }

        const message = await prisma.message.create({
          data: {
            conversationId: directConv.id,
            senderId: userId,
            content: content ?? null,
            mediaUrl: mediaUrl ?? null,
            mediaType: mediaType ?? null,
          },
          include: {
            sender: { select: { id: true, username: true, avatarUrl: true } },
          },
        });

        // Update conversation timestamp
        await prisma.conversation.update({
          where: { id: directConv.id },
          data: { updatedAt: new Date() },
        });

        // Emit via socket to recipient
        if (io) {
          io.to(recipientId).emit("new_message", {
            conversationId: directConv.id,
            message,
          });
        }

        deliveredTo.push(recipientId);
      } catch (err) {
        console.warn(`[Broadcast] Failed to deliver to ${recipientId}:`, err);
      }
    }

    res.json({
      message: "Broadcast delivered",
      deliveredTo: deliveredTo.length,
      totalRecipients: broadcastConv.participants.length,
    });
  } catch (error) {
    console.error("[Broadcast] sendBroadcastMessage error:", error);
    res.status(500).json({ message: "Failed to send broadcast" });
  }
};

// ── Add/Remove Recipients ─────────────────────────────────────────────────────
export const updateBroadcastRecipients = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { broadcastId } = req.params as { broadcastId: string };
    const { addIds, removeIds } = req.body as { addIds?: string[]; removeIds?: string[] };

    const broadcastConv = await prisma.conversation.findFirst({
      where: {
        id: broadcastId,
        isGroup: true,
        description: BROADCAST_MARKER,
        participants: { some: { userId, role: "OWNER" } },
      },
    });

    if (!broadcastConv) {
      res.status(403).json({ message: "Broadcast list not found or access denied" });
      return;
    }

    if (addIds && addIds.length > 0) {
      const toAdd = [...new Set(addIds.filter((id) => id !== userId))];
      for (const rid of toAdd) {
        await prisma.participant.upsert({
          where: { userId_conversationId: { userId: rid, conversationId: broadcastId } },
          create: { userId: rid, conversationId: broadcastId, role: "MEMBER" },
          update: {},
        });
      }
    }

    if (removeIds && removeIds.length > 0) {
      await prisma.participant.deleteMany({
        where: {
          conversationId: broadcastId,
          userId: { in: removeIds },
          role: "MEMBER",
        },
      });
    }

    res.json({ message: "Broadcast recipients updated" });
  } catch (error) {
    console.error("[Broadcast] updateBroadcastRecipients error:", error);
    res.status(500).json({ message: "Failed to update broadcast recipients" });
  }
};

// ── Delete Broadcast List ─────────────────────────────────────────────────────
export const deleteBroadcastList = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { broadcastId } = req.params as { broadcastId: string };

    const broadcastConv = await prisma.conversation.findFirst({
      where: {
        id: broadcastId,
        isGroup: true,
        description: BROADCAST_MARKER,
        participants: { some: { userId, role: "OWNER" } },
      },
    });

    if (!broadcastConv) {
      res.status(403).json({ message: "Broadcast list not found or access denied" });
      return;
    }

    // Delete all participants first, then conversation
    await prisma.participant.deleteMany({ where: { conversationId: broadcastId } });
    await prisma.conversation.delete({ where: { id: broadcastId } });

    res.json({ message: "Broadcast list deleted" });
  } catch (error) {
    console.error("[Broadcast] deleteBroadcastList error:", error);
    res.status(500).json({ message: "Failed to delete broadcast list" });
  }
};
