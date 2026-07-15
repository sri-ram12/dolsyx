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

    // Check if current user is an admin or owner
    const participant = await prisma.participant.findFirst({
      where: {
        conversationId,
        userId: currentUserId,
      },
    });

    if (!participant || (participant.role !== "OWNER" && participant.role !== "ADMIN")) {
      res.status(403).json({ message: "Unauthorized to update group details" });
      return;
    }

    const updated = await prisma.conversation.update({
      where: { id: conversationId },
      data: {
        name: name?.trim() || undefined,
        description: description !== undefined ? description.trim() : undefined,
        avatarUrl: avatarUrl || undefined,
      },
    });

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

    // Validate operator rights
    const operator = await prisma.participant.findFirst({
      where: { conversationId, userId: currentUserId },
    });

    if (!operator || (operator.role !== "OWNER" && operator.role !== "ADMIN")) {
      res.status(403).json({ message: "Unauthorized to add members" });
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

    // A user can remove themselves (leave group)
    if (targetUserId !== currentUserId) {
      // Otherwise, check operator rights
      const operator = await prisma.participant.findFirst({
        where: { conversationId, userId: currentUserId },
      });

      if (!operator || (operator.role !== "OWNER" && operator.role !== "ADMIN")) {
        res.status(403).json({ message: "Unauthorized to remove members" });
        return;
      }
    }

    // Remove participant
    await prisma.participant.delete({
      where: {
        userId_conversationId: {
          userId: targetUserId,
          conversationId,
        },
      },
    });

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
