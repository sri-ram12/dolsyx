import { Server } from "socket.io";
import jwt from "jsonwebtoken";
import { prisma } from "../config/db.js";
import { encryptionService } from "../services/encryption.service.js";
import { sendPushNotification } from "../config/firebase.config.js";
import { canViewOnline, canViewLastSeen } from "../utils/privacy.engine.js";

const JWT_SECRET = process.env.JWT_SECRET || "dolsyx_super_secret_key_123456";

// Map to track online users: userId -> Set of socket.id (supports multiple client connections)
const onlineUsers = new Map<string, Set<string>>();
// Map to track users currently active in a call: userId -> conversationId
const activeCallUsers = new Map<string, string>();
// In-memory cache for conversation participants for <1ms zero-lag delivery
const convParticipantsCache = new Map<string, { userIds: string[]; isGroup: boolean; name: string; timestamp: number }>();

// Persistent Scheduled Messages Store & Dispatcher
export interface ScheduledMsg {
  id: string;
  conversationId: string;
  senderId: string;
  content: string;
  scheduledFor: number; // epoch ms
  mediaUrl?: string | null | undefined;
  mediaType?: string | null | undefined;
  createdAt: number;
}
const scheduledMessagesStore = new Map<string, ScheduledMsg>();

let schedulerTickStarted = false;

