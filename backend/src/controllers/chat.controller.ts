import type { Response } from "express";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";
import { encryptionService } from "../services/encryption.service.js";
import { canViewProfilePhoto, canViewAbout, canViewLastSeen, canViewOnline } from "../utils/privacy.engine.js";

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

    // Batch fetch unread counts for all conversations in a single DB query
    const conversationIds = conversations.map((c) => c.id);
    let unreadCountMap: Record<string, number> = {};

    if (conversationIds.length > 0) {
      try {
        const unreadCounts = await prisma.message.groupBy({
          by: ["conversationId"],
          where: {
            conversationId: { in: conversationIds },
            senderId: { not: userId },
            receipts: {
              none: {
                userId,
                status: "READ",
              },
            },
          },
          _count: { id: true },
        });

        for (const item of unreadCounts) {
          unreadCountMap[item.conversationId] = item._count.id;
        }
      } catch (_) {}
    }

    // Format chat list for frontend convenience
    const formattedChats = await Promise.all(
      conversations.map(async (chat) => {
        // Find the recipient (the other participant in a 1-on-1 chat)
        const otherParticipant = chat.participants.find((p) => p.userId !== userId);
        const recipient = otherParticipant ? { ...otherParticipant.user } : null;
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

        const unreadCount = unreadCountMap[chat.id] || 0;

        if (recipient) {
          try {
            const [canViewPhoto, canViewBio] = await Promise.all([
              canViewProfilePhoto(userId, recipient.id),
              canViewAbout(userId, recipient.id),
            ]);
            if (!canViewPhoto) recipient.avatarUrl = null;
            if (!canViewBio) recipient.bio = null;
          } catch (_) {}
        }

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
          isArchived: chat.participants.find((p) => p.userId === userId)?.isArchived || false,
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
        reactions: true,
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

export const getMediaMessages = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const conversationId = req.params["conversationId"];
    const userId = req.user!.id;

    if (!conversationId || typeof conversationId !== "string") {
      res.status(400).json({ message: "Conversation ID is required" });
      return;
    }

    // Verify participant
    const isParticipant = await prisma.participant.findFirst({
      where: { conversationId, userId },
    });

    if (!isParticipant) {
      res.status(403).json({ message: "You are not a participant in this conversation" });
      return;
    }

    // Fetch only media messages (IMAGE, VIDEO, FILE/DOCUMENT)
    const mediaMessages = await prisma.message.findMany({
      where: {
        conversationId,
        mediaUrl: { not: null },
        mediaType: { in: ["IMAGE", "VIDEO", "FILE", "DOCUMENT"] },
        isDeleted: false,
        deletedForUsers: { none: { userId } },
      },
      orderBy: { createdAt: "desc" },
      take: 200,
      select: {
        id: true,
        mediaUrl: true,
        mediaType: true,
        content: true,
        createdAt: true,
        senderId: true,
        sender: {
          select: { id: true, username: true, avatarUrl: true },
        },
      },
    });

    res.json(mediaMessages);
  } catch (error) {
    console.error("GetMediaMessages error:", error);
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
      select: { id: true, username: true, email: true, phoneNumber: true, avatarUrl: true, bio: true, lastSeen: true, isOnline: true },
    });

    if (!targetUser) {
      res.status(404).json({ message: "Target user not found" });
      return;
    }

    const [canViewPhoto, canViewBio, canSeeLastSeen, canSeeOnline] = await Promise.all([
      canViewProfilePhoto(currentUserId, targetUser.id),
      canViewAbout(currentUserId, targetUser.id),
      canViewLastSeen(currentUserId, targetUser.id),
      canViewOnline(currentUserId, targetUser.id),
    ]);
    if (!canViewPhoto) targetUser.avatarUrl = null;
    if (!canViewBio) targetUser.bio = null;
    if (!canSeeLastSeen) targetUser.lastSeen = null;
    if (!canSeeOnline) targetUser.isOnline = false;

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

    // Get all messages in this conversation
    const messages = await prisma.message.findMany({
      where: { conversationId },
      select: { id: true },
    });

    // Create DeletedMessage records for each message FOR THIS USER ONLY
    // This is "clear for me" — the other user still sees their messages
    await prisma.deletedMessage.createMany({
      data: messages.map((m) => ({ messageId: m.id, userId })),
      skipDuplicates: true,
    });

    // Emit socket event ONLY to the requesting user so their message list clears
    const io = (req as any).app.get("io");
    if (io) {
      io.to(userId).emit("chat_cleared", { conversationId });
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

    // Find all messages across all conversations the user is part of that are CALL_LOG and not deleted for user
    const callLogs = await prisma.message.findMany({
      where: {
        mediaType: "CALL_LOG",
        isDeleted: false,
        deletedForUsers: {
          none: {
            userId,
          }
        },
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
        data: { 
          isDeleted: true, 
          content: "This message was deleted",
          mediaUrl: null,
          mediaType: null,
          isForwarded: false
        }
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

export const clearCallLogs = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;

    // A call log is a message of type CALL.
    // Instead of deleting from DB, we insert into DeletedMessage to hide it for this user.
    const callMessages = await prisma.message.findMany({
      where: {
        mediaType: "CALL_LOG",
        conversation: {
          participants: {
            some: { userId }
          }
        },
        deletedForUsers: {
          none: { userId }
        }
      },
      select: { id: true }
    });

    if (callMessages.length > 0) {
      const deletedData = callMessages.map(msg => ({
        userId,
        messageId: msg.id
      }));

      await prisma.deletedMessage.createMany({
        data: deletedData,
        skipDuplicates: true
      });
    }

    res.json({ message: "Call logs cleared" });
  } catch (error) {
    console.error("Clear call logs error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const deleteSingleCallLog = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const callId = req.params["callId"] as string;

    if (!callId) {
      res.status(400).json({ message: "Call ID is required" });
      return;
    }

    await prisma.deletedMessage.createMany({
      data: [
        {
          userId,
          messageId: callId,
        },
      ],
      skipDuplicates: true,
    });

    res.json({ message: "Call log deleted" });
  } catch (error) {
    console.error("Delete single call log error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const deleteBulkCallLogs = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { callIds } = req.body;

    if (!Array.isArray(callIds) || callIds.length === 0) {
      res.status(400).json({ message: "callIds array is required" });
      return;
    }

    const data = callIds.map((id: string) => ({
      userId,
      messageId: id,
    }));

    await prisma.deletedMessage.createMany({
      data,
      skipDuplicates: true,
    });

    res.json({ message: "Call logs deleted successfully" });
  } catch (error) {
    console.error("Delete bulk call logs error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

/** Feature #35: Large File Streaming & Chunked Upload Endpoint */
export const uploadChunk = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { uploadId, chunkIndex, totalChunks } = req.body;
    if (!req.file) {
      res.status(400).json({ message: "No chunk file provided" });
      return;
    }
    const chunkUrl = `/uploads/${req.file.filename}`;
    res.json({
      success: true,
      uploadId,
      chunkIndex,
      totalChunks,
      chunkUrl,
      isComplete: Number(chunkIndex) + 1 >= Number(totalChunks),
    });
  } catch (error) {
    console.error("Upload chunk error:", error);
    res.status(500).json({ message: "Failed to process chunk" });
  }
};


