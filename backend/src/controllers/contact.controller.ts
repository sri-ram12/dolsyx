import type { Response } from "express";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";

// Add a contact by email
export const addContact = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { email, savedName } = req.body;

    if (!email) {
      res.status(400).json({ message: "Email is required" });
      return;
    }

    // Find user by email
    const contactUser = await prisma.user.findUnique({
      where: { email },
    });

    if (!contactUser) {
      res.status(404).json({ message: "User with this email not found" });
      return;
    }

    if (contactUser.id === userId) {
      res.status(400).json({ message: "You cannot add yourself as a contact" });
      return;
    }

    // Check if contact already exists
    const existingContact = await prisma.contact.findUnique({
      where: {
        userId_contactId: {
          userId,
          contactId: contactUser.id,
        },
      },
    });

    if (existingContact) {
      res.status(400).json({ message: "Contact already saved" });
      return;
    }

    const contact = await prisma.contact.create({
      data: {
        userId,
        contactId: contactUser.id,
        savedName: savedName || contactUser.username,
      },
      include: {
        contact: {
          select: { id: true, username: true, email: true, avatarUrl: true, statusMessage: true },
        },
      },
    });

    res.status(201).json(contact);
  } catch (error) {
    console.error("Add contact error:", error);
    res.status(500).json({ message: "Failed to add contact" });
  }
};

// Get all contacts
export const getContacts = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;

    const contacts = await prisma.contact.findMany({
      where: { userId },
      include: {
        contact: {
          select: { id: true, username: true, email: true, avatarUrl: true, statusMessage: true, lastSeen: true, isOnline: true },
        },
      },
      orderBy: { savedName: "asc" },
    });

    res.status(200).json(contacts);
  } catch (error) {
    console.error("Get contacts error:", error);
    res.status(500).json({ message: "Failed to retrieve contacts" });
  }
};

// Delete a contact
export const deleteContact = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const contactId = req.params["contactId"] as string;

    await prisma.contact.delete({
      where: {
        userId_contactId: {
          userId,
          contactId,
        },
      },
    });

    res.status(200).json({ message: "Contact deleted successfully" });
  } catch (error) {
    console.error("Delete contact error:", error);
    res.status(500).json({ message: "Failed to delete contact" });
  }
};
