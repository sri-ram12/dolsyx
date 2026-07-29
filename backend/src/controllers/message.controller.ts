import type { Response } from 'express';
import { prisma } from '../config/db.js';
import type { AuthRequest } from '../middleware/auth.middleware.js';

export const sendEncryptedMessage = async (req: AuthRequest, res: Response) => {
  try {
    const senderUserId = req.user!.id;
    const { senderDeviceId, recipients, conversationId } = req.body;

    if (!senderDeviceId || !Array.isArray(recipients) || !conversationId) {
      return res.status(400).json({ error: 'Invalid payload format' });
    }

    // Verify sender device belongs to sender
    const senderDevice = await prisma.device.findUnique({
      where: {
        userId_deviceId: { userId: senderUserId, deviceId: senderDeviceId }
      }
    });

    if (!senderDevice) {
      return res.status(403).json({ error: 'Sender device not found' });
    }

    const messagesToCreate = [];
    const pushTargets = new Set<string>();

    for (const recipient of recipients) {
      const { recipientDeviceId, type, ciphertext, recipientUserId } = recipient;
      
      if (!recipientDeviceId || !type || !ciphertext) {
        continue;
      }

      // Verify recipient device exists
      const recipientDevice = await prisma.device.findUnique({
        where: { id: recipientDeviceId }
      });

      if (recipientDevice) {
        messagesToCreate.push({
          senderDeviceId: senderDevice.id,
          recipientDeviceId: recipientDevice.id,
          type,
          ciphertext,
          delivered: false
        });
        
        // Target user for real-time socket push
        pushTargets.add(recipientDevice.userId);
      }
    }

    if (messagesToCreate.length > 0) {
      await prisma.encryptedMessage.createMany({
        data: messagesToCreate
      });
      
      // Emit socket event to notify recipients that they have new messages to sync
      const io = req.app.get('io');
      if (io) {
        // Find the sender user details to include in the payload
        const sender = await prisma.user.findUnique({
          where: { id: senderUserId },
          select: { id: true, username: true, avatarUrl: true, email: true }
        });

        for (const recipient of recipients) {
          const { recipientDeviceId, type, ciphertext, recipientUserId } = recipient;
          
          if (recipientUserId) {
            io.to(recipientUserId).emit("receive_encrypted_message", {
              conversationId: conversationId,
              message: {
                id: `e2ee-${Date.now()}`,
                content: JSON.stringify({ type, ciphertext }),
                senderId: senderUserId,
                createdAt: new Date().toISOString(),
                mediaType: "TEXT",
                sender: sender
              }
            });
          }
        }
      }
    }

    res.status(200).json({ success: true, count: messagesToCreate.length });
  } catch (error) {
    console.error('Error sending encrypted message:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const syncEncryptedMessages = async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const deviceId = parseInt(req.query.deviceId as string);

    if (isNaN(deviceId)) {
      return res.status(400).json({ error: 'Device ID is required in query params' });
    }

    const device = await prisma.device.findUnique({
      where: {
        userId_deviceId: { userId, deviceId }
      }
    });

    if (!device) {
      return res.status(404).json({ error: 'Device not found' });
    }

    // Fetch undelivered messages for this device
    const messages = await prisma.encryptedMessage.findMany({
      where: {
        recipientDeviceId: device.id,
        delivered: false
      },
      orderBy: {
        timestamp: 'asc'
      },
      include: {
        senderDevice: {
          select: {
            deviceId: true,
            user: {
              select: {
                id: true,
                email: true
              }
            }
          }
        }
      }
    });

    // Mark as delivered
    if (messages.length > 0) {
      await prisma.encryptedMessage.updateMany({
        where: {
          id: { in: messages.map(m => m.id) }
        },
        data: {
          delivered: true
        }
      });
    }

    // Format response
    const formattedMessages = messages.map(m => ({
      id: m.id,
      senderUserId: m.senderDevice?.user.id,
      senderEmail: m.senderDevice?.user.email,
      senderDeviceId: m.senderDevice?.deviceId,
      type: m.type,
      ciphertext: m.ciphertext,
      timestamp: m.timestamp
    }));

    res.status(200).json({ success: true, data: formattedMessages });
  } catch (error) {
    console.error('Error syncing encrypted messages:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
