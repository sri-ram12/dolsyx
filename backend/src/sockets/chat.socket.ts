import { Server } from "socket.io";
import jwt from "jsonwebtoken";
import { prisma } from "../config/db.js";
import { encryptionService } from "../services/encryption.service.js";

const JWT_SECRET = process.env.JWT_SECRET || "dolsyx_super_secret_key_123456";

// Map to track online users: userId -> Set of socket.id (supports multiple client connections)
const onlineUsers = new Map<string, Set<string>>();

export const initChatSocket = (io: Server) => {
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

    // Fetch privacy settings and relevant contacts
    prisma.user.findUnique({ where: { id: userId }, select: { lastSeenPrivacy: true } }).then(async user => {
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
      socket.emit("online_users_list", onlineContacts);

      if (user?.lastSeenPrivacy === 'PUBLIC' || user?.lastSeenPrivacy === 'CONTACTS') {
        const payload = {
          userId,
          status: "online",
        };

        // Broadcast user online status change ONLY to relevant contacts
        relatedParticipants.forEach(p => {
          io.to(p.userId).emit("user_status_change", payload);
        });
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

    // Handle real-time messaging
    socket.on("send_message", async (data: { conversationId: string; content: string; parentMessageId?: string; mediaUrl?: string; mediaType?: string; isForwarded?: boolean }) => {
      try {
        const { conversationId, content, parentMessageId, mediaUrl, mediaType, isForwarded } = data;

        // Allow empty content for media messages
        if (!mediaUrl && (!content || !content.trim())) return;

        // Find conversation participants first (needed for block check)
        const participants = await prisma.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });

        // Check if either user has blocked the other
        const recipientIds = participants.filter(p => p.userId !== userId).map(p => p.userId);
        if (recipientIds.length > 0) {
          const blocks = await (prisma as any).userBlock.findMany({
            where: {
              OR: [
                { blockerId: userId, blockedId: { in: recipientIds } },
                { blockerId: { in: recipientIds }, blockedId: userId }
              ]
            }
          });
          if (blocks.length > 0) {
            console.log(`Message blocked between ${userId} and recipients`);
            return;
          }
        }
        // Save message to database with encrypted content
        const encryptedContent = content ? encryptionService.encrypt(content.trim()) : "";
        const message = await prisma.message.create({
          data: {
            content: encryptedContent,
            conversationId,
            senderId: userId,
            parentMessageId: parentMessageId || null,
            mediaUrl: mediaUrl || null,
            mediaType: (mediaType as any) || "TEXT",
            isForwarded: isForwarded || false,
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
            receipts: true,
          },
        });

        // Decrypt the message content for broadcasting
        const decryptedMessage = {
          ...message,
          content: content ? content.trim() : "",
          parentMessage: message.parentMessage
            ? {
                ...message.parentMessage,
                content: encryptionService.decrypt(message.parentMessage.content),
              }
            : null,
        };

        // Touch conversation timestamp
        await prisma.conversation.update({
          where: { id: conversationId },
          data: { updatedAt: new Date() },
        });

        // Create Message Receipts for all other participants (participants already fetched above)

        // Create Message Receipts for all other participants
        const receiptsData = [];
        for (const participant of participants) {
          if (participant.userId === userId) continue;

          const roomSockets = io.sockets.adapter.rooms.get(conversationId);
          const userSockets = onlineUsers.get(participant.userId);
          
          let status = onlineUsers.has(participant.userId) ? "DELIVERED" : "SENT";

          const receipt = await prisma.messageReceipt.create({
            data: {
              messageId: message.id,
              userId: participant.userId,
              status,
            },
          });
          receiptsData.push(receipt);
        }
        (decryptedMessage as any).receipts = receiptsData;

        // Broadcast to all participants using their personal user rooms
        participants.forEach((participant) => {
          io.to(participant.userId).emit("new_message", {
            message: decryptedMessage,
            conversationId,
          });
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

        // Broadcast to all participants in conversation
        const participants = await prisma.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });

        participants.forEach((participant) => {
          io.to(participant.userId).emit("reaction_added", {
            messageId,
            conversationId,
            userId,
            emoji
          });
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
        const participants = await prisma.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });

        participants.forEach((participant) => {
          io.to(participant.userId).emit("reaction_removed", {
            messageId,
            conversationId,
            userId
          });
        });
      } catch (error) {
        console.error("Socket remove_reaction error:", error);
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

          // Broadcast the updated soft-deleted message to everyone
          participants.forEach((participant) => {
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
    socket.on("call_offer", (data: {
      targetUserId: string;
      offer: RTCSessionDescriptionInit;
      callType: "audio" | "video";
      conversationId: string;
      callerName: string;
      callerAvatar: string | null;
    }) => {
      io.to(data.targetUserId).emit("call_incoming", {
        callerId: userId,
        callerName: data.callerName || username,
        callerAvatar: data.callerAvatar || null,
        callerAvatarUrl: data.callerAvatar || null,
        offer: data.offer,
        callType: data.callType,
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
      io.to(data.callerId).emit("call_rejected", { rejecterId: userId });
      // Notify receiver's other devices that the call was handled
      socket.broadcast.to(userId).emit("call_ended", { status: "answered_elsewhere" });
      if (data.conversationId) {
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
      io.to(data.peerId).emit("call_ended", { endedBy: userId });
      // Also notify the sender's other devices to stop ringing/call UI
      socket.broadcast.to(userId).emit("call_ended", { endedBy: userId });
      if (data.conversationId) {
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

    // Handle typing indicator

    socket.on("typing", async (data: { conversationId: string; isTyping: boolean }) => {
      const { conversationId, isTyping } = data;
      // Broadcast user typing state to other users inside the conversation room
      socket.to(conversationId).emit("user_typing", {
        conversationId,
        userId,
        username,
        isTyping,
      });

      try {
        const participants = await prisma.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });
        participants.forEach((p) => {
          if (p.userId !== userId) {
            io.to(p.userId).emit("user_typing", {
              conversationId,
              userId,
              username,
              isTyping,
            });
          }
        });
      } catch (err) {
        console.error("Error broadcasting typing to participants:", err);
      }
    });

    // Handle client disconnect
    socket.on("disconnect", () => {
      console.log(`User disconnected from socket: ${username} (${userId})`);

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
            if (user?.lastSeenPrivacy === 'PUBLIC' || user?.lastSeenPrivacy === 'CONTACTS') {
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

              const payload = {
                userId,
                status: "offline",
                lastSeen: lastSeenTime,
              };

              relatedParticipants.forEach(p => {
                io.to(p.userId).emit("user_status_change", payload);
              });
            }
          }).catch(err => {
            console.error("Error updating user lastSeen on socket disconnect:", err);
          });
        }
      }
    });
  });
};
