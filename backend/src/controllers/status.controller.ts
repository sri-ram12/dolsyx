import type { Response } from "express";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";
import { canViewStatus } from "../utils/privacy.engine.js";

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

    const creator = await prisma.user.findUnique({
      where: { id: userId },
      select: { statusPrivacyType: true, statusPrivacyList: true },
    });
    const privacyType = creator?.statusPrivacyType || "MY_CONTACTS";
    const privacyList = creator?.statusPrivacyList || [];

    const status = await prisma.status.create({
      data: {
        userId,
        mediaUrl: mediaUrl || null,
        mediaType: mediaType || "TEXT",
        caption: caption || null,
        bgColor: bgColor || null,
        privacyType,
        privacyList: typeof privacyList === "string" ? privacyList : JSON.stringify(privacyList),
        expiresAt,
      },
      include: {
        user: {
          select: { id: true, username: true, avatarUrl: true },
        },
        views: true,
      },
    });

    // Emit socket event so eligible contacts see the new status in real-time
    const io = (req as any).app.get("io");
    if (io) {
      const savedContacts = await prisma.contact.findMany({
        where: { userId },
        select: { contactId: true },
      });
      const conversations = await prisma.participant.findMany({
        where: { userId },
        select: { conversationId: true },
      });
      const conversationIds = conversations.map((p) => p.conversationId);
      const chatParticipants = await prisma.participant.findMany({
        where: {
          conversationId: { in: conversationIds },
          userId: { not: userId },
        },
        select: { userId: true },
      });

      const candidateIds = Array.from(
        new Set([...savedContacts.map((c) => c.contactId), ...chatParticipants.map((c) => c.userId)])
      );

      for (const candidateId of candidateIds) {
        const canSee = await canViewStatus(candidateId, userId, { privacyType, privacyList });
        if (canSee) {
          io.to(candidateId).emit("new_status", { status });
        }
      }
    }

    res.status(201).json(status);
  } catch (error) {
    console.error("CreateStatus error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Get all active statuses from contacts that user is authorized to view
export const getStatuses = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const now = new Date();

    const savedContacts = await prisma.contact.findMany({
      where: { userId },
      select: { contactId: true },
    });
    const conversations = await prisma.participant.findMany({
      where: { userId },
      select: { conversationId: true },
    });
    const conversationIds = conversations.map((p) => p.conversationId);
    const chatParticipants = await prisma.participant.findMany({
      where: {
        conversationId: { in: conversationIds },
        userId: { not: userId },
      },
      select: { userId: true },
    });

    const contactIds = Array.from(
      new Set([...savedContacts.map((c) => c.contactId), ...chatParticipants.map((c) => c.userId)])
    );
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
              select: { id: true, username: true, avatarUrl: true, readReceipts: true },
            },
          },
        },
      },
      orderBy: { createdAt: "asc" },
    });

    const mutes = await prisma.statusMute.findMany({
      where: { muterId: userId },
      select: { mutedId: true },
    });
    const mutedSet = new Set(mutes.map((m) => m.mutedId));

    const privacyCache = new Map<string, boolean>();
    const grouped: Record<string, any> = {};
    for (const s of statuses) {
      if (s.userId !== userId) {
        const cacheKey = `${userId}:${s.userId}:${s.privacyType}:${s.privacyList}`;
        let canSee = privacyCache.get(cacheKey);
        if (canSee === undefined) {
          canSee = await canViewStatus(userId, s.userId, { privacyType: s.privacyType, privacyList: s.privacyList });
          privacyCache.set(cacheKey, canSee);
        }
        if (!canSee) continue;
      }

      if (!grouped[s.userId]) {
        grouped[s.userId] = {
          user: { id: s.user.id, username: s.user.username, avatarUrl: s.user.avatarUrl },
          statuses: [],
          hasUnread: false,
          isMuted: mutedSet.has(s.userId),
        };
      }

      const isViewed = s.views.some((v) => v.viewerId === userId);
      const visibleViews = s.views.filter((v) => v.viewer.readReceipts || v.viewerId === s.userId);

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

// Fetch single status by ID with privacy authorization check
export const getStatusById = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const statusId = req.params.statusId as string;
    const userId = req.user!.id;

    const status = await prisma.status.findUnique({
      where: { id: statusId },
      include: {
        user: { select: { id: true, username: true, email: true, avatarUrl: true } },
      },
    });

    if (!status) {
      res.status(404).json({ message: "Status not found" });
      return;
    }

    if (status.expiresAt < new Date()) {
      res.status(410).json({ message: "Status has expired" });
      return;
    }

    if (status.userId !== userId) {
      const canSee = await canViewStatus(userId, status.userId, { privacyType: status.privacyType, privacyList: status.privacyList });
      if (!canSee) {
        res.status(403).json({ message: "Forbidden: Not authorized to view status" });
        return;
      }
    }

    res.json(status);
  } catch (error) {
    console.error("getStatusById error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Mark a status as viewed with privacy authorization check
export const viewStatus = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const statusId = req.params.statusId as string;
    const viewerId = req.user!.id;

    const status = await prisma.status.findUnique({ where: { id: statusId } });
    if (!status) {
      res.status(404).json({ message: "Status not found" });
      return;
    }

    if (status.userId !== viewerId) {
      const allowed = await canViewStatus(viewerId, status.userId, { privacyType: status.privacyType, privacyList: status.privacyList });
      if (!allowed) {
        res.status(403).json({ message: "Forbidden: Not authorized to view status" });
        return;
      }
    }

    const viewer = await prisma.user.findUnique({ where: { id: viewerId } });
    if (!viewer?.readReceipts) {
      res.json({ message: "Viewed (anonymous)" });
      return;
    }

    await prisma.statusView.upsert({
      where: { statusId_viewerId: { statusId, viewerId } },
      update: { viewedAt: new Date() },
      create: { statusId, viewerId },
    });

    if (status.userId !== viewerId) {
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
