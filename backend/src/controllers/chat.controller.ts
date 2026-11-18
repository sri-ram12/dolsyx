import type { Response } from "express";
import { Prisma } from "@prisma/client";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";
import { evaluatePrivacyInMemory, canViewProfilePhoto, canViewAbout, canViewLastSeen, canViewOnline } from "../utils/privacy.engine.js";
import { encryptionService } from "../services/encryption.service.js";
import { sendPushNotification } from "../config/firebase.config.js";

// ── Serverless-Compatible Live Typing & Online Presence Store ─────────────────
// Works seamlessly across both persistent Socket.IO and multi-instance Vercel Serverless
const presenceThrottle = new Map<string, number>();
const PRESENCE_THROTTLE_MS = 15000;
const ONLINE_WINDOW_MS = 35000;
const TYPING_TTL_MS = 6000;

let typingTableReady = false;
async function ensureTypingTable(): Promise<void> {
  if (typingTableReady) return;
  try {
    await prisma.$executeRawUnsafe(`
      CREATE TABLE IF NOT EXISTS "TypingStatus" (
        "conversationId" TEXT NOT NULL,
        "userId" TEXT NOT NULL,
        "username" TEXT,
        "expiresAt" BIGINT NOT NULL,
        PRIMARY KEY ("conversationId", "userId")
      )
    `);
    typingTableReady = true;
  } catch (_) {}
}

function touchUserPresence(userId: string): void {
  const now = Date.now();
  const last = presenceThrottle.get(userId) ?? 0;
  if (now - last < PRESENCE_THROTTLE_MS) return;
  presenceThrottle.set(userId, now);
  if (presenceThrottle.size > 5000) presenceThrottle.clear();
  prisma.user
    .update({
      where: { id: userId },
      data: { lastSeen: new Date(now), isOnline: true },
    })
    .catch(() => {});
}

async function getActiveTypingMap(conversationIds: string[], excludeUserId: string): Promise<Record<string, string[]>> {
  const map: Record<string, string[]> = {};
  if (conversationIds.length === 0) return map;
  try {
    await ensureTypingTable();
    const now = BigInt(Date.now());
    const rows = await prisma.$queryRaw<Array<{ conversationId: string; userId: string }>>`
      SELECT "conversationId", "userId"
      FROM "TypingStatus"
      WHERE "conversationId" IN (${Prisma.join(conversationIds)})
        AND "userId" != ${excludeUserId}
        AND "expiresAt" > ${now}
    `;
    for (const r of rows) {
      if (!map[r.conversationId]) map[r.conversationId] = [];
      map[r.conversationId]!.push(r.userId);
    }
  } catch (_) {}
  return map;
}