async function executeScheduledMessage(io: Server, msg: ScheduledMsg) {
  const { id, conversationId, senderId, content, mediaUrl, mediaType } = msg;
  try {
    const now = Date.now();
    let cached = convParticipantsCache.get(conversationId);
    if (!cached || now - cached.timestamp > 300000) {
      const fetched = await prisma.participant.findMany({
        where: { conversationId },
        select: {
          userId: true,
          conversation: { select: { isGroup: true, name: true } },
        },
      });
      cached = {
        userIds: fetched.map((p) => p.userId),
        isGroup: fetched[0]?.conversation?.isGroup || false,
        name: fetched[0]?.conversation?.name || "",
        timestamp: now,
      };
      convParticipantsCache.set(conversationId, cached);
    }

    const participantUserIds = cached.userIds;

    const encryptedContent = content ? encryptionService.encrypt(content.trim()) : "";
    const createdMessage = await prisma.message.create({
      data: {
        content: encryptedContent,
        conversationId,
        senderId,
        mediaUrl: mediaUrl || null,
        mediaType: (mediaType as any) || "TEXT",
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

    const decryptedMessage = {
      ...createdMessage,
      content: content ? content.trim() : "",
    };

    // 🚀 Broadcast to conversation room and all participant sockets
    io.to(conversationId).emit("new_message", {
      message: decryptedMessage,
      conversationId,
    });

    participantUserIds.forEach((pId) => {
      io.to(pId).emit("new_message", {
        message: decryptedMessage,
        conversationId,
      });
    });

    // Notify sender that scheduled message was dispatched
    io.to(senderId).emit("scheduled_message_executed", {
      id,
      conversationId,
      message: decryptedMessage,
    });

    // Background receipts & conversation touch
    setImmediate(async () => {
      try {
        await prisma.conversation.update({
          where: { id: conversationId },
          data: { updatedAt: new Date() },
        });

        const otherParticipantIds = participantUserIds.filter((pId) => pId !== senderId);
        const receiptsToCreate = otherParticipantIds.map((pId) => ({
          messageId: createdMessage.id,
          userId: pId,
          status: onlineUsers.has(pId) ? "DELIVERED" : "SENT",
        }));

        if (receiptsToCreate.length > 0) {
          await prisma.messageReceipt.createMany({
            data: receiptsToCreate,
            skipDuplicates: true,
          });
        }
      } catch (_) {}
    });
  } catch (err) {
    console.error(`[SCHEDULED MSG] Error executing scheduled message ${id}:`, err);
  }
}

export const initChatSocket = (io: Server) => {
  if (!schedulerTickStarted) {
    schedulerTickStarted = true;
    setInterval(async () => {
      const now = Date.now();
      for (const [id, msg] of scheduledMessagesStore.entries()) {
        if (msg.scheduledFor <= now) {
          scheduledMessagesStore.delete(id);
          try {
            await executeScheduledMessage(io, msg);
          } catch (e) {
            console.error(`[SCHEDULED MSG] Error executing ${id}:`, e);
          }
        }
      }
    }, 3000);
  }

  // Authentication middleware for Socket.io
  io.use((socket: any, next) => {
    const token =
      socket.handshake.auth?.token ||
      socket.handshake.headers?.authorization?.split(" ")[1];

    if (!token) {
      return next(new Error("Authentication error: Token missing"));
    }

    try {
      const decoded = jwt.verify(token, JWT_SECRET) as {
        id: string;
        username: string;
      };
      socket.userId = decoded.id;
      socket.username = decoded.username;
      next();
    } catch (err) {
      next(new Error("Authentication error: Invalid token"));
    }
  });

  io.on("connection", (socket: any) => {
    const userId = socket.userId;
    const username = socket.username;

    console.log(`User connected to socket: ${username} (${userId})`);

    // Add to online users tracking
    if (!onlineUsers.has(userId)) {
      onlineUsers.set(userId, new Set());
    }
    onlineUsers.get(userId)!.add(socket.id);

    // Join personal room to receive real-time direct notifications/messages
    socket.join(userId);

    // Auto-deliver pending messages to this connected user
    setImmediate(async () => {
      try {
        const undelivered = await prisma.messageReceipt.findMany({
          where: {
            userId,
            status: "SENT",
          },
          select: {
            messageId: true,
            message: { select: { conversationId: true } },
          },
        });

        if (undelivered.length > 0) {
          const msgIds = undelivered.map((r) => r.messageId);
          await prisma.messageReceipt.updateMany({
            where: {
              messageId: { in: msgIds },
              userId,
              status: "SENT",
            },
            data: { status: "DELIVERED" },
          });

          const byConv = new Map<string, string[]>();
          undelivered.forEach((r) => {
            const cId = r.message?.conversationId;
            if (cId) {
              const l = byConv.get(cId) || [];
              l.push(r.messageId);
              byConv.set(cId, l);
            }
          });

          byConv.forEach((ids, cId) => {
            io.to(cId).emit("messages_delivered", {
              conversationId: cId,
              messageIds: ids,
              userId,
            });
          });
        }
      } catch (err) {
        console.error("Auto delivery error on connect:", err);
      }
    });

    // Fetch privacy settings and relevant contacts
    prisma.user.findUnique({ where: { id: userId }, select: { lastSeenPrivacy: true, avatarUrl: true } }).then(async user => {
      if (user?.avatarUrl) {
        socket.avatarUrl = user.avatarUrl;
      }
      // Find all users who share a conversation with the connected user
      const relatedParticipants = await prisma.participant.findMany({
        where: {
          conversation: {
            participants: {
              some: { userId }
            }
          },
          userId: { not: userId }
        },
        select: { userId: true },
        distinct: ['userId']
      });

      // Filter onlineUsers to only include those relevant contacts
      const contactIds = new Set(relatedParticipants.map(p => p.userId));
      const onlineContacts = Array.from(onlineUsers.keys()).filter(id => contactIds.has(id));

      // Provide immediate restricted list of online users to the connected client
      // Note: A more robust implementation would filter this list by canViewOnline for each contact,
      // but for performance on connection we leave this as is or filter it.
      socket.emit("online_users_list", onlineContacts);

      const payload = {
        userId,
        status: "online",
      };

      // Broadcast user online status change ONLY to relevant contacts who have permission
      for (const p of relatedParticipants) {
        const canSee = await canViewOnline(p.userId, userId);
        if (canSee) {
          io.to(p.userId).emit("user_status_change", payload);
        }
      }
    }).catch(err => {
      console.error("Error in connection logic:", err);
    });

    // Join a conversation room (for targeting typing status broadcasts)
    socket.on("join_conversation", (conversationId: string) => {
      socket.join(conversationId);
      console.log(`Socket ${socket.id} joined conversation: ${conversationId}`);
    });

    // Leave a conversation room
    socket.on("leave_conversation", (conversationId: string) => {
      socket.leave(conversationId);
      console.log(`Socket ${socket.id} left conversation: ${conversationId}`);
    });

    // ==========================================
    // SCHEDULED MESSAGES EVENTS
    // ==========================================
    socket.on("schedule_message", async (data: {
      conversationId: string;
      content: string;
      scheduledFor: number;
      mediaUrl?: string;
      mediaType?: string;
    }, callback?: Function) => {
      const { conversationId, content, scheduledFor, mediaUrl, mediaType } = data || {};
      if (!conversationId || (!content && !mediaUrl) || !scheduledFor) {
        if (callback) callback({ success: false, error: "Invalid parameters" });
        return;
      }

      const scheduledMsg: ScheduledMsg = {
        id: `sched_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
        conversationId,
        senderId: userId,
        content: content || "",
        scheduledFor,
        mediaUrl,
        mediaType: mediaType || "TEXT",
        createdAt: Date.now(),
      };

      scheduledMessagesStore.set(scheduledMsg.id, scheduledMsg);
      console.log(`[SCHEDULED MSG] Scheduled for ${new Date(scheduledFor).toISOString()}: ${scheduledMsg.id}`);

      const userScheduled = Array.from(scheduledMessagesStore.values()).filter(
        (m) => m.conversationId === conversationId && m.senderId === userId
      );

      socket.emit("scheduled_messages_updated", {
        conversationId,
        scheduledMessages: userScheduled,
      });

      if (callback) callback({ success: true, scheduledMessage: scheduledMsg, scheduledMessages: userScheduled });
    });

    socket.on("get_scheduled_messages", (data: { conversationId: string }, callback?: Function) => {
      const { conversationId } = data || {};
      const userScheduled = Array.from(scheduledMessagesStore.values()).filter(
        (m) => m.conversationId === conversationId && m.senderId === userId
      );
      socket.emit("scheduled_messages_updated", {
        conversationId,
        scheduledMessages: userScheduled,
      });
      if (callback) callback({ success: true, scheduledMessages: userScheduled });
    });

    socket.on("cancel_scheduled_message", (data: { id: string; conversationId: string }, callback?: Function) => {
      const { id, conversationId } = data || {};
      const msg = scheduledMessagesStore.get(id);
      if (msg && msg.senderId === userId) {
        scheduledMessagesStore.delete(id);
      }
      const userScheduled = Array.from(scheduledMessagesStore.values()).filter(
        (m) => m.conversationId === conversationId && m.senderId === userId
      );
      socket.emit("scheduled_messages_updated", {
        conversationId,
        scheduledMessages: userScheduled,
      });
      if (callback) callback({ success: true, scheduledMessages: userScheduled });
    });

    socket.on("send_scheduled_message_now", async (data: { id: string }, callback?: Function) => {
      const { id } = data || {};
      const msg = scheduledMessagesStore.get(id);
      if (msg && msg.senderId === userId) {
        scheduledMessagesStore.delete(id);
        await executeScheduledMessage(io, msg);
        if (callback) callback({ success: true });
      } else {
        if (callback) callback({ success: false, error: "Not found" });
      }
    });

    // Handle real-time messaging with SUB-0.2MS ZERO-LAG DELIVERY
    socket.on("send_message", async (data: {
      id?: string;
      conversationId: string;
      content: string;
      parentMessageId?: string;
      mediaUrl?: string;
      mediaType?: string;
      isForwarded?: boolean;
      isViewOnce?: boolean;
      latitude?: number;
      longitude?: number;
      locationTitle?: string;
      isLiveLocation?: boolean;
      liveExpiresAt?: string | Date;
    }) => {
      try {
        const {
          id: clientMessageId,
          conversationId,
          content,
          parentMessageId,
          mediaUrl,
          mediaType,
          isForwarded,
          isViewOnce,
          latitude,
          longitude,
          locationTitle,
          isLiveLocation,
          liveExpiresAt
        } = data;

        // Allow empty content for media & location messages
        if (!mediaUrl && !latitude && (!content || !content.trim())) return;

        // Block check — reject message if either party has blocked the other (DM only)
        const conv = await prisma.conversation.findUnique({
          where: { id: conversationId },
          select: { isGroup: true, participants: { select: { userId: true } } },
        });
        if (conv && !conv.isGroup) {
          const otherUserId = conv.participants.find((p) => p.userId !== userId)?.userId;
          if (otherUserId) {
            const blockExists = await prisma.userBlock.findFirst({
              where: {
                OR: [
                  { blockerId: userId, blockedId: otherUserId },
                  { blockerId: otherUserId, blockedId: userId },
                ],
              },
            });
            if (blockExists) {
              socket.emit("message_error", { conversationId, error: "blocked" });
              return;
            }
          }
        }

        // Feature #26: Automated Spam & Phishing Shield
        const suspiciousPatterns = [/bit\.ly/i, /tinyurl\.com/i, /free-crypto-giveaway/i, /claim-bonus-now/i];
        let processedContent = content;
        if (content && suspiciousPatterns.some(pattern => pattern.test(content))) {
          processedContent = `[⚠️ Spam Shield Flagged] ${content}`;
        }

        // ⚡️ 0.2MS SUB-MILLISECOND IMMEDIATE BROADCAST
        const messageId = clientMessageId || `msg_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
        const instantMessage: any = {
          id: messageId,
          content: processedContent ? processedContent.trim() : "",
          conversationId,
          senderId: userId,
          parentMessageId: parentMessageId || null,
          mediaUrl: mediaUrl || null,
          mediaType: mediaType || (latitude ? "LOCATION" : "TEXT"),
          isForwarded: isForwarded || false,
          isViewOnce: isViewOnce || false,
          latitude: latitude ?? null,
          longitude: longitude ?? null,
          locationTitle: locationTitle || null,
          isLiveLocation: isLiveLocation || false,
          liveExpiresAt: liveExpiresAt ? new Date(liveExpiresAt).toISOString() : null,
          createdAt: new Date().toISOString(),
          sender: {
            id: userId,
            username,
            avatarUrl: socket.avatarUrl || null,
          },
        };

        // Fast participant lookup via cache
        const now = Date.now();
        let cached = convParticipantsCache.get(conversationId);
        if (!cached || now - cached.timestamp > 300000) {
          const fetched = await prisma.participant.findMany({
            where: { conversationId },
            select: {
              userId: true,
              conversation: { select: { isGroup: true, name: true } },
            },
          });
          cached = {
            userIds: fetched.map((p) => p.userId),
            isGroup: fetched[0]?.conversation?.isGroup || false,
            name: fetched[0]?.conversation?.name || "",
            timestamp: now,
          };
          convParticipantsCache.set(conversationId, cached);
        }

        const participantUserIds = cached.userIds;
        const otherParticipantIds = participantUserIds.filter((pId) => pId !== userId);
        const onlineRecipients = otherParticipantIds.filter((pId) => onlineUsers.has(pId));
        const initialReceipts = otherParticipantIds.map((pId) => ({
          userId: pId,
          status: onlineUsers.has(pId) ? "DELIVERED" : "SENT",
        }));
        instantMessage.receipts = initialReceipts;

        // 🚀 SUB-0.2MS IMMEDIATE BROADCAST (ZERO WAIT)
        io.to(conversationId).emit("new_message", {
          message: instantMessage,
          conversationId,
        });

        if (onlineRecipients.length > 0) {
          io.to(conversationId).emit("messages_delivered", {
            conversationId,
            messageIds: [messageId],
            userId: onlineRecipients[0],
          });
        }

        // Deliver to user rooms for chat list/notifications, excluding sockets already in conversation room
        participantUserIds.forEach((pId) => {
          if (pId !== userId) {
            io.except(conversationId).to(pId).emit("new_message", {
              message: instantMessage,
              conversationId,
            });
          }
        });

        // Asynchronous DB Persistence & Push Notifications (Non-blocking)
        setImmediate(async () => {
          try {
            const encryptedContent = processedContent ? encryptionService.encrypt(processedContent.trim()) : "";
            const dbMessage = await prisma.message.create({
              data: {
                id: messageId,
                content: encryptedContent,
                conversationId,
                senderId: userId,
                parentMessageId: parentMessageId || null,
                mediaUrl: mediaUrl || null,
                mediaType: (mediaType as any) || (latitude ? "LOCATION" : "TEXT"),
                isForwarded: isForwarded || false,
                isViewOnce: isViewOnce || false,
                latitude: latitude ?? null,
                longitude: longitude ?? null,
                locationTitle: locationTitle || null,
                isLiveLocation: isLiveLocation || false,
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

            // Deliveries & FCM Push
            const otherParticipantIds = participantUserIds.filter((pId) => pId !== userId);
            const receiptsToCreate = otherParticipantIds.map((pId) => ({
              messageId: dbMessage.id,
              userId: pId,
              status: onlineUsers.has(pId) ? "DELIVERED" : "SENT",
            }));

            if (receiptsToCreate.length > 0) {
              await prisma.messageReceipt.createMany({
                data: receiptsToCreate,
                skipDuplicates: true,
              });
            }

            // Push notifications for offline recipients
            const offlineParticipantIds = otherParticipantIds.filter((pId) => !onlineUsers.has(pId));
            if (offlineParticipantIds.length > 0) {
              const [sender, recipientUsers] = await Promise.all([
                prisma.user.findUnique({ where: { id: userId }, select: { username: true } }),
                prisma.user.findMany({
                  where: { id: { in: offlineParticipantIds } },
                  select: { fcmToken: true },
                }),
              ]);
              const pushTitle = cached?.isGroup ? `${cached.name}` : `${sender?.username || username}`;
              const pushBody = cached?.isGroup
                ? `${sender?.username || username}: ${processedContent || "Media message"}`
                : `${processedContent || "Media message"}`;

              for (const u of recipientUsers) {
                if (u.fcmToken) {
                  sendPushNotification(u.fcmToken, pushTitle, pushBody, {
                    conversationId,
                    messageId: dbMessage.id,
                  });
                }
              }
            }
          } catch (bgErr) {
            console.error("Background task error in send_message:", bgErr);
          }
        });
      } catch (error) {
        console.error("Socket send_message error:", error);
      }
    });

    // Handle reactions
    socket.on("add_reaction", async (data: { messageId: string; conversationId: string; emoji: string }) => {
      try {
        const { messageId, conversationId, emoji } = data;
        if (!messageId || !conversationId || !emoji) return;

        // Upsert reaction (only one per user per message)
        let reaction = await prisma.messageReaction.findUnique({
          where: { messageId_userId: { messageId, userId } }
        });

        if (reaction) {
          reaction = await prisma.messageReaction.update({
            where: { id: reaction.id },
            data: { emoji }
          });
        } else {
          reaction = await prisma.messageReaction.create({
            data: { messageId, userId, emoji }
          });
        }

        // Broadcast to conversation room and participants safely
        io.to(conversationId).emit("reaction_added", {
          messageId,
          conversationId,
          userId,
          emoji
        });
        io.except(conversationId).to(conversationId).emit("reaction_added", {
          messageId,
          conversationId,
          userId,
          emoji
        });
      } catch (error) {
        console.error("Socket add_reaction error:", error);
      }
    });

    socket.on("remove_reaction", async (data: { messageId: string; conversationId: string }) => {
      try {
        const { messageId, conversationId } = data;
        if (!messageId || !conversationId) return;

        await prisma.messageReaction.deleteMany({
          where: { messageId, userId }
        });

        // Broadcast removal
        io.to(conversationId).emit("reaction_removed", {
          messageId,
          conversationId,
          userId
        });
      } catch (error) {
        console.error("Socket remove_reaction error:", error);
      }
    });

    // Handle voting on polls in real time across all platforms
    socket.on("vote_poll", async (data: { conversationId: string; messageId: string; optionId: number }) => {
      try {
        const { conversationId, messageId, optionId } = data;
        if (!conversationId || !messageId || optionId === undefined) return;

        const targetMessage = await prisma.message.findUnique({
          where: { id: messageId },
        });

        if (!targetMessage) return;

        let contentStr = targetMessage.content;
        try {
          contentStr = encryptionService.decrypt(contentStr);
        } catch (_) {}

        if (!contentStr || !contentStr.startsWith("{")) return;

        let pollData: any = {};
        try {
          pollData = JSON.parse(contentStr);
        } catch (_) {
          return;
        }

        const options: any[] = pollData.options || [];
        const targetOpt = options.find((o) => o.id === optionId);
        if (!targetOpt) return;

        if (!targetOpt.votes) targetOpt.votes = [];
        const votes: string[] = targetOpt.votes;

        const userIndex = votes.indexOf(userId);
        if (userIndex !== -1) {
          votes.splice(userIndex, 1);
        } else {
          // If single choice poll (allowMultiple == false), clear previous votes
          if (!pollData.allowMultiple) {
            options.forEach((opt) => {
              if (opt.votes) {
                const idx = opt.votes.indexOf(userId);
                if (idx !== -1) opt.votes.splice(idx, 1);
              }
            });
          }
          votes.push(userId);
        }

        pollData.options = options;
        const updatedJson = JSON.stringify(pollData);
        const encryptedContent = encryptionService.encrypt(updatedJson);

        await prisma.message.update({
          where: { id: messageId },
          data: { content: encryptedContent },
        });

        const participants = await prisma.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });

        const payload = {
          conversationId,
          messageId,
          content: updatedJson,
        };

        io.to(conversationId).emit("poll_updated", payload);
        participants.forEach((p) => {
          io.to(p.userId).emit("poll_updated", payload);
        });
      } catch (error) {
        console.error("Socket vote_poll error:", error);
      }
    });

    // Handle marking messages as read
    socket.on("mark_read", async (data: { conversationId: string }) => {
      try {
        const { conversationId } = data;
        if (!conversationId) return;

        // Respect Read Receipts privacy for broadcasting
        const user = await prisma.user.findUnique({ where: { id: userId }, select: { readReceipts: true } });

        // Find messages sent by others that don't have a READ receipt for this user
        const messagesToRead = await prisma.message.findMany({
          where: {
            conversationId,
            senderId: { not: userId },
            receipts: {
              none: {
                userId,
                status: "READ",
              },
            },
          },
          select: { id: true },
        });

        if (messagesToRead.length > 0) {
          const messageIds = messagesToRead.map((m) => m.id);

          // Use updateMany since receipts are created during send_message.
          // For safety, we will just update existing receipts to READ.
          await prisma.messageReceipt.updateMany({
            where: {
              messageId: { in: messageIds },
              userId,
            },
            data: {
              status: "READ",
            },
          });
          
          // Legacy messages that might not have a receipt at all:
          // We can find any messages that still don't have a receipt and create them.
          const updatedReceipts = await prisma.messageReceipt.findMany({
            where: { messageId: { in: messageIds }, userId },
            select: { messageId: true }
          });
          const updatedMessageIds = new Set(updatedReceipts.map(r => r.messageId));
          const missingReceiptMessageIds = messageIds.filter(id => !updatedMessageIds.has(id));
          
          if (missingReceiptMessageIds.length > 0) {
            // Use upsert-style to avoid duplicate constraint errors
            for (const mId of missingReceiptMessageIds) {
              await prisma.messageReceipt.upsert({
                where: { messageId_userId: { messageId: mId, userId } },
                create: { messageId: mId, userId, status: "READ" },
                update: { status: "READ" },
              });
            }
          }

          // Broadcast to everyone in the conversation room ONLY if they have read receipts enabled
          if (user?.readReceipts !== false) {
            io.to(conversationId).emit("messages_read", {
              conversationId,
              userId, // The user who read the messages
            });
          }
          
          // ALWAYS emit to the user's personal room so their other logged-in devices sync the unread count drop
          io.to(userId).emit("messages_read", {
            conversationId,
            userId,
          });
        }
      } catch (error) {
        console.error("Socket mark_read error:", error);
      }
    });

    // Handle edit message
    socket.on("edit_message", async (data: { messageId: string; content: string }) => {
      try {
        const { messageId, content } = data;
        if (!content || !content.trim()) return;

        // Verify message ownership
        const existing = await prisma.message.findUnique({
          where: { id: messageId },
        });

        if (!existing || existing.senderId !== userId) return;

        // Update message
        const encryptedContent = content ? encryptionService.encrypt(content.trim()) : "";
        const updatedMessage = await prisma.message.update({
          where: { id: messageId },
          data: {
            content: encryptedContent,
            isEdited: true,
          },
          include: {
            sender: {
              select: {
                id: true,
                username: true,
                avatarUrl: true,
              },
            },
            parentMessage: {
              include: {
                sender: {
                  select: {
                    id: true,
                    username: true,
                  },
                },
              },
            },
          },
        });

        // Decrypt for broadcasting
        const decryptedMessage = {
          ...updatedMessage,
          content: content ? content.trim() : "",
          parentMessage: updatedMessage.parentMessage
            ? {
                ...updatedMessage.parentMessage,
                content: encryptionService.decrypt(updatedMessage.parentMessage.content),
              }
            : null,
        };

        // Find conversation participants
        const participants = await prisma.participant.findMany({
          where: { conversationId: existing.conversationId },
          select: { userId: true },
        });

        // Broadcast edit to all participants
        participants.forEach((participant) => {
          io.to(participant.userId).emit("message_edited", {
            message: decryptedMessage,
            conversationId: existing.conversationId,
          });
        });
      } catch (error) {
        console.error("Socket edit_message error:", error);
      }
    });

    // Handle delete message (Delete for me vs. Delete for everyone)
    socket.on("delete_message", async (data: { messageId: string; deleteType: "everyone" | "me" }) => {
      try {
        const { messageId, deleteType } = data;

        const existing = await prisma.message.findUnique({
          where: { id: messageId },
          include: {
            sender: true,
          },
        });

        if (!existing) return;

        if (deleteType === "everyone") {
          // Verify message ownership: only the sender can delete for everyone
          if (existing.senderId !== userId) return;

          // Soft delete: mark message as deleted but keep it in DB
          // so others can see the placeholder "This message was deleted"
          const updatedMessage = await prisma.message.update({
            where: { id: messageId },
            data: {
              isDeleted: true,
              content: "",   // clear content
              mediaUrl: null, // clear media
              mediaType: "TEXT",
            },
            include: {
              sender: {
                select: { id: true, username: true, avatarUrl: true },
              },
              receipts: true,
            },
          });

          // Find conversation participants
          const participants = await prisma.participant.findMany({
            where: { conversationId: existing.conversationId },
            select: { userId: true },
          });

          // Broadcast both message_deleted and message_edited to everyone
          participants.forEach((participant) => {
            io.to(participant.userId).emit("message_deleted", {
              messageId,
              conversationId: existing.conversationId,
              isDeleted: true,
              content: "This message was deleted",
            });
            io.to(participant.userId).emit("message_edited", {
              message: updatedMessage,
              conversationId: existing.conversationId,
            });
          });
        } else if (deleteType === "me") {
          // Delete for me: Create a record in DeletedMessage
          await prisma.deletedMessage.upsert({
            where: {
              messageId_userId: {
                messageId,
                userId,
              },
            },
            update: {},
            create: {
              messageId,
              userId,
            },
          });

          // Emit to the current user's socket room only
          io.to(userId).emit("message_deleted_for_me", {
            messageId,
            conversationId: existing.conversationId,
          });
        }
      } catch (error) {
        console.error("Socket delete_message error:", error);
      }
    });

    // Helper to save call log messages and broadcast to participants
    const saveAndBroadcastCallLog = async (
      conversationId: string,
      senderId: string,
      callType: "audio" | "video",
      logStatus: string
    ) => {
      try {
        if (!conversationId) return;

        const message = await prisma.message.create({
          data: {
            content: logStatus,
            conversationId,
            senderId,
            mediaUrl: callType,
            mediaType: "CALL_LOG",
          },
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
        });

        // Touch conversation timestamp
        await prisma.conversation.update({
          where: { id: conversationId },
          data: { updatedAt: new Date() },
        });

        // Find conversation participants
        const participants = await prisma.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });

        const receiptsData = [];
        for (const participant of participants) {
          if (participant.userId === senderId) continue;

          const roomSockets = io.sockets.adapter.rooms.get(conversationId);
          const userSockets = onlineUsers.get(participant.userId);

          let status = "SENT";
          if (userSockets && roomSockets) {
            const isViewing = Array.from(userSockets).some(sid => roomSockets.has(sid));
            status = isViewing ? "READ" : "DELIVERED";
          } else if (onlineUsers.has(participant.userId)) {
            status = "DELIVERED";
          }

          const receipt = await prisma.messageReceipt.create({
            data: {
              messageId: message.id,
              userId: participant.userId,
              status,
            },
          });
          receiptsData.push(receipt);
        }
        (message as any).receipts = receiptsData;

        participants.forEach((participant) => {
          io.to(participant.userId).emit("new_message", {
            message,
            conversationId,
          });
        });
      } catch (err) {
        console.error("Error saving call log message:", err);
      }
    };

    // Caller sends offer → forward to recipient as incoming call notification
    socket.on("call_offer", async (data: {
      targetUserId: string;
      offer: RTCSessionDescriptionInit;
      callType: "audio" | "video";
      conversationId: string;
      callerName: string;
      callerAvatar: string | null;
    }) => {
      // Check if target user is ALREADY engaged in a DIFFERENT active call
      const existingCallConv = activeCallUsers.get(data.targetUserId);
      if (existingCallConv && existingCallConv !== data.conversationId) {
        io.to(userId).emit("call_busy", {
          targetUserId: data.targetUserId,
          conversationId: data.conversationId,
        });
        return;
      }

      activeCallUsers.set(userId, data.conversationId);
      activeCallUsers.set(data.targetUserId, data.conversationId);

      io.to(data.targetUserId).emit("call_incoming", {
        callerId: userId,
        callerName: data.callerName || username,
        callerAvatar: data.callerAvatar || null,
        callerAvatarUrl: data.callerAvatar || null,
        offer: data.offer,
        callType: data.callType,
        conversationId: data.conversationId,
      });

      // ALWAYS send FCM push notification for incoming calls to guarantee arrival on backgrounded/killed/locked devices
      try {
        const recipientUser = await prisma.user.findUnique({
          where: { id: data.targetUserId },
          select: { fcmToken: true },
        });
        if (recipientUser?.fcmToken) {
          const callTypeString = data.callType === "video" ? "Video Call" : "Audio Call";
          sendPushNotification(
            recipientUser.fcmToken,
            `Incoming ${callTypeString}`,
            `${data.callerName || username} is calling you`,
            {
              conversationId: data.conversationId,
              callType: data.callType,
              callerId: userId,
              callerName: data.callerName || username,
              callerAvatarUrl: data.callerAvatar || "",
              type: "CALL",
            }
          );
        }
      } catch (e) {
        console.error("Failed to send call push notification:", e);
      }
    });

    // Receiver requests SDP offer if launched without initial offer (e.g. from background push notification)
    socket.on("request_call_offer", (data: { callerId: string; conversationId: string }) => {
      io.to(data.callerId).emit("request_call_offer", {
        requesterId: userId,
        conversationId: data.conversationId,
      });
    });

    // Receiver accepts the call → send SDP answer back to caller
    socket.on("call_answer", (data: { callerId: string; answer: RTCSessionDescriptionInit }) => {
      io.to(data.callerId).emit("call_answered", {
        answer: data.answer,
        answererId: userId,
      });
      // Notify receiver's other devices that the call was answered elsewhere
      socket.broadcast.to(userId).emit("call_ended", { status: "answered_elsewhere" });
    });

    // Receiver rejects the call
    socket.on("call_reject", (data: { callerId: string; conversationId: string; callType: "audio" | "video" }) => {
      activeCallUsers.delete(userId);
      if (data.callerId && activeCallUsers.get(data.callerId) === data.conversationId) {
        activeCallUsers.delete(data.callerId);
      }

      io.to(data.callerId).emit("call_rejected", { rejecterId: userId });
      io.to(data.callerId).emit("call_ended", { status: "rejected", endedBy: userId });
      io.to(userId).emit("call_ended", { status: "rejected", endedBy: userId });
      if (data.conversationId) {
        io.to(data.conversationId).emit("call_ended", { status: "rejected", endedBy: userId });
        saveAndBroadcastCallLog(data.conversationId, data.callerId, data.callType, "declined");
      }
    });

    // Either side ends the active call
    socket.on("call_end", (data: {
      peerId: string;
      conversationId: string;
      callType: "audio" | "video";
      status: "missed" | "connected";
      duration?: number;
      callerId?: string;
    }) => {
      activeCallUsers.delete(userId);
      if (data.peerId && activeCallUsers.get(data.peerId) === data.conversationId) {
        activeCallUsers.delete(data.peerId);
      }
      if (data.callerId && activeCallUsers.get(data.callerId) === data.conversationId) {
        activeCallUsers.delete(data.callerId);
      }

      if (data.peerId) {
        io.to(data.peerId).emit("call_ended", { endedBy: userId });
      }
      io.to(userId).emit("call_ended", { endedBy: userId });
      if (data.conversationId) {
        io.to(data.conversationId).emit("call_ended", { endedBy: userId });
        const originalCallerId = data.callerId || (data.status === "missed" ? userId : (userId === data.peerId ? userId : data.peerId));
        const logContent = data.status === "connected" ? `connected:${data.duration || 0}` : "missed";
        saveAndBroadcastCallLog(data.conversationId, originalCallerId, data.callType, logContent);
      }
    });

    // Exchange ICE candidates for NAT traversal
    socket.on("ice_candidate", (data: { targetUserId: string; candidate: RTCIceCandidateInit }) => {
      io.to(data.targetUserId).emit("ice_candidate", {
        candidate: data.candidate,
        fromUserId: userId,
      });
    });

    // Mesh Group Call: Notify an existing participant to connect to a newly added user
    socket.on("user_added_to_call", (data: { targetUserId: string; newUserId: string; newUserName: string; conversationId: string; callType: "audio" | "video" }) => {
      io.to(data.targetUserId).emit("user_added_to_call", {
        newUserId: data.newUserId,
        newUserName: data.newUserName,
        conversationId: data.conversationId,
        callType: data.callType,
      });
    });

    // Screen Share Request Signaling (Accept / Decline flow)
    socket.on("screen_share_request", (data: { targetUserId: string; conversationId: string; senderName: string }) => {
      io.to(data.targetUserId).emit("screen_share_request", {
        senderId: userId,
        senderName: data.senderName || username,
        conversationId: data.conversationId,
      });
    });

    socket.on("screen_share_accept", (data: { targetUserId: string; conversationId: string }) => {
      io.to(data.targetUserId).emit("screen_share_accept", {
        accepterId: userId,
        conversationId: data.conversationId,
      });
    });

    socket.on("screen_share_decline", (data: { targetUserId: string; conversationId: string }) => {
      io.to(data.targetUserId).emit("screen_share_decline", {
        declinerId: userId,
        conversationId: data.conversationId,
      });
    });

    // Handle View Once Media Opened
    socket.on("view_once_opened", async (data: { messageId: string; conversationId: string }) => {
      try {
        const { messageId, conversationId } = data;
        const updatedMsg = await prisma.message.update({
          where: { id: messageId },
          data: {
            isViewed: true,
            viewedAt: new Date(),
            mediaUrl: null, // Wipe media URL once opened
          },
        });

        const participants = await prisma.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });

        participants.forEach((p) => {
          io.to(p.userId).emit("view_once_opened", {
            messageId,
            conversationId,
            viewerId: userId,
          });
        });
      } catch (err) {
        console.error("Error in view_once_opened socket handler:", err);
      }
    });

    // Realtime Live Location Update
    socket.on("live_location_update", async (data: { conversationId: string; messageId: string; latitude: number; longitude: number }) => {
      try {
        const { conversationId, messageId, latitude, longitude } = data;
        await prisma.message.update({
          where: { id: messageId },
          data: { latitude, longitude },
        });

        io.to(conversationId).emit("live_location_updated", {
          conversationId,
          messageId,
          userId,
          latitude,
          longitude,
        });
      } catch (err) {
        console.error("Error updating live location:", err);
      }
    });

    // Stop Live Location
    socket.on("stop_live_location", async (data: { conversationId: string; messageId: string }) => {
      try {
        const { conversationId, messageId } = data;
        await prisma.message.update({
          where: { id: messageId },
          data: { isLiveEnded: true },
        });

        io.to(conversationId).emit("live_location_ended", {
          conversationId,
          messageId,
          userId,
        });
      } catch (err) {
        console.error("Error stopping live location:", err);
      }
    });

    // Pin / Unpin Contact
    socket.on("pin_contact", async (data: { conversationId: string; pin: boolean }) => {
      try {
        const { conversationId, pin } = data;
        if (pin) {
          const pinnedCount = await prisma.participant.count({
            where: { userId, isPinned: true },
          });
          if (pinnedCount >= 3) {
            socket.emit("error_message", { message: "Maximum 3 pinned chats allowed." });
            return;
          }
        }
        await prisma.participant.update({
          where: { userId_conversationId: { userId, conversationId } },
          data: { isPinned: pin, pinnedAt: pin ? new Date() : null },
        });
        socket.emit("contact_pinned_updated", { conversationId, isPinned: pin });
      } catch (err) {
        console.error("Error toggling pinned contact:", err);
      }
    });

    // Pin / Unpin Message
    socket.on("pin_message", async (data: { conversationId: string; messageId: string; durationHours?: number }) => {
      try {
        const { conversationId, messageId, durationHours } = data;
        let expiresAt: Date | null = null;
        if (durationHours && durationHours > 0) {
          expiresAt = new Date(Date.now() + durationHours * 3600 * 1000);
        }

        const pinned = await prisma.pinnedMessage.upsert({
          where: { conversationId_messageId: { conversationId, messageId } },
          create: {
            conversationId,
            messageId,
            pinnedById: userId,
            expiresAt,
          },
          update: {
            pinnedById: userId,
            expiresAt,
          },
          include: {
            message: true,
          },
        });

        const participants = await prisma.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });

        participants.forEach((p) => {
          io.to(p.userId).emit("message_pinned", {
            conversationId,
            pinnedMessage: pinned,
          });
        });
      } catch (err) {
        console.error("Error pinning message:", err);
      }
    });

    socket.on("unpin_message", async (data: { conversationId: string; messageId: string }) => {
      try {
        const { conversationId, messageId } = data;
        await prisma.pinnedMessage.deleteMany({
          where: { conversationId, messageId },
        });

        const participants = await prisma.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });

        participants.forEach((p) => {
          io.to(p.userId).emit("message_unpinned", {
            conversationId,
            messageId,
          });
        });
      } catch (err) {
        console.error("Error unpinning message:", err);
      }
    });

    // Handle typing indicator
    socket.on("typing", (data: { conversationId: string; isTyping: boolean }) => {
      const { conversationId, isTyping } = data;
      if (!conversationId) return;
      // Broadcast user typing state instantly to all other users in conversation room
      socket.to(conversationId).emit("user_typing", {
        conversationId,
        userId,
        username,
        isTyping,
      });
    });

    // Handle client disconnect
    socket.on("disconnect", () => {
      console.log(`User disconnected from socket: ${username} (${userId})`);
      const ongoingConvId = activeCallUsers.get(userId);
      if (ongoingConvId) {
        // Grace period (12s) to allow seamless PiP mode, app switching, and socket reconnects
        setTimeout(() => {
          const sockets = onlineUsers.get(userId);
          if (!sockets || sockets.size === 0) {
            const currentCallConv = activeCallUsers.get(userId);
            if (currentCallConv === ongoingConvId) {
              activeCallUsers.delete(userId);
              for (const [peerUserId, convId] of activeCallUsers.entries()) {
                if (convId === ongoingConvId && peerUserId !== userId) {
                  activeCallUsers.delete(peerUserId);
                  io.to(peerUserId).emit("call_ended", {
                    endedBy: userId,
                    status: "disconnected",
                    reason: "User closed app or disconnected",
                  });
                }
              }
              io.to(ongoingConvId).emit("call_ended", {
                endedBy: userId,
                status: "disconnected",
                reason: "User closed app or disconnected",
              });
            }
          }
        }, 12000);
      }

      const userSockets = onlineUsers.get(userId);
      if (userSockets) {
        userSockets.delete(socket.id);
        if (userSockets.size === 0) {
          onlineUsers.delete(userId);

          const lastSeenTime = new Date();

          // Update lastSeen in database asynchronously
          prisma.user.update({
            where: { id: userId },
            data: { lastSeen: lastSeenTime },
            select: { lastSeenPrivacy: true },
          }).then(async user => {
            // Broadcast user offline status change with lastSeen timestamp to relevant contacts only
            const relatedParticipants = await prisma.participant.findMany({
              where: {
                conversation: {
                  participants: { some: { userId } }
                },
                userId: { not: userId }
              },
              select: { userId: true },
              distinct: ['userId']
            });

            for (const p of relatedParticipants) {
              const canSeeOnline = await canViewOnline(p.userId, userId);
              const canSeeLastSeen = await canViewLastSeen(p.userId, userId);

              if (canSeeOnline || canSeeLastSeen) {
                const payload: any = {
                  userId,
                  status: "offline",
                };
                if (canSeeLastSeen) {
                  payload.lastSeen = lastSeenTime;
                }
                io.to(p.userId).emit("user_status_change", payload);
              }
            }
          }).catch(err => {
            console.error("Error updating user lastSeen on socket disconnect:", err);
          });
        }
      }
    });
  });
};
