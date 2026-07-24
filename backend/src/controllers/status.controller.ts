import type { Response } from "express";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";

// Create a new status (24h story)
export const createStatus = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { mediaUrl, mediaType, caption, bgColor } = req.body;

    if (!mediaUrl && !caption) {
      res.status(400).json({ message: "Either media or caption is required" });
      return;
    }

    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

    const status = await prisma.status.create({
      data: {
        userId,
        mediaUrl: mediaUrl || null,
        mediaType: mediaType || "TEXT",
        caption: caption || null,
        bgColor: bgColor || null,
        expiresAt,
      },
      include: {
        user: {
          select: { id: true, username: true, avatarUrl: true },
        },
        views: true,
      },
    });

    // Emit socket event so contacts see the new status in real-time
    const io = (req as any).app.get("io");
    if (io) {
      // Find all users this person has chatted with
      const conversations = await prisma.participant.findMany({
        where: { userId },
        select: { conversationId: true },
      });

      const conversationIds = conversations.map((p) => p.conversationId);
      const contacts = await prisma.participant.findMany({
        where: {
          conversationId: { in: conversationIds },
          userId: { not: userId },
        },
        select: { userId: true },
        distinct: ["userId"],
      });

      // Apply privacy settings: My Contacts, My Contacts Except..., Only Share With...
      const me = await prisma.user.findUnique({ where: { id: userId }, select: { statusPrivacyType: true, statusPrivacyList: true } });
      const privacyType = me?.statusPrivacyType || "MY_CONTACTS";
      const privacyList = me?.statusPrivacyList || [];

      contacts.forEach((contact) => {
        let canSee = true;
        if (privacyType === "EXCEPT" && privacyList.includes(contact.userId)) {
          canSee = false;
        } else if (privacyType === "ONLY_SHARE" && !privacyList.includes(contact.userId)) {
          canSee = false;
        }
        if (canSee) {
          io.to(contact.userId).emit("new_status", { status });
        }
      });
    }

    res.status(201).json(status);
  } catch (error) {
    console.error("CreateStatus error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Get all active statuses from contacts (people user has chatted with)
export const getStatuses = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const now = new Date();

    // Find all contact IDs (users this person has had conversations with)
    const conversations = await prisma.participant.findMany({
      where: { userId },
      select: { conversationId: true },
    });

    const conversationIds = conversations.map((p) => p.conversationId);
    const contacts = await prisma.participant.findMany({
      where: {
        conversationId: { in: conversationIds },
        userId: { not: userId },
      },
      select: { userId: true },
      distinct: ["userId"],
    });

    const contactIds = contacts.map((c) => c.userId);
    // Include current user so they can see their own status
    const userIds = [userId, ...contactIds];

    const statuses = await prisma.status.findMany({
      where: {
        userId: { in: userIds },
        expiresAt: { gt: now },
      },
      include: {
        user: {
          select: { id: true, username: true, avatarUrl: true, statusPrivacyType: true, statusPrivacyList: true, readReceipts: true },
        },
        views: {
          select: {
            viewerId: true,
            viewedAt: true,
            viewer: {
              select: { id: true, username: true, avatarUrl: true, readReceipts: true }
            }
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });

    const mutes = await prisma.statusMute.findMany({
      where: { muterId: userId },
      select: { mutedId: true }
    });
    const mutedSet = new Set(mutes.map(m => m.mutedId));

    // Group by user
    const grouped: Record<string, any> = {};
    for (const s of statuses) {
      // Respect privacy for others' statuses
      if (s.userId !== userId) {
        const pType = s.user.statusPrivacyType;
        const pList = s.user.statusPrivacyList;
        if (pType === "EXCEPT" && pList.includes(userId)) continue;
        if (pType === "ONLY_SHARE" && !pList.includes(userId)) continue;
      }

      if (!grouped[s.userId]) {
        grouped[s.userId] = {
          user: { id: s.user.id, username: s.user.username, avatarUrl: s.user.avatarUrl },
          statuses: [],
          hasUnread: false,
          isMuted: mutedSet.has(s.userId)
        };
      }
      
      const isViewed = s.views.some((v) => v.viewerId === userId);
      
      // Filter out seenBy viewers if they disabled readReceipts (except self)
      const visibleViews = s.views.filter(v => v.viewer.readReceipts || v.viewerId === s.userId);
      
      grouped[s.userId].statuses.push({ ...s, isViewed, views: visibleViews });
      if (!isViewed && s.userId !== userId) {
        grouped[s.userId].hasUnread = true;
      }
    }

    res.json(Object.values(grouped));
  } catch (error) {
    console.error("GetStatuses error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Mark a status as viewed
export const viewStatus = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const statusId = req.params.statusId as string;
    const viewerId = req.user!.id;

    const viewer = await prisma.user.findUnique({ where: { id: viewerId } });
    if (!viewer?.readReceipts) {
      // If viewer disabled read receipts, we don't save their view in DB to protect privacy!
      res.json({ message: "Viewed (anonymous)" });
      return;
    }

    await prisma.statusView.upsert({
      where: { statusId_viewerId: { statusId, viewerId } },
      update: { viewedAt: new Date() },
      create: { statusId, viewerId },
    });

    // Optionally emit event to uploader
    const status = await prisma.status.findUnique({ where: { id: statusId } });
    if (status && status.userId !== viewerId) {
      const io = (req as any).app.get("io");
      io?.to(status.userId).emit("status_viewed", { statusId, viewerId });
    }

    res.json({ message: "Viewed" });
  } catch (error) {
    console.error("ViewStatus error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Delete own status
export const deleteStatus = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const statusId = req.params.statusId as string;
    const userId = req.user!.id;

    const existing = await prisma.status.findUnique({ where: { id: statusId } });
    if (!existing || existing.userId !== userId) {
      res.status(403).json({ message: "Not authorized" });
      return;
    }

    await prisma.status.delete({ where: { id: statusId } });
    
    // Broadcast delete event
    const io = (req as any).app.get("io");
    io?.emit("status_deleted", { statusId, userId });
    
    res.json({ message: "Status deleted" });
  } catch (error) {
    console.error("DeleteStatus error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const muteStatus = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { contactId } = req.body;
    const userId = req.user!.id;
    
    await prisma.statusMute.upsert({
      where: { muterId_mutedId: { muterId: userId, mutedId: contactId } },
      create: { muterId: userId, mutedId: contactId },
      update: {}
    });
    res.json({ message: "Muted" });
  } catch (error) {
    console.error("muteStatus error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const unmuteStatus = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { contactId } = req.body;
    const userId = req.user!.id;
    
    await prisma.statusMute.deleteMany({
      where: { muterId: userId, mutedId: contactId }
    });
    res.json({ message: "Unmuted" });
  } catch (error) {
    console.error("unmuteStatus error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};