export const getChats = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    touchUserPresence(userId);

    // Batch 1 (Parallel): Fetch conversations and user blocks simultaneously
    const [conversations, myBlocks] = await Promise.all([
      prisma.conversation.findMany({
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
                  avatarPrivacy: true,
                  avatarPrivacyExceptList: true,
                  lastSeenPrivacy: true,
                  lastSeenPrivacyExceptList: true,
                  onlinePrivacy: true,
                  aboutPrivacy: true,
                  aboutPrivacyExceptList: true,
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
              receipts: true,
            },
          },
        },
        orderBy: {
          updatedAt: "desc",
        },
      }),
      prisma.userBlock.findMany({
        where: {
          OR: [{ blockerId: userId }, { blockedId: userId }],
        },
      }),
    ]);

    const blockedSet = new Set<string>();
    for (const b of myBlocks) {
      if (b.blockerId === userId) blockedSet.add(b.blockedId);
      if (b.blockedId === userId) blockedSet.add(b.blockerId);
    }

    const conversationIds = conversations.map((c) => c.id);
    const recipientUserIds = Array.from(new Set(
      conversations
        .map((c) => c.participants.find((p) => p.userId !== userId)?.userId)
        .filter((id): id is string => Boolean(id))
    ));

    // Batch 2 (Parallel): PgBouncer-safe unread counts, recipient contacts, active typing map, and auto-DELIVERED receipt upgrade
    let unreadCountMap: Record<string, number> = {};
    const [, recipientContacts, typingMap] = await Promise.all([
      conversationIds.length > 0
        ? (async () => {
            try {
              const unreadGroups = await prisma.message.groupBy({
                by: ["conversationId"],
                where: {
                  conversationId: { in: conversationIds },
                  senderId: { not: userId },
                  isDeleted: false,
                  deletedForUsers: { none: { userId } },
                  receipts: {
                    none: {
                      userId,
                      status: "READ",
                    },
                  },
                },
                _count: { id: true },
              });

              for (const row of unreadGroups) {
                unreadCountMap[row.conversationId] = row._count.id;
              }
            } catch (err) {
              console.warn("[getChats] Unread count groupBy error:", err);
            }
          })()
        : Promise.resolve(),
      recipientUserIds.length > 0
        ? prisma.contact.findMany({
            where: {
              userId: { in: recipientUserIds },
              contactId: userId,
            },
            select: { userId: true },
          })
        : Promise.resolve([]),
      getActiveTypingMap(conversationIds, userId),
      // Auto-upgrade SENT receipts to DELIVERED for this active user (enables double grey ticks without WebSockets)
      conversationIds.length > 0
        ? prisma.messageReceipt
            .updateMany({
              where: {
                userId,
                status: "SENT",
                message: {
                  conversationId: { in: conversationIds },
                  senderId: { not: userId },
                },
              },
              data: { status: "DELIVERED" },
            })
            .catch(() => {})
        : Promise.resolve(),
    ]);

    const contactsOfRecipientsSet = new Set<string>(recipientContacts.map((c) => c.userId));

    // Format chat list in-memory — 0 additional DB queries
    const formattedChats = conversations.map((chat) => {
      // Find the recipient (the other participant in a 1-on-1 chat)
      const otherParticipant = chat.participants.find((p) => p.userId !== userId);
      const recipient = otherParticipant ? { ...otherParticipant.user } : null;
      // Zero-Knowledge E2EE: return stored content as-is so clients decrypt locally, but decrypt any server at-rest layer first
      const rawLastMessage = chat.messages[0] || null;
      const lastMessage = rawLastMessage
        ? {
            ...rawLastMessage,
            content: encryptionService.decrypt(rawLastMessage.content || ""),
          }
        : null;

      const unreadCount = unreadCountMap[chat.id] || 0;

      if (recipient) {
        // Compute serverless-friendly live online status from recent heartbeat
        const recentlyActive = Boolean(
          recipient.lastSeen &&
            Date.now() - new Date(recipient.lastSeen).getTime() < ONLINE_WINDOW_MS
        );
        recipient.isOnline = Boolean(recipient.isOnline || recentlyActive);

        const isBlocked = blockedSet.has(recipient.id);
        const isContact = contactsOfRecipientsSet.has(recipient.id);
        const privacy = evaluatePrivacyInMemory(userId, recipient, isBlocked, isContact);

        if (!privacy.canPhoto) recipient.avatarUrl = null;
        if (!privacy.canLastSeen) recipient.lastSeen = null;
        if (!privacy.canOnlineStatus) recipient.isOnline = false;
        if (!privacy.canAbout) recipient.bio = null;
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
        typingUserIds: typingMap[chat.id] || [],
        isArchived: chat.participants.find((p) => p.userId === userId)?.isArchived || false,
        isLocked: chat.participants.find((p) => p.userId === userId)?.isLocked || false,
        isFavorite: chat.participants.find((p) => p.userId === userId)?.isFavorite || false,
      };
    });

    // Deduplicate 1-on-1 direct conversations so each contact/user appears strictly once
    const seenDirectUserIds = new Set<string>();
    const deduplicatedChats = [];

    for (const chat of formattedChats) {
      if (!chat.isGroup && chat.recipient?.id) {
        if (seenDirectUserIds.has(chat.recipient.id)) {
          // Skip duplicate conversation for the same user
          continue;
        }
        seenDirectUserIds.add(chat.recipient.id);
      }
      deduplicatedChats.push(chat);
    }

    res.json(deduplicatedChats);
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

    touchUserPresence(userId);

    const cursor = req.query["cursor"] as string | undefined;
    const limitQuery = req.query["limit"] as string | undefined;
    const limit = limitQuery ? Math.min(Math.max(parseInt(limitQuery, 10), 1), 100) : 50;

    const findArgs: any = {
      where: {
        conversationId,
        deletedForUsers: {
          none: {
            userId,
          },
        },
      },
      take: limit,
      orderBy: {
        createdAt: "desc",
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
        parentMessage: true,
      },
    };

    if (cursor) {
      findArgs.cursor = { id: cursor };
      findArgs.skip = 1;
    }

    // Parallelize participant auth check, message fetch, typing indicator, and remote presence (single DB round-trip)
    const [isParticipant, messages, typingMap, remoteParticipants] = await Promise.all([
      prisma.participant.findFirst({
        where: {
          conversationId,
          userId,
        },
        select: { id: true },
      }),
      prisma.message.findMany(findArgs),
      !cursor ? getActiveTypingMap([conversationId], userId) : Promise.resolve({} as Record<string, string[]>),
      !cursor
        ? prisma.participant.findMany({
            where: { conversationId, userId: { not: userId } },
            select: {
              user: {
                select: {
                  id: true,
                  isOnline: true,
                  lastSeen: true,
                  onlinePrivacy: true,
                  lastSeenPrivacy: true,
                },
              },
            },
            take: 2,
          })
        : Promise.resolve([]),
    ]);

    if (!isParticipant) {
      res.status(403).json({ message: "You are not a participant in this conversation" });
      return;
    }

    // Auto-mark ONLY actually-unread messages from others as READ (0 DB writes on idle polls!)
    if (!cursor && req.query["markRead"] !== "false") {
      const unreadOtherMessageIds = messages
        .filter(
          (m: any) =>
            m.senderId !== userId &&
            !(Array.isArray(m.receipts) && m.receipts.some((r: any) => r.userId === userId && r.status === "READ"))
        )
        .map((m: any) => m.id as string);

      if (unreadOtherMessageIds.length > 0) {
        try {
          await Promise.all([
            prisma.messageReceipt.updateMany({
              where: {
                userId,
                messageId: { in: unreadOtherMessageIds },
                status: { not: "READ" },
              },
              data: { status: "READ" },
            }),
            prisma.messageReceipt.createMany({
              data: unreadOtherMessageIds.map((messageId) => ({
                messageId,
                userId,
                status: "READ",
              })),
              skipDuplicates: true,
            }),
          ]);
        } catch (_) {
          // Non-blocking
        }
      }
    }

    // Reverse for chronological order on the client
    messages.reverse();

    const nextCursor = messages.length === limit ? messages[0]?.id : null;
    if (nextCursor) {
      res.setHeader("X-Next-Cursor", nextCursor);
    }

    // Attach live typing & online presence headers (works seamlessly on serverless without changing JSON shape)
    const activeTypingIds = typingMap[conversationId] || [];
    res.setHeader("X-Typing-Users", JSON.stringify(activeTypingIds));
    if (remoteParticipants.length === 1 && remoteParticipants[0]?.user) {
      const ru = remoteParticipants[0].user;
      const recentlyActive = Boolean(
        ru.lastSeen && Date.now() - new Date(ru.lastSeen).getTime() < ONLINE_WINDOW_MS
      );
      const canShowOnline = ru.onlinePrivacy !== "NOBODY";
      const canShowLastSeen = ru.lastSeenPrivacy !== "NOBODY";
      const isRemoteOnline = canShowOnline && Boolean(ru.isOnline || recentlyActive);
      res.setHeader("X-Remote-Online", isRemoteOnline ? "true" : "false");
      if (canShowLastSeen && ru.lastSeen) {
        res.setHeader("X-Remote-Last-Seen", new Date(ru.lastSeen).toISOString());
      }
    }
    res.setHeader(
      "Access-Control-Expose-Headers",
      "X-Next-Cursor, X-Typing-Users, X-Remote-Online, X-Remote-Last-Seen"
    );

    // Decrypt any at-rest server encryption layers (leaves client E2EE payloads intact for client decryption)
    const processedMessages = messages.map((m: any) => ({
      ...m,
      content: encryptionService.decrypt(m.content || ""),
      parentMessage: m.parentMessage
        ? {
            ...m.parentMessage,
            content: encryptionService.decrypt(m.parentMessage.content || ""),
          }
        : null,
    }));

    res.json(processedMessages);
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

    // Fetch messages for conversation, excluding non-media/call logs
    const messages = await prisma.message.findMany({
      where: {
        conversationId,
        isDeleted: false,
        isViewOnce: false, // Privacy: Never leak View-Once media in shared gallery
        deletedForUsers: { none: { userId } },
        mediaType: {
          notIn: ["CALL_LOG", "SYSTEM", "LOCATION"],
        },
      },
      orderBy: { createdAt: "desc" },
      take: 500,
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

    const processedMediaMessages = messages.map((m: any) => ({
      ...m,
      content: encryptionService.decrypt(m.content || ""),
    }));

    res.json(processedMediaMessages);
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

    // Block check — if either user has blocked the other, deny chat creation
    const blockRecord = await prisma.userBlock.findFirst({
      where: {
        OR: [
          { blockerId: currentUserId, blockedId: targetUserId },
          { blockerId: targetUserId, blockedId: currentUserId },
        ],
      },
    });
    if (blockRecord) {
      res.status(403).json({ message: "Cannot start a conversation with this user" });
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
        const deletePayload = {
          messageId: message.id,
          conversationId: message.conversationId,
          isDeleted: true,
          content: "This message was deleted",
        };
        participants.forEach(p => {
          io.to(p.userId).emit("message_deleted", deletePayload);
        });
        io.to(message.conversationId).emit("message_deleted", deletePayload);
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
    });
  } catch (error) {
    console.error("Upload chunk error:", error);
    res.status(500).json({ message: "Failed to upload chunk" });
  }
};

