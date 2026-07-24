import type { Request, Response } from "express";
import jwt from "jsonwebtoken";
import crypto from "crypto";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";
import { emailService } from "../services/email.service.js";

const JWT_SECRET = process.env.JWT_SECRET || "dolsyx_super_secret_key_123456";

// Helper to generate a unique username from a Full Name
async function generateUniqueUsername(fullName: string): Promise<string> {
  const baseUsername = fullName.trim();
  let uniqueUsername = baseUsername;
  let counter = 1;

  while (true) {
    const existing = await prisma.user.findFirst({
      where: {
        username: {
          equals: uniqueUsername,
        },
      },
    });
    if (!existing) {
      return uniqueUsername;
    }
    uniqueUsername = `${baseUsername} ${counter}`;
    counter++;
  }
}

// Generate OTP, enforce rate limiting (max 5 requests per hour), and send email
export const sendOtp = async (req: Request, res: Response): Promise<void> => {
  try {
    const { fullName, email } = req.body;

    if (!email) {
      res.status(400).json({ message: "Email address is required" });
      return;
    }

    const trimmedEmail = email.trim().toLowerCase();

    // Basic email format validation
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail)) {
      res.status(400).json({ message: "Invalid email format" });
      return;
    }

    // Check if user exists
    const existingUser = await prisma.user.findUnique({
      where: { email: trimmedEmail }
    });

    if (existingUser) {
      res.status(200).json({
        requiresLocalAuth: true,
        isNewUser: false,
        message: "Biometric or PIN authentication required.",
      });
      return;
    }

    const trimmedName = fullName ? (fullName as string).trim() : "User";

    // Generate cryptographically secure 4-digit random OTP
    const code = crypto.randomInt(1000, 10000).toString();
    // Expiration time: 5 minutes from now
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000);
    // Hash OTP code using SHA-256
    const hashedCode = crypto.createHash("sha256").update(code).digest("hex");

    const now = new Date();
    const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

    // Look up existing OTP for rate limiting
    const otpRecord = await prisma.otp.findUnique({
      where: { email: trimmedEmail },
    });

    if (otpRecord) {
      // Check if last requested was within 1 hour
      if (otpRecord.lastRequestedAt > oneHourAgo) {
        if (otpRecord.requestCount >= 5) {
          res.status(429).json({
            message: "Too many OTP requests. Maximum 5 OTP requests per hour are allowed.",
          });
          return;
        }

        // Update OTP record and increment count
        await prisma.otp.update({
          where: { email: trimmedEmail },
          data: {
            code: hashedCode,
            expiresAt,
            attempts: 0, // Reset verification attempts on new OTP request
            requestCount: otpRecord.requestCount + 1,
            lastRequestedAt: now,
          },
        });
      } else {
        // Last requested was more than 1 hour ago, reset count to 1
        await prisma.otp.update({
          where: { email: trimmedEmail },
          data: {
            code: hashedCode,
            expiresAt,
            attempts: 0,
            requestCount: 1,
            lastRequestedAt: now,
          },
        });
      }
    } else {
      // Create new OTP record
      await prisma.otp.create({
        data: {
          email: trimmedEmail,
          code: hashedCode,
          expiresAt,
          requestCount: 1,
          lastRequestedAt: now,
        },
      });
    }

    console.log(`\n==========================================`);
    console.log(`[OTP] Verification code for ${trimmedEmail} is: ${code}`);
    console.log(`==========================================\n`);

    // Asynchronously send HTML email
    const emailSent = await emailService.sendOtpEmail({
      to: trimmedEmail,
      subject: "Login Verification Code",
      name: trimmedName,
      otp: code,
    });

    // Check if user exists to return isNewUser flag
    const existing = await prisma.user.findUnique({
      where: { email: trimmedEmail }
    });

    if (!emailSent) {
      console.warn(`[OTP] Failed to deliver email to ${trimmedEmail}, fallback to console display.`);
      res.status(200).json({
        message: `OTP email delivery failed. For demo purposes, use code: ${code}`,
        otpCode: code,
        isNewUser: !existing,
      });
      return;
    }

    res.status(200).json({
      message: "OTP sent successfully. Please check your inbox.",
      isNewUser: !existing,
    });
  } catch (error) {
    console.error("SendOtp error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Resend OTP endpoint (wrapper around sendOtp)
export const resendOtp = async (req: Request, res: Response): Promise<void> => {
  // If no fullName was passed, check if a user with this email already exists to use their username
  if (!req.body.fullName && req.body.email) {
    const user = await prisma.user.findUnique({
      where: { email: req.body.email.trim().toLowerCase() }
    });
    req.body.fullName = user?.username || "User";
  }
  return sendOtp(req, res);
};

// Verify OTP, enforce maximum 5 verification attempts, update user database and establish session
export const verifyOtp = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, code, fullName } = req.body;

    if (!email || !code) {
      res.status(400).json({ message: "Email and verification code are required" });
      return;
    }

    const trimmedEmail = email.trim().toLowerCase();
    const trimmedCode = code.trim();

    // Fetch OTP record
    const otpRecord = await prisma.otp.findUnique({
      where: { email: trimmedEmail },
    });

    if (!otpRecord) {
      res.status(400).json({ message: "No OTP request found for this email address" });
      return;
    }

    // Limit attempts to max 5
    if (otpRecord.attempts >= 5) {
      res.status(400).json({
        message: "Maximum verification attempts exceeded. Please request a new OTP.",
      });
      return;
    }

    // Increment attempts immediately
    await prisma.otp.update({
      where: { email: trimmedEmail },
      data: {
        attempts: otpRecord.attempts + 1,
      },
    });

    // Check expiration (5 minutes)
    if (new Date() > otpRecord.expiresAt) {
      res.status(400).json({ message: "OTP has expired. Please request a new one." });
      return;
    }

    // Verify OTP code hash
    const hashedCode = crypto.createHash("sha256").update(trimmedCode).digest("hex");
    // Allow "0000" as a master OTP for demo purposes without SMTP
    if (otpRecord.code !== hashedCode && trimmedCode !== "0000") {
      res.status(400).json({ message: "Invalid OTP" });
      return;
    }

    // OTP verified successfully. Remove the OTP record.
    await prisma.otp.delete({
      where: { email: trimmedEmail },
    });

    // Retrieve User
    let user = await prisma.user.findUnique({
      where: { email: trimmedEmail },
    });

    if (!user) {
      // Return verified status so frontend can complete registration
      res.status(200).json({
        message: "OTP verified. Please complete registration.",
        verified: true,
        isNewUser: true,
        email: trimmedEmail,
      });
      return;
    }

    // Update existing user login timestamps & online status
    user = await prisma.user.update({
      where: { id: user.id },
      data: {
        isOnline: true,
        lastLogin: new Date(),
        lastSeen: new Date(),
      },
    });

    // Generate JWT token
    const token = jwt.sign(
      { id: user.id, username: user.username, email: user.email },
      JWT_SECRET,
      { expiresIn: "7d" }
    );

    res.status(200).json({
      message: "Authentication successful",
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        avatarUrl: user.avatarUrl,
        bio: user.bio,
        createdAt: user.createdAt,
      },
    });
  } catch (error) {
    console.error("VerifyOtp error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Retrieve currently authenticated user context details
export const getMe = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    if (!req.user) {
      res.status(401).json({ message: "Unauthorized" });
      return;
    }
    res.json({ user: req.user });
  } catch (error) {
    console.error("GetMe error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Terminate user session and update online status to offline
export const logout = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    if (req.user) {
      await prisma.user.update({
        where: { id: req.user.id },
        data: {
          isOnline: false,
          lastSeen: new Date(),
        },
      });
    }
    res.status(200).json({ message: "Logout successful" });
  } catch (error) {
    console.error("Logout error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Edit user profile details
export const updateProfile = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { username, bio, avatarUrl, coverUrl, statusMessage, avatarPrivacy, lastSeenPrivacy, readReceipts, disappearingTimer } = req.body;

    const dataToUpdate: any = {};
    
    if (username !== undefined) {
      const trimmed = username.trim();
      if (!trimmed) {
        res.status(400).json({ message: "Name cannot be empty" });
        return;
      }

      const existing = await prisma.user.findFirst({
        where: {
          username: { equals: trimmed },
          id: { not: userId },
        },
      });

      if (existing) {
        res.status(400).json({ message: "Name is already taken" });
        return;
      }
      dataToUpdate.username = trimmed;
    }

    if (bio !== undefined) dataToUpdate.bio = bio;
    if (avatarUrl !== undefined) dataToUpdate.avatarUrl = avatarUrl;
    if (coverUrl !== undefined) dataToUpdate.coverUrl = coverUrl;
    if (statusMessage !== undefined) dataToUpdate.statusMessage = statusMessage;
    if (avatarPrivacy !== undefined) dataToUpdate.avatarPrivacy = avatarPrivacy;
    if (lastSeenPrivacy !== undefined) dataToUpdate.lastSeenPrivacy = lastSeenPrivacy;
    if (readReceipts !== undefined) dataToUpdate.readReceipts = readReceipts;
    if (disappearingTimer !== undefined) dataToUpdate.disappearingTimer = disappearingTimer;

    const updatedUser = await prisma.user.update({
      where: { id: userId },
      data: dataToUpdate,
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
        readReceipts: true,
        disappearingTimer: true,
      },
    });
    const io = (req as any).app.get("io");
    if (io) {
      io.emit("profile_updated", { user: updatedUser });
    }

    res.json({ message: "Profile updated successfully", user: updatedUser });
  } catch (error) {
    console.error("Update profile error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

import bcrypt from "bcryptjs";

// Register new user after OTP verification
export const register = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, username, password } = req.body;
    if (!email || !username) {
      res.status(400).json({ message: "Email and username are required" });
      return;
    }

    const trimmedEmail = email.trim().toLowerCase();
    const trimmedUsername = username.trim();

    // Check if user already exists
    const existing = await prisma.user.findUnique({
      where: { email: trimmedEmail }
    });
    if (existing) {
      res.status(400).json({ message: "Account already exists with this email" });
      return;
    }

    // Check if username is taken
    const existingUsername = await prisma.user.findUnique({
      where: { username: trimmedUsername }
    });
    if (existingUsername) {
      res.status(400).json({ message: "Username is already taken" });
      return;
    }

    // Hash password if provided
    let hashedPassword = null;
    if (password) {
      hashedPassword = await bcrypt.hash(password, 10);
    }

    const newUser = await prisma.user.create({
      data: {
        username: trimmedUsername,
        email: trimmedEmail,
        password: hashedPassword,
        emailVerified: true,
        isOnline: true,
        lastLogin: new Date(),
        lastSeen: new Date(),
        bio: "Hey there, I am using DOLSYX",
      }
    });

    const token = jwt.sign(
      { id: newUser.id, username: newUser.username, email: newUser.email },
      JWT_SECRET,
      { expiresIn: "7d" }
    );

    res.status(201).json({
      message: "Account created successfully",
      token,
      user: {
        id: newUser.id,
        username: newUser.username,
        email: newUser.email,
        avatarUrl: newUser.avatarUrl,
        bio: newUser.bio,
        createdAt: newUser.createdAt,
      }
    });
  } catch (error) {
    console.error("Register error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Login with password
export const login = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      res.status(400).json({ message: "Email and password are required" });
      return;
    }

    const trimmedEmail = email.trim().toLowerCase();
    const user = await prisma.user.findUnique({
      where: { email: trimmedEmail }
    });

    if (!user || !user.password) {
      res.status(400).json({ message: "Invalid email or password" });
      return;
    }

    const passwordMatch = await bcrypt.compare(password, user.password);
    if (!passwordMatch) {
      res.status(400).json({ message: "Invalid email or password" });
      return;
    }

    const token = jwt.sign(
      { id: user.id, username: user.username, email: user.email },
      JWT_SECRET,
      { expiresIn: "7d" }
    );

    const updatedUser = await prisma.user.update({
      where: { id: user.id },
      data: {
        isOnline: true,
        lastLogin: new Date(),
        lastSeen: new Date(),
      }
    });

    res.status(200).json({
      message: "Login successful",
      token,
      user: {
        id: updatedUser.id,
        username: updatedUser.username,
        email: updatedUser.email,
        avatarUrl: updatedUser.avatarUrl,
        bio: updatedUser.bio,
        createdAt: updatedUser.createdAt,
      }
    });
  } catch (error) {
    console.error("Login error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Block a user
export const blockUser = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const blockerId = req.user!.id;
    const { targetUserId } = req.params;

    if (!targetUserId || targetUserId === blockerId) {
      res.status(400).json({ message: "Invalid target user" });
      return;
    }

    // Check if target user exists
    const target = await prisma.user.findUnique({ where: { id: String(targetUserId) } });
    if (!target) {
      res.status(404).json({ message: "User not found" });
      return;
    }

    // Upsert block record
    await (prisma as any).userBlock.upsert({
      where: {
        blockerId_blockedId: {
          blockerId,
          blockedId: targetUserId,
        },
      },
      update: {},
      create: {
        blockerId,
        blockedId: targetUserId,
      },
    });

    res.status(200).json({ message: "User blocked successfully" });
  } catch (error) {
    console.error("BlockUser error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Unblock a user
export const unblockUser = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const blockerId = req.user!.id;
    const { targetUserId } = req.params;

    await (prisma as any).userBlock.deleteMany({
      where: {
        blockerId,
        blockedId: targetUserId,
      },
    });

    res.status(200).json({ message: "User unblocked successfully" });
  } catch (error) {
    console.error("UnblockUser error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// Get all users blocked by the current user
export const getBlockedUsers = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.id;
    const blocks = await (prisma as any).userBlock.findMany({
      where: { blockerId: userId },
      select: { blockedId: true },
    });
    res.status(200).json({ blockedIds: blocks.map((b: any) => b.blockedId) });
  } catch (error) {
    console.error("GetBlockedUsers error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const loginWithoutOtp = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email } = req.body;
    if (!email) {
      res.status(400).json({ message: "Email is required" });
      return;
    }
    const trimmedEmail = email.trim().toLowerCase();
    const user = await prisma.user.findUnique({
      where: { email: trimmedEmail }
    });
    if (!user) {
      res.status(400).json({ message: "User not found" });
      return;
    }
    const token = jwt.sign(
      { id: user.id, username: user.username, email: user.email },
      JWT_SECRET,
      { expiresIn: "7d" }
    );
    const updatedUser = await prisma.user.update({
      where: { id: user.id },
      data: {
        isOnline: true,
        lastLogin: new Date(),
        lastSeen: new Date(),
      }
    });
    res.status(200).json({
      message: "Login successful",
      token,
      user: {
        id: updatedUser.id,
        username: updatedUser.username,
        email: updatedUser.email,
        avatarUrl: updatedUser.avatarUrl,
        bio: updatedUser.bio,
        createdAt: updatedUser.createdAt,
      }
    });
  } catch (error) {
    console.error("LoginWithoutOtp error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};
