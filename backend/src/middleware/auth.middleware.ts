import type { Request, Response, NextFunction } from "express";
import jwt from "jsonwebtoken";
import { prisma } from "../config/db.js";

export interface AuthRequest extends Request {
  user?: {
    id: string;
    username: string;
    email?: string | null;
    phoneNumber?: string | null;
    avatarUrl: string | null;
    bio?: string | null;
  };
}

export const authenticateToken = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
 ): Promise<void> => {
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) {
    res.status(401).json({ message: "Access token required" });
    return;
  }

  try {
    const secret = process.env.JWT_SECRET || "dolsyx_super_secret_key_123456";
    const decoded = jwt.verify(token, secret) as {
      id: string;
      username: string;
    };

    const user = await prisma.user.findUnique({
      where: { id: decoded.id },
      select: {
        id: true,
        username: true,
        email: true,
        phoneNumber: true,
        avatarUrl: true,
        coverUrl: true,
        bio: true,
        statusMessage: true,
        xp: true,
        streakCount: true,
        avatarPrivacy: true,
        lastSeenPrivacy: true,
        onlinePrivacy: true,
        aboutPrivacy: true,
        readReceipts: true,
        disappearingTimer: true,
        statusPrivacyType: true,
        statusPrivacyList: true,
        avatarPrivacyExceptList: true,
        lastSeenPrivacyExceptList: true,
        aboutPrivacyExceptList: true,
      },
    });

    if (!user) {
      res.status(404).json({ message: "User not found" });
      return;
    }

    req.user = user;
    next();
  } catch (error) {
    res.status(403).json({ message: "Invalid or expired token" });
  }
};