export const editMessage = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const messageId = req.params["messageId"] as string;
    const { content } = req.body;

    if (!content || !content.trim()) {
      res.status(400).json({ message: "Message content cannot be empty" });
      return;
    }

    const message = await prisma.message.findUnique({ where: { id: messageId } });

    if (!message) {
      res.status(404).json({ message: "Message not found" });
      return;
    }

    if (message.senderId !== userId) {
      res.status(403).json({ message: "You can only edit your own messages" });
      return;
    }

    // 15-minute edit time limit check
    const ageInMinutes = (Date.now() - new Date(message.createdAt).getTime()) / (1000 * 60);
    if (ageInMinutes > 15) {
      res.status(400).json({ message: "Messages can only be edited within 15 minutes of sending" });
      return;
    }

    // Zero-Knowledge E2EE: Store client ciphertext directly
    const updated = await prisma.message.update({
      where: { id: messageId },
      data: {
        content: content.trim(),
        isEdited: true,
      },
    });

    const decryptedMessage = {
      ...updated,
      content: content.trim(),
    };

    // Socket broadcast
    const io = (req as any).app.get("io");
    if (io) {
      const participants = await prisma.participant.findMany({
        where: { conversationId: message.conversationId },
        select: { userId: true },
      });
      participants.forEach((p) => {
        io.to(p.userId).emit("message_edited", {
          message: decryptedMessage,
          conversationId: message.conversationId,
        });
      });
    }

    res.json({ message: "Message edited successfully", messageData: decryptedMessage });
  } catch (error) {
    console.error("Edit message error:", error);
    res.status(500).json({ message: "Failed to edit message" });
  }
};

