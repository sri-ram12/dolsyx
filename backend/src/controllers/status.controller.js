import { prisma } from "../config/db.js";
// Create a new status (24h story)
export const createStatus = async (req, res) => {
    try {
        const userId = req.user.id;
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
        const io = req.app.get("io");
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
            contacts.forEach((contact) => {
                io.to(contact.userId).emit("new_status", { status });
            });
        }
        res.status(201).json(status);
    }
    catch (error) {
        console.error("CreateStatus error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
// Get all active statuses from contacts (people user has chatted with)
export const getStatuses = async (req, res) => {
    try {
        const userId = req.user.id;
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
                    select: { id: true, username: true, avatarUrl: true },
                },
                views: {
                    select: { viewerId: true, viewedAt: true },
                },
            },
            orderBy: { createdAt: "desc" },
        });
        // Group by user
        const grouped = {};
        for (const s of statuses) {
            if (!grouped[s.userId]) {
                grouped[s.userId] = {
                    user: s.user,
                    statuses: [],
                    hasUnread: false,
                };
            }
            const isViewed = s.views.some((v) => v.viewerId === userId);
            grouped[s.userId].statuses.push({ ...s, isViewed });
            if (!isViewed && s.userId !== userId) {
                grouped[s.userId].hasUnread = true;
            }
        }
        res.json(Object.values(grouped));
    }
    catch (error) {
        console.error("GetStatuses error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
// Mark a status as viewed
export const viewStatus = async (req, res) => {
    try {
        const statusId = req.params.statusId;
        const viewerId = req.user.id;
        await prisma.statusView.upsert({
            where: { statusId_viewerId: { statusId, viewerId } },
            update: { viewedAt: new Date() },
            create: { statusId, viewerId },
        });
        res.json({ message: "Viewed" });
    }
    catch (error) {
        console.error("ViewStatus error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
// Delete own status
export const deleteStatus = async (req, res) => {
    try {
        const statusId = req.params.statusId;
        const userId = req.user.id;
        const existing = await prisma.status.findUnique({ where: { id: statusId } });
        if (!existing || existing.userId !== userId) {
            res.status(403).json({ message: "Not authorized" });
            return;
        }
        await prisma.status.delete({ where: { id: statusId } });
        res.json({ message: "Status deleted" });
    }
    catch (error) {
        console.error("DeleteStatus error:", error);
        res.status(500).json({ message: "Internal server error" });
    }
};
//# sourceMappingURL=status.controller.js.map