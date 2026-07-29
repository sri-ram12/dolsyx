import type { Response } from 'express';
import { prisma } from '../config/db.js';
import type { AuthRequest } from '../middleware/auth.middleware.js';

/**
 * Save an encrypted backup of the user's local E2EE key state.
 * The backup is encrypted client-side with a key derived from their password (Argon2id).
 * The server never sees the plaintext keys.
 */
export const saveBackup = async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const { encryptedData, salt, nonce } = req.body;

    if (!encryptedData || !salt || !nonce) {
      return res.status(400).json({ error: 'Missing required backup fields: encryptedData, salt, nonce' });
    }

    // Upsert — each user has one backup slot
    await prisma.encryptedBackup.upsert({
      where: {
        id: (await prisma.encryptedBackup.findFirst({ where: { userId } }))?.id ?? ''
      },
      update: {
        encryptedData,
        salt,
        nonce,
        updatedAt: new Date()
      },
      create: {
        userId,
        encryptedData,
        salt,
        nonce
      }
    });

    res.status(200).json({ success: true, message: 'Backup saved successfully' });
  } catch (error) {
    console.error('Error saving backup:', error);
    res.status(500).json({ error: 'Failed to save backup' });
  }
};

/**
 * Retrieve the encrypted backup for the authenticated user.
 * Returns only the encrypted blob — the server has no ability to decrypt it.
 */
export const loadBackup = async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.id;

    const backup = await prisma.encryptedBackup.findFirst({
      where: { userId },
      orderBy: { updatedAt: 'desc' }
    });

    if (!backup) {
      return res.status(404).json({ error: 'No backup found for this user' });
    }

    res.status(200).json({
      success: true,
      data: {
        encryptedData: backup.encryptedData,
        salt: backup.salt,
        nonce: backup.nonce,
        updatedAt: backup.updatedAt
      }
    });
  } catch (error) {
    console.error('Error loading backup:', error);
    res.status(500).json({ error: 'Failed to load backup' });
  }
};