/**
 * REST fallback for sending messages (enables full E2EE messaging on serverless hosts like Vercel
 * where WebSocket upgrades are unavailable, while also broadcasting via Socket.IO when active).
 */
export const sendMessageRest = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const senderId = req.user!.id;
    const conversationId = req.params["conversationId"] as string;
    const {
      content,
      mediaUrl,
      mediaType,
      parentMessageId,
      isForwarded,
      forwardCount,
      isViewOnce,
      latitude,
      longitude,
      locationTitle,
      isLiveLocation,
      liveExpiresAt,
      tempId,
    } = req.body;

    if (!conversationId) {
      res.status(400).json({ message: "conversationId is required" });
      return;
    }

    const participants = await prisma.participant.findMany({
      where: { conversationId },
      select: {
        userId: true,
        user: { select: { id: true, username: true, fcmToken: true } },
        conversation: { select: { isGroup: true, name: true } },
      },
    });

    const isMember = participants.some((p) => p.userId === senderId);
    if (!isMember) {
      res.status(403).json({ message: "Not a participant of this conversation" });
      return;
    }

    // Zero-Knowledge E2EE: Persist client-encrypted ciphertext directly without server decryption
    const createdMessage = await prisma.message.create({
      data: {
        content: typeof content === "string" ? content.trim() : "",
        conversationId,
        senderId,
        mediaUrl: mediaUrl || null,
        mediaType: mediaType || "TEXT",
        parentMessageId: parentMessageId || null,
        isForwarded: Boolean(isForwarded),
        forwardCount: typeof forwardCount === "number" ? forwardCount : 0,
        isViewOnce: Boolean(isViewOnce),
        latitude: typeof latitude === "number" ? latitude : null,
        longitude: typeof longitude === "number" ? longitude : null,
        locationTitle: locationTitle || null,
        isLiveLocation: Boolean(isLiveLocation),
        liveExpiresAt: liveExpiresAt ? new Date(liveExpiresAt) : null,
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true,
            avatarUrl: true,
          },
        },
        parentMessage: true,
        receipts: true,
      },
    });

    await prisma.conversation.update({
      where: { id: conversationId },
      data: { updatedAt: new Date() },
    });

    const otherParticipants = participants.filter((p) => p.userId !== senderId);
    if (otherParticipants.length > 0) {
      await prisma.messageReceipt.createMany({
        data: otherParticipants.map((p) => ({
          messageId: createdMessage.id,
          userId: p.userId,
          status: "SENT",
        })),
        skipDuplicates: true,
      });
    }

    // Broadcast via Socket.IO if running on a persistent host
    const io = (req as any).app?.get("io");
    if (io) {
      const payload = {
        message: createdMessage,
        conversationId,
        ...(tempId ? { tempId } : {}),
      };
      io.to(conversationId).emit("new_message", payload);
      participants.forEach((p) => {
        io.to(p.userId).emit("new_message", payload);
      });
    }

    // Send FCM push notifications to other participants (non-blocking)
    const senderName = createdMessage.sender?.username || "New message";
    const pushBody = mediaType && mediaType !== "TEXT" ? `Sent a ${String(mediaType).toLowerCase()}` : "New encrypted message";
    for (const p of otherParticipants) {
      if (p.user?.fcmToken) {
        sendPushNotification(p.user.fcmToken, senderName, pushBody, {
          type: "MESSAGE",
          conversationId,
          messageId: createdMessage.id,
          senderId,
        }).catch(() => {});
      }
    }

    // Clear sender's typing indicator & refresh online heartbeat (non-blocking)
    touchUserPresence(senderId);
    ensureTypingTable()
      .then(() =>
        prisma.$executeRaw`DELETE FROM "TypingStatus" WHERE "conversationId" = ${conversationId} AND "userId" = ${senderId}`
      )
      .catch(() => {});

    res.status(201).json({
      ...createdMessage,
      ...(tempId ? { tempId } : {}),
    });
  } catch (error) {
    console.error("Send message REST error:", error);
    res.status(500).json({ message: "Failed to send message" });
  }
};

