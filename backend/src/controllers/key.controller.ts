import type { Response } from 'express';
import { prisma } from '../config/db.js';
import type { AuthRequest } from '../middleware/auth.middleware.js';

export const uploadKeys = async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const { deviceId, identityKeyPublic, signedPreKeyPublic, signedPreKeySignature, oneTimePreKeys, replenishOnly } = req.body;

    if (deviceId === undefined || deviceId === null) {
      return res.status(400).json({ error: 'Missing deviceId' });
    }

    const numericDeviceId = Number(deviceId);

    // Handle OPK replenishment only
    if (replenishOnly) {
      if (!Array.isArray(oneTimePreKeys) || oneTimePreKeys.length === 0) {
        return res.status(400).json({ error: 'Missing oneTimePreKeys for replenishment' });
      }

      const device = await prisma.device.findUnique({
        where: {
          userId_deviceId: {
            userId,
            deviceId: numericDeviceId
          }
        }
      });

      if (!device) {
        return res.status(404).json({ error: 'Device not found for replenishment' });
      }

      const preKeysData = oneTimePreKeys.map((k: any) => ({
        deviceId: device.id,
        keyId: Number(k.keyId),
        publicKey: String(k.publicKey)
      }));

      await prisma.oneTimePreKey.createMany({
        data: preKeysData,
        skipDuplicates: true
      });

      return res.status(200).json({ success: true, message: 'PreKeys replenished successfully' });
    }

    if (!identityKeyPublic || !signedPreKeyPublic || !signedPreKeySignature || !oneTimePreKeys) {
      return res.status(400).json({ error: 'Missing required key data' });
    }

    // Create or update the device keys
    const device = await prisma.device.upsert({
      where: {
        userId_deviceId: {
          userId,
          deviceId: numericDeviceId
        }
      },
      update: {
        identityKeyPublic,
        signedPreKeyPublic,
        signedPreKeySignature,
      },
      create: {
        userId,
        deviceId: numericDeviceId,
        identityKeyPublic,
        signedPreKeyPublic,
        signedPreKeySignature,
      }
    });

    // Insert One-Time PreKeys
    if (Array.isArray(oneTimePreKeys) && oneTimePreKeys.length > 0) {
      // Clear existing unused keys for this device to prevent bloat
      await prisma.oneTimePreKey.deleteMany({
        where: { deviceId: device.id }
      });

      const preKeysData = oneTimePreKeys.map((k: any) => ({
        deviceId: device.id,
        keyId: Number(k.keyId),
        publicKey: String(k.publicKey)
      }));

      await prisma.oneTimePreKey.createMany({
        data: preKeysData,
        skipDuplicates: true
      });
    }

    res.status(200).json({ success: true, message: 'Keys uploaded successfully' });
  } catch (error) {
    console.error('Error uploading keys:', error);
    res.status(500).json({ error: 'Failed to upload keys' });
  }
};

export const fetchKeys = async (req: AuthRequest, res: Response) => {
  try {
    const email = req.params.email as string;

    // Find the user by email
    const recipient = await prisma.user.findUnique({
      where: { email: email },
      include: {
        devices: {
          include: {
            oneTimePreKeys: {
              take: 1
            }
          }
        }
      }
    });

    if (!recipient) {
      return res.status(404).json({ error: 'User not found' });
    }

    const recipientWithDevices = recipient as typeof recipient & {
      devices: Array<{
        id: string;
        deviceId: number;
        identityKeyPublic: string;
        signedPreKeyPublic: string;
        signedPreKeySignature: string;
        oneTimePreKeys: Array<{ id: string; keyId: number; publicKey: string }>;
      }>;
    };

    if (recipientWithDevices.devices.length === 0) {
      return res.status(404).json({ error: 'User has no registered devices for E2EE' });
    }

    const deviceKeys = await Promise.all(recipientWithDevices.devices.map(async (device: any) => {
      const opk = device.oneTimePreKeys[0];
      
      // If a pre-key was fetched, delete it so it's only used once
      if (opk) {
        await prisma.oneTimePreKey.delete({
          where: { id: opk.id }
        });
      }

      return {
        deviceId: device.deviceId,
        identityKeyPublic: device.identityKeyPublic,
        signedPreKeyPublic: device.signedPreKeyPublic,
        signedPreKeySignature: device.signedPreKeySignature,
        oneTimePreKey: opk ? {
          keyId: opk.keyId,
          publicKey: opk.publicKey
        } : null
      };
    }));

    res.status(200).json({
      success: true,
      data: {
        userId: recipient.id,
        devices: deviceKeys
      }
    });
  } catch (error) {
    console.error('Error fetching keys:', error);
    res.status(500).json({ error: 'Failed to fetch keys' });
  }
};
