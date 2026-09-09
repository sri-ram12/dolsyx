import type { Response } from "express";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";

// Create a new group conversation
export const createGroup = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { name, description, avatarUrl, userIds } = req.body;
    const currentUserId = req.user!.id;

    if (!name || !name.trim()) {
      res.status(400).json({ message: "Group name is required" });
      return;
    }

    const members = Array.isArray(userIds) ? userIds : [];
    
    // Ensure current user is in the member list
    const uniqueMembers = Array.from(new Set([...members, currentUserId]));

    // Create the conversation with participants
    const group = await prisma.conversation.create({
      data: {
        name: name.trim(),
        isGroup: true,
        description: description?.trim() || null,
        avatarUrl: avatarUrl || null,
        participants: {
          create: uniqueMembers.map((userId) => ({
            userId,
            role: userId === currentUserId ? "OWNER" : "MEMBER",
          })),
        },
      },
      include: {
        participants: {
          include: {
            user: {
              select: {
                id: true,
                username: true,
                avatarUrl: true,
              },
            },
          },
        },
      },
    });

    const formattedGroup = {
      id: group.id,
      isGroup: group.isGroup,
      name: group.name || "Group Chat",
      avatarUrl: group.avatarUrl,
      recipient: null,
      lastMessage: null,
      updatedAt: group.updatedAt,
      participants: group.participants,
    };

    // Emit live socket event to all group members
    const io = req.app.get("io");
    if (io) {
      uniqueMembers.forEach((memberId) => {
        io.to(memberId).emit("new_conversation", {
          chat: formattedGroup,
        });
      });
    }

    res.status(201).json(formattedGroup);
  } catch (error) {
    console.error("CreateGroup error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Update group metadata (name, description, avatar)
export const updateGroup = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params.conversationId as string;
    const { name, description, avatarUrl } = req.body;
    const currentUserId = req.user!.id;

    if (!conversationId) {
      res.status(400).json({ message: "Conversation ID is required" });
      return;
    }

    // Check if current user is a participant
    const participant = await prisma.participant.findFirst({
      where: {
        conversationId,
        userId: currentUserId,
      },
    });

    if (!participant) {
      res.status(403).json({ message: "Unauthorized to update group details" });
      return;
    }

    const updateData: any = {};
    if (name !== undefined && name !== null && name.trim() !== "") {
      updateData.name = name.trim();
    }
    if (description !== undefined && description !== null) {
      updateData.description = description.trim();
    }
    if (avatarUrl !== undefined && avatarUrl !== null && avatarUrl.trim() !== "") {
      updateData.avatarUrl = avatarUrl.trim();
    }

    const updated = await prisma.conversation.update({
      where: { id: conversationId },
      data: updateData,
      include: {
        participants: {
          select: { userId: true }
        }
      }
    });

    // Emit live group update event to all group participants
    const io = req.app.get("io");
    if (io && updated.participants) {
      updated.participants.forEach((p) => {
        io.to(p.userId).emit("group_updated", {
          conversationId,
          group: updated,
          avatarUrl: updated.avatarUrl,
          name: updated.name,
          description: updated.description,
        });
      });
    }

    res.json(updated);
  } catch (error) {
    console.error("UpdateGroup error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Add member to group
export const addMember = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params.conversationId as string;
    const { targetUserId } = req.body;
    const currentUserId = req.user!.id;

    if (!conversationId || !targetUserId) {
      res.status(400).json({ message: "Conversation ID and Target User ID are required" });
      return;
    }

    // Validate operator rights (user must be in the group)
    const operator = await prisma.participant.findFirst({
      where: { conversationId, userId: currentUserId },
    });

    if (!operator) {
      res.status(403).json({ message: "Unauthorized: You must be a member of this group to add members" });
      return;
    }

    // Check if already in conversation
    const existing = await prisma.participant.findFirst({
      where: { conversationId, userId: targetUserId },
    });

    if (existing) {
      res.status(400).json({ message: "User is already a participant" });
      return;
    }

    const participant = await prisma.participant.create({
      data: {
        conversationId,
        userId: targetUserId,
        role: "MEMBER",
      },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            avatarUrl: true,
          },
        },
      },
    });

    // Create system message and broadcast
    try {
      const [operatorUser, targetUser] = await Promise.all([
        prisma.user.findUnique({ where: { id: currentUserId }, select: { username: true } }),
        prisma.user.findUnique({ where: { id: targetUserId }, select: { username: true } }),
      ]);
      const sysMsgText = `${operatorUser?.username || "Admin"} added ${targetUser?.username || "User"} to group`;
      const sysMsg = await prisma.message.create({
        data: {
          conversationId,
          senderId: currentUserId,
          content: sysMsgText,
          mediaType: "SYSTEM",
        },
      });
      const io = req.app.get("io");
      if (io) {
        io.to(conversationId).emit("new_message", {
          conversationId,
          message: sysMsg,
        });
        io.to(conversationId).emit("group_updated", {
          conversationId,
          action: "member_added",
          operator: operatorUser?.username || "Admin",
          target: targetUser?.username || "User",
          message: sysMsgText,
        });
      }
    } catch (e) {
      console.error("Failed to create system message for addMember:", e);
    }

    res.status(201).json(participant);
  } catch (error) {
    console.error("AddMember error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Remove member from group
export const removeMember = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params.conversationId as string;
    const targetUserId = req.params.targetUserId as string;
    const currentUserId = req.user!.id;

    if (!conversationId || !targetUserId) {
      res.status(400).json({ message: "Conversation ID and Target User ID are required" });
      return;
    }

    // A user can remove themselves or any member if they are in the group
    if (targetUserId !== currentUserId) {
      const operator = await prisma.participant.findFirst({
        where: { conversationId, userId: currentUserId },
      });

      if (!operator) {
        res.status(403).json({ message: "Unauthorized to remove members" });
        return;
      }
    }

    // Fetch user details for system message before deleting participant
    const [operatorUser, targetUser] = await Promise.all([
      prisma.user.findUnique({ where: { id: currentUserId }, select: { username: true } }),
      prisma.user.findUnique({ where: { id: targetUserId }, select: { username: true } }),
    ]);

    // Remove participant
    await prisma.participant.deleteMany({
      where: {
        conversationId,
        OR: [
          { userId: targetUserId },
          { id: targetUserId },
        ],
      },
    });

    // Create system message and broadcast
    try {
      const isSelfLeave = targetUserId === currentUserId;
      const sysMsgText = isSelfLeave
        ? `${targetUser?.username || "User"} left group`
        : `${operatorUser?.username || "Admin"} removed ${targetUser?.username || "User"} from group`;

      const sysMsg = await prisma.message.create({
        data: {
          conversationId,
          senderId: currentUserId,
          content: sysMsgText,
          mediaType: "SYSTEM",
        },
      });

      const io = req.app.get("io");
      if (io) {
        io.to(conversationId).emit("new_message", {
          conversationId,
          message: sysMsg,
        });
        io.to(conversationId).emit("group_updated", {
          conversationId,
          action: isSelfLeave ? "member_left" : "member_removed",
          operator: operatorUser?.username || "Admin",
          target: targetUser?.username || "User",
          message: sysMsgText,
        });
      }
    } catch (e) {
      console.error("Failed to create system message for removeMember:", e);
    }

    res.json({ message: "Member removed successfully" });
  } catch (error) {
    console.error("RemoveMember error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Change member role
export const changeMemberRole = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params.conversationId as string;
    const { targetUserId, role } = req.body;
    const currentUserId = req.user!.id;

    if (!conversationId || !targetUserId || !role) {
      res.status(400).json({ message: "Conversation ID, Target User ID, and Role are required" });
      return;
    }

    if (!["ADMIN", "MODERATOR", "MEMBER"].includes(role)) {
      res.status(400).json({ message: "Invalid role value" });
      return;
    }

    // Owner/Admin check
    const operator = await prisma.participant.findFirst({
      where: { conversationId, userId: currentUserId },
    });

    if (!operator || (operator.role !== "OWNER" && operator.role !== "ADMIN")) {
      res.status(403).json({ message: "Unauthorized to change roles" });
      return;
    }

    const updated = await prisma.participant.update({
      where: {
        userId_conversationId: {
          userId: targetUserId,
          conversationId,
        },
      },
      data: { role },
    });

    res.json(updated);
  } catch (error) {
    console.error("ChangeMemberRole error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Disband group (Permanently delete group conversation for all members)
export const disbandGroup = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params.conversationId as string;
    const currentUserId = req.user!.id;

    if (!conversationId) {
      res.status(400).json({ message: "Conversation ID is required" });
      return;
    }

    // Check operator role (must be OWNER or ADMIN)
    const operator = await prisma.participant.findFirst({
      where: { conversationId, userId: currentUserId },
    });

    if (!operator || (operator.role !== "OWNER" && operator.role !== "ADMIN")) {
      res.status(403).json({ message: "Unauthorized: Only group admins can disband the group" });
      return;
    }

    // Fetch all participants before deleting to send socket notifications
    const participants = await prisma.participant.findMany({
      where: { conversationId },
      select: { userId: true },
    });
    const participantUserIds = participants.map((p) => p.userId);

    // Hard delete conversation and related data
    await prisma.conversation.delete({
      where: { id: conversationId },
    });

    // Broadcast socket event to all members
    const io = req.app.get("io");
    if (io) {
      participantUserIds.forEach((memberId) => {
        io.to(memberId).emit("group_disbanded", { conversationId });
        io.to(memberId).emit("conversation_deleted", { conversationId });
      });
      io.to(conversationId).emit("group_disbanded", { conversationId });
    }

    res.json({ message: "Group disbanded successfully" });
  } catch (error) {
    console.error("DisbandGroup error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Get past participants / member history (left, removed, added) for the past 60 days
export const getPastParticipants = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params.conversationId as string;
    if (!conversationId) {
      res.status(400).json({ message: "Conversation ID is required" });
      return;
    }

    const sixtyDaysAgo = new Date();
    sixtyDaysAgo.setDate(sixtyDaysAgo.getDate() - 60);

    // Fetch system messages for group events
    const systemMessages = await prisma.message.findMany({
      where: {
        conversationId,
        createdAt: {
          gte: sixtyDaysAgo,
        },
        OR: [
          { mediaType: "SYSTEM" },
          { senderId: "system" },
          { content: { contains: "left" } },
          { content: { contains: "removed" } },
          { content: { contains: "added" } },
        ],
      },
      orderBy: {
        createdAt: "desc",
      },
    });

    const history = systemMessages.map((msg) => {
      const content = msg.content.replace(/^SYSTEM:\s*/, "").trim();
      const lower = content.toLowerCase();

      let action = "changed";
      let name = "Group Member";

      if (lower.includes(" left")) {
        action = "left";
        name = content.split(/\s+left/i)[0]?.trim() || "Group Member";
      } else if (lower.includes(" removed ")) {
        action = "removed";
        const parts = content.split(/\s+removed\s+/i);
        const targetPart = parts[1] || parts[0] || "";
        name = targetPart.replace(/\s+from group$/i, "").trim();
      } else if (lower.includes(" added ")) {
        action = "joined";
        const parts = content.split(/\s+added\s+/i);
        const targetPart = parts[1] || parts[0] || "";
        name = targetPart.replace(/\s+to group$/i, "").trim();
      }

      return {
        id: msg.id,
        name: name || "Participant",
        action,
        actionText: content,
        createdAt: msg.createdAt,
      };
    });

    res.json(history);
  } catch (error) {
    console.error("GetPastParticipants error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

