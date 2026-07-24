import type { Response } from "express";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";
import { encryptionService } from "../services/encryption.service.js";

export const getChats = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;

    // Find all conversations where the current user is a participant
    const conversations = await prisma.conversation.findMany({
      where: {
        participants: {
          some: {
            userId,
          },
        },
      },
      include: {
        participants: {
          include: {
            user: {
              select: {
                id: true,
                username: true,
                email: true,
                phoneNumber: true,
                avatarUrl: true,
                lastSeen: true,
                isOnline: true,
                bio: true,
              },
            },
          },
        },
        messages: {
          where: {
            deletedForUsers: {
              none: {
                userId,
              },
            },
          },
          orderBy: {
            createdAt: "desc",
          },
          take: 1,
          include: {
            sender: {
              select: {
                id: true,
                username: true,
                avatarUrl: true,
              },
            },
          },
        },
      },
      orderBy: {
        updatedAt: "desc",
      },
    });

    // Format chat list for frontend convenience
    const formattedChats = await Promise.all(
      conversations.map(async (chat) => {
        // Find the recipient (the other participant in a 1-on-1 chat)
        const otherParticipant = chat.participants.find((p) => p.userId !== userId);
        const recipient = otherParticipant ? otherParticipant.user : null;
        // Decrypt lastMessage content so the sidebar preview shows readable text
        const rawLastMessage = chat.messages[0] || null;
        const lastMessage = rawLastMessage
          ? {
              ...rawLastMessage,
              content: rawLastMessage.content
                ? (() => {
                    try {
                      return encryptionService.decrypt(rawLastMessage.content);
                    } catch {
                      return "";
                    }
                  })()
                : "",
            }
          : null;

        // Count unread messages (messages sent by others that don't have a READ receipt for this user)
        const unreadCount = await prisma.message.count({
          where: {
            conversationId: chat.id,
            senderId: { not: userId },
            deletedForUsers: {
              none: {
                userId,
              },
            },
            receipts: {
              none: {
                userId,
                status: "READ",
              },
            },
          },
        });

        return {
          id: chat.id,
          isGroup: chat.isGroup,
          name: chat.isGroup
            ? (chat.name || "Group Chat")
            : (recipient?.username || chat.name || "Chat"),
          avatarUrl: chat.isGroup
            ? (chat.avatarUrl || null)
            : (recipient?.avatarUrl || null),
          recipient,
          lastMessage,
          updatedAt: chat.updatedAt,
          participants: chat.participants,
          unreadCount,
        };
      })
    );

    res.json(formattedChats);
  } catch (error) {
    console.error("GetChats error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const getMessages = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params["conversationId"];
    const userId = req.user!.id;

    if (!conversationId || typeof conversationId !== "string") {
      res.status(400).json({ message: "Conversation ID is required" });
      return;
    }

    // Verify participant
    const isParticipant = await prisma.participant.findFirst({
      where: {
        conversationId,
        userId,
      },
    });

    if (!isParticipant) {
      res.status(403).json({ message: "You are not a participant in this conversation" });
      return;
    }

    // Fetch messages
    const messages = await prisma.message.findMany({
      where: {
        conversationId,
        deletedForUsers: {
          none: {
            userId,
          },
        },
      },
      orderBy: {
        createdAt: "asc",
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true,
            avatarUrl: true,
            bio: true,
          },
        },
        receipts: true,
      },
    });

    // Decrypt messages
    const decryptedMessages = messages.map((msg) => ({
      ...msg,
      content: encryptionService.decrypt(msg.content),
    }));

    res.json(decryptedMessages);
  } catch (error) {
    console.error("GetMessages error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const createOrGetDirectChat = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { targetUserId } = req.body;
    const currentUserId = req.user!.id;

    if (!targetUserId) {
      res.status(400).json({ message: "Target User ID is required" });
      return;
    }

    if (targetUserId === currentUserId) {
      res.status(400).json({ message: "You cannot chat with yourself" });
      return;
    }

    // Check if user exists
    const targetUser = await prisma.user.findUnique({
      where: { id: targetUserId },
      select: { id: true, username: true, email: true, phoneNumber: true, avatarUrl: true, lastSeen: true, isOnline: true },
    });

    if (!targetUser) {
      res.status(404).json({ message: "Target user not found" });
      return;
    }

    // Find existing conversation between these 2 users
    const existingChat = await prisma.conversation.findFirst({
      where: {
        isGroup: false,
        AND: [
          { participants: { some: { userId: currentUserId } } },
          { participants: { some: { userId: targetUserId } } },
        ],
      },
      include: {
        participants: {
          include: {
            user: {
              select: {
                id: true,
                username: true,
                email: true,
                phoneNumber: true,
                avatarUrl: true,
                lastSeen: true,
                isOnline: true,
                bio: true,
              },
            },
          },
        },
      },
    });

    if (existingChat) {
      const recipient = targetUser;
      res.json({
        id: existingChat.id,
        isGroup: false,
        name: recipient.username,
        avatarUrl: recipient.avatarUrl,
        recipient,
        updatedAt: existingChat.updatedAt,
      });
      return;
    }

    // Create new direct conversation
    const newChat = await prisma.conversation.create({
      data: {
        isGroup: false,
        participants: {
          create: [
            { userId: currentUserId },
            { userId: targetUserId },
          ],
        },
      },
      include: {
        participants: {
          include: {
            user: {
              select: {
                id: true,
                username: true,
                email: true,
                phoneNumber: true,
                avatarUrl: true,
                lastSeen: true,
                isOnline: true,
                bio: true,
              },
            },
          },
        },
      },
    });

    res.status(201).json({
      id: newChat.id,
      isGroup: false,
      name: targetUser.username,
      avatarUrl: targetUser.avatarUrl,
      recipient: targetUser,
      updatedAt: newChat.updatedAt,
    });
  } catch (error) {
    console.error("CreateChat error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const searchUsers = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { query } = req.query;
    const currentUserId = req.user!.id;

    if (!query || typeof query !== "string") {
      res.status(400).json({ message: "Search query is required" });
      return;
    }

    const users = await prisma.user.findMany({
      where: {
        username: {
          contains: query,
        },
        id: {
          not: currentUserId,
        },
      },
      select: {
        id: true,
        username: true,
        email: true,
        phoneNumber: true,
        avatarUrl: true,
        lastSeen: true,
      },
      take: 10,
    });

    res.json(users);
  } catch (error) {
    console.error("SearchUsers error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const deleteConversation = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params["conversationId"] as string;
    const userId = req.user!.id;

    if (!conversationId) {
      res.status(400).json({ message: "Conversation ID is required" });
      return;
    }

    // Verify participant
    const isParticipant = await prisma.participant.findFirst({
      where: {
        conversationId,
        userId,
      },
    });

    if (!isParticipant) {
      res.status(403).json({ message: "You are not a participant in this conversation" });
      return;
    }

    // Delete the participant (remove this user from the conversation)
    await prisma.participant.delete({
      where: {
        userId_conversationId: {
          userId,
          conversationId,
        },
      },
    });

    // Check if there are any remaining participants
    const remainingParticipants = await prisma.participant.findMany({
      where: { conversationId },
      select: { userId: true },
    });

    if (remainingParticipants.length === 0) {
      // If no one is left, we can safely hard delete the conversation
      await prisma.conversation.delete({
        where: { id: conversationId },
      });
    }

    // Emit socket event ONLY to the participant who deleted it so their sidebar updates
    const io = (req as any).app.get("io");
    if (io) {
      io.to(userId).emit("conversation_deleted", { conversationId });
    }

    res.json({ message: "Conversation deleted successfully" });
  } catch (error) {
    console.error("DeleteConversation error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const clearChatMessages = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params["conversationId"] as string;
    const userId = req.user!.id;

    if (!conversationId) {
      res.status(400).json({ message: "Conversation ID is required" });
      return;
    }

    // Verify participant
    const isParticipant = await prisma.participant.findFirst({
      where: {
        conversationId,
        userId,
      },
    });

    if (!isParticipant) {
      res.status(403).json({ message: "You are not a participant in this conversation" });
      return;
    }

    // Delete all messages in this conversation
    await prisma.message.deleteMany({
      where: { conversationId },
    });

    // Touch the conversation timestamp
    await prisma.conversation.update({
      where: { id: conversationId },
      data: { updatedAt: new Date() },
    });

    // Emit socket event to all participants so their message list updates in real-time
    const participants = await prisma.participant.findMany({
      where: { conversationId },
      select: { userId: true },
    });

    const io = (req as any).app.get("io");
    if (io) {
      participants.forEach((participant) => {
        io.to(participant.userId).emit("chat_cleared", { conversationId });
      });
    }

    res.json({ message: "Chat messages cleared successfully" });
  } catch (error) {
    console.error("ClearChatMessages error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const getCallHistory = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;

    // Find all messages across all conversations the user is part of that are CALL_LOG
    const callLogs = await prisma.message.findMany({
      where: {
        mediaType: "CALL_LOG",
        conversation: {
          participants: {
            some: {
              userId,
            }
          }
        }
      },
      orderBy: {
        createdAt: 'desc',
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true,
            avatarUrl: true,
          }
        },
        conversation: {
          include: {
            participants: {
              include: {
                user: {
                  select: {
                    id: true,
                    username: true,
                    avatarUrl: true,
                  }
                }
              }
            }
          }
        }
      },
      take: 50,
    });

    res.json(callLogs);
  } catch (error) {
    console.error("Error fetching call history:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const updateParticipantSettings = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params["conversationId"] as string;
    const userId = req.user!.id;
    const { muteUntil, isArchived, isLocked, isFavorite } = req.body;

    if (!conversationId) {
      res.status(400).json({ message: "Conversation ID is required" });
      return;
    }

    const participant = await prisma.participant.findFirst({
      where: { conversationId, userId }
    });

    if (!participant) {
      res.status(403).json({ message: "You are not a participant" });
      return;
    }

    const updateData: any = {};
    if (muteUntil !== undefined) updateData.muteUntil = muteUntil ? new Date(muteUntil) : null;
    if (isArchived !== undefined) updateData.isArchived = isArchived;
    if (isLocked !== undefined) updateData.isLocked = isLocked;
    if (isFavorite !== undefined) updateData.isFavorite = isFavorite;

    const updatedParticipant = await prisma.participant.update({
      where: { id: participant.id },
      data: updateData,
    });

    res.json(updatedParticipant);
  } catch (error) {
    console.error("updateParticipantSettings error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const clearCallLogs = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    
    // We can just soft-delete the call logs for this specific user.
    // First, find all call logs for this user.
    const callLogs = await prisma.message.findMany({
      where: {
        mediaType: "CALL_LOG",
        conversation: {
          participants: {
            some: { userId }
          }
        }
      },
      select: { id: true }
    });

    const callLogIds = callLogs.map(log => log.id);

    if (callLogIds.length > 0) {
      // For each call log, create a DeletedMessage entry for this user
      const deletedEntries = callLogIds.map(messageId => ({
        messageId,
        userId
      }));

      await prisma.deletedMessage.createMany({
        data: deletedEntries
      });
    }

    res.json({ message: "Call logs cleared" });
  } catch (error) {
    console.error("clearCallLogs error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const starMessage = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const messageId = req.params["messageId"] as string;

    const existing = await prisma.starredMessage.findUnique({
      where: { userId_messageId: { userId, messageId } }
    });

    if (existing) {
      await prisma.starredMessage.delete({ where: { id: existing.id } });
      res.json({ message: "Message unstarred" });
    } else {
      await prisma.starredMessage.create({
        data: { userId, messageId }
      });
      res.json({ message: "Message starred" });
    }
  } catch (error) {
    console.error("Star message error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const pinMessage = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params["conversationId"] as string;
    const messageId = req.params["messageId"] as string;

    // Toggle pin
    const conversation = await prisma.conversation.findUnique({ where: { id: conversationId } });
    
    if (conversation?.pinnedMessageId === messageId) {
      await prisma.conversation.update({
        where: { id: conversationId },
        data: { pinnedMessageId: null }
      });
      res.json({ message: "Message unpinned" });
    } else {
      await prisma.conversation.update({
        where: { id: conversationId },
        data: { pinnedMessageId: messageId }
      });
      res.json({ message: "Message pinned" });
    }
  } catch (error) {
    console.error("Pin message error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const deleteMessage = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const messageId = req.params["messageId"] as string;
    const forEveryone = req.query["forEveryone"] as string | undefined;

    const message = await prisma.message.findUnique({ where: { id: messageId } });

    if (!message) {
      res.status(404).json({ message: "Message not found" });
      return;
    }

    if (forEveryone === "true") {
      if (message.senderId !== userId) {
        res.status(403).json({ message: "You can only delete your own messages for everyone" });
        return;
      }
      
      await prisma.message.update({
        where: { id: messageId },
        data: { isDeleted: true, content: "This message was deleted" }
      });

      // Emit socket event
      const io = (req as any).app.get("io");
      if (io) {
        const participants = await prisma.participant.findMany({
          where: { conversationId: message.conversationId },
          select: { userId: true }
        });
        participants.forEach(p => {
          io.to(p.userId).emit("message_deleted", { messageId, conversationId: message.conversationId });
        });
      }
    } else {
      // Delete for me
      await prisma.deletedMessage.create({
        data: { userId, messageId }
      });
    }

    res.json({ message: "Message deleted" });
  } catch (error) {
    console.error("Delete message error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};