/**
 * REST fallback for marking all unread messages in a conversation as READ (blue ticks + unread count = 0).
 */
export const markConversationReadRest = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const conversationId = req.params["conversationId"] as string;
    if (!conversationId) {
      res.status(400).json({ message: "conversationId is required" });
      return;
    }

    const unreadMessages = await prisma.message.findMany({
      where: {
        conversationId,
        senderId: { not: userId },
        isDeleted: false,
        receipts: { none: { userId, status: "READ" } },
      },
      select: { id: true },
      take: 200,
    });

    if (unreadMessages.length > 0) {
      const msgIds = unreadMessages.map((m) => m.id);
      await Promise.all([
        prisma.messageReceipt.updateMany({
          where: { userId, messageId: { in: msgIds }, status: { not: "READ" } },
          data: { status: "READ" },
        }),
        prisma.messageReceipt.createMany({
          data: msgIds.map((messageId) => ({ messageId, userId, status: "READ" })),
          skipDuplicates: true,
        }),
      ]);
    }

    const io = (req as any).app?.get("io");
    if (io) {
      io.to(conversationId).emit("messages_read", { conversationId, userId });
    }

    res.json({ success: true, markedCount: unreadMessages.length });
  } catch (error) {
    console.error("Mark conversation read REST error:", error);
    res.status(500).json({ message: "Failed to mark conversation as read" });
  }
};

/**
 * REST fallback for live typing indicators on serverless hosts (Vercel).
 * Persists a short-lived (6s TTL) typing row in Postgres and broadcasts via Socket.IO if available.
 */
export const setTypingStatusRest = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const username = req.user!.username || "";
    const conversationId = req.params["conversationId"] as string;
    const isTyping = Boolean(req.body?.isTyping);

    if (!conversationId) {
      res.status(400).json({ message: "conversationId is required" });
      return;
    }

    touchUserPresence(userId);
    await ensureTypingTable();

    if (isTyping) {
      const expiresAt = BigInt(Date.now() + TYPING_TTL_MS);
      await prisma.$executeRaw`
        INSERT INTO "TypingStatus" ("conversationId", "userId", "username", "expiresAt")
        VALUES (${conversationId}, ${userId}, ${username}, ${expiresAt})
        ON CONFLICT ("conversationId", "userId")
        DO UPDATE SET "username" = EXCLUDED."username", "expiresAt" = EXCLUDED."expiresAt"
      `;
    } else {
      await prisma.$executeRaw`
        DELETE FROM "TypingStatus"
        WHERE "conversationId" = ${conversationId} AND "userId" = ${userId}
      `;
    }

    const io = (req as any).app?.get("io");
    if (io) {
      io.to(conversationId).emit("user_typing", {
        conversationId,
        userId,
        username,
        isTyping,
      });
    }

    res.json({ ok: true, conversationId, isTyping });
  } catch (error) {
    console.error("Set typing status REST error:", error);
    res.status(500).json({ message: "Failed to update typing status" });
  }
};



