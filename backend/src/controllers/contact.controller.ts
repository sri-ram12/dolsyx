import type { Response } from "express";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";

import { canViewProfilePhoto, canViewAbout, canViewLastSeen, canViewOnline } from "../utils/privacy.engine.js";

// Search user by email or username (before adding as contact)
export const searchUser = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { query } = req.query as { query: string };

    if (!query || query.trim().length < 2) {
      res.status(400).json({ message: "Search query must be at least 2 characters" });
      return;
    }

    const cleanQuery = query.trim();
    const user = await prisma.user.findFirst({
      where: {
        OR: [
          { email: { equals: cleanQuery, mode: "insensitive" } },
          { username: { equals: cleanQuery, mode: "insensitive" } },
          { email: { contains: cleanQuery, mode: "insensitive" } },
          { username: { contains: cleanQuery, mode: "insensitive" } },
        ],
        NOT: { id: userId },
      },
      select: {
        id: true,
        username: true,
        email: true,
        avatarUrl: true,
        bio: true,
        statusMessage: true,
        isOnline: true,
        lastSeen: true,
      },
    });

    if (!user) {
      res.status(404).json({ message: "No user found with that username or email" });
      return;
    }

    // Apply Privacy Engine Filtering
    const [canViewPhoto, canViewBio, canSeeLastSeen, canSeeOnline] = await Promise.all([
      canViewProfilePhoto(userId, user.id),
      canViewAbout(userId, user.id),
      canViewLastSeen(userId, user.id),
      canViewOnline(userId, user.id),
    ]);

    if (!canViewPhoto) user.avatarUrl = null;
    if (!canViewBio) {
      user.bio = null;
      user.statusMessage = null;
    }
    if (!canSeeLastSeen) user.lastSeen = null;
    if (!canSeeOnline) user.isOnline = false;

    // Check if already saved as contact
    const existing = await prisma.contact.findUnique({
      where: { userId_contactId: { userId, contactId: user.id } },
    });

    res.status(200).json({ ...user, alreadySaved: !!existing });
  } catch (error) {
    console.error("Search user error:", error);
    res.status(500).json({ message: "Search failed" });
  }
};

// Add / save a contact by email or username
export const addContact = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { query, savedName } = req.body; // query = email or username

    if (!query) {
      res.status(400).json({ message: "Email or username is required" });
      return;
    }

    const cleanQuery = query.trim();
    const contactUser = await prisma.user.findFirst({
      where: {
        OR: [
          { email: { equals: cleanQuery, mode: "insensitive" } },
          { username: { equals: cleanQuery, mode: "insensitive" } },
          { email: { contains: cleanQuery, mode: "insensitive" } },
          { username: { contains: cleanQuery, mode: "insensitive" } },
        ],
      },
    });

    if (!contactUser) {
      res.status(404).json({ message: "No user found with that email or username" });
      return;
    }

    if (contactUser.id === userId) {
      res.status(400).json({ message: "You cannot add yourself as a contact" });
      return;
    }

    const existing = await prisma.contact.findUnique({
      where: { userId_contactId: { userId, contactId: contactUser.id } },
    });

    if (existing) {
      res.status(400).json({ message: "Contact already saved" });
      return;
    }

    const contact = await prisma.contact.create({
      data: {
        userId,
        contactId: contactUser.id,
        savedName: savedName?.trim() || contactUser.username,
        savedEmail: contactUser.email,
        savedUsername: contactUser.username,
      },
      include: {
        contact: {
          select: { id: true, username: true, email: true, avatarUrl: true, statusMessage: true, isOnline: true, lastSeen: true },
        },
      },
    });

    res.status(201).json(contact);
  } catch (error) {
    console.error("Add contact error:", error);
    res.status(500).json({ message: "Failed to add contact" });
  }
};

// Add contact directly by contactUserId (used after first message)
export const addContactById = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { contactUserId, savedName } = req.body;

    if (!contactUserId) {
      res.status(400).json({ message: "contactUserId is required" });
      return;
    }

    const contactUser = await prisma.user.findUnique({
      where: { id: contactUserId },
    });

    if (!contactUser) {
      res.status(404).json({ message: "User not found" });
      return;
    }

    if (contactUser.id === userId) {
      res.status(400).json({ message: "You cannot add yourself" });
      return;
    }

    const existing = await prisma.contact.findUnique({
      where: { userId_contactId: { userId, contactId: contactUserId } },
    });

    if (existing) {
      res.status(400).json({ message: "Contact already saved" });
      return;
    }

    const contact = await prisma.contact.create({
      data: {
        userId,
        contactId: contactUserId,
        savedName: savedName?.trim() || contactUser.username,
        savedEmail: contactUser.email,
        savedUsername: contactUser.username,
      },
      include: {
        contact: {
          select: { id: true, username: true, email: true, avatarUrl: true, statusMessage: true, isOnline: true },
        },
      },
    });

    res.status(201).json(contact);
  } catch (error) {
    console.error("Add contact by ID error:", error);
    res.status(500).json({ message: "Failed to add contact" });
  }
};

// Get all contacts for current user
export const getContacts = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;

    const contacts = await prisma.contact.findMany({
      where: { userId, isBlocked: false },
      include: {
        contact: {
          select: { id: true, username: true, email: true, avatarUrl: true, statusMessage: true, lastSeen: true, isOnline: true },
        },
      },
      orderBy: [{ isFavorite: "desc" }, { savedName: "asc" }],
    });

    res.status(200).json(contacts);
  } catch (error) {
    console.error("Get contacts error:", error);
    res.status(500).json({ message: "Failed to retrieve contacts" });
  }
};

// Update contact (rename or toggle favorite)
export const updateContact = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const contactId = req.params["contactId"] as string;
    const { savedName, isFavorite } = req.body;

    const contact = await prisma.contact.findFirst({
      where: { id: contactId, userId },
    });

    if (!contact) {
      res.status(404).json({ message: "Contact not found" });
      return;
    }

    const updated = await prisma.contact.update({
      where: { id: contactId },
      data: {
        ...(savedName !== undefined && { savedName: savedName.trim() }),
        ...(isFavorite !== undefined && { isFavorite }),
      },
      include: {
        contact: {
          select: { id: true, username: true, email: true, avatarUrl: true, statusMessage: true },
        },
      },
    });

    res.status(200).json(updated);
  } catch (error) {
    console.error("Update contact error:", error);
    res.status(500).json({ message: "Failed to update contact" });
  }
};

// Delete a contact
export const deleteContact = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const contactId = req.params["contactId"] as string;

    const contact = await prisma.contact.findFirst({
      where: { id: contactId, userId },
    });

    if (!contact) {
      res.status(404).json({ message: "Contact not found" });
      return;
    }

    await prisma.contact.delete({ where: { id: contactId } });

    res.status(200).json({ message: "Contact deleted" });
  } catch (error) {
    console.error("Delete contact error:", error);
    res.status(500).json({ message: "Failed to delete contact" });
  }
};

// Check if a userId is in caller's contacts
export const checkIsContact = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const targetUserId = req.params["targetUserId"] as string;

    const contact = await prisma.contact.findUnique({
      where: { userId_contactId: { userId, contactId: targetUserId } },
    });

    res.status(200).json({ isContact: !!contact, contact });
  } catch (error) {
    console.error("Check contact error:", error);
    res.status(500).json({ message: "Failed to check contact" });
  }
};
