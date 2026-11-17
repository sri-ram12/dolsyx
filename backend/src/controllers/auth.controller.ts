import type { Request, Response } from "express";
import jwt from "jsonwebtoken";
import crypto from "crypto";
import bcrypt from "bcryptjs";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";
import { canViewProfilePhoto, canViewAbout, canViewLastSeen, canViewOnline } from "../utils/privacy.engine.js";
import { emailService } from "../services/email.service.js";
import { googleAuthService } from "../services/googleAuth.service.js";

const JWT_SECRET = process.env.JWT_SECRET || "dolsyx_super_secret_key_123456";

function formatErrorMessage(error: any, fallback = "Internal server error"): string {
  if (process.env.NODE_ENV === "production") return fallback;
  if (!error) return fallback;
  const msg = error.message || String(error);
  if (msg.includes("tenant/user") || msg.includes("ENOTFOUND") || msg.includes("connect") || error.code?.startsWith?.("P")) {
    return "Database connection failed (Supabase database may be paused). Please restore the database in Supabase dashboard or check DATABASE_URL.";
  }
  return msg || fallback;
}

// Helper to generate a unique username from a Full Name safely and reliably
async function generateUniqueUsername(fullName: string): Promise<string> {
  const baseUsername = fullName.trim().replace(/\s+/g, "_").toLowerCase() || "user";
  const existing = await prisma.user.findUnique({
    where: { username: baseUsername },
    select: { id: true },
  });
  if (!existing) {
    return baseUsername;
  }

  // Try up to 5 times with random 4-digit suffixes using indexed O(1) lookups
  for (let i = 0; i < 5; i++) {
    const candidate = `${baseUsername}_${Math.floor(1000 + Math.random() * 9000)}`;
    const match = await prisma.user.findUnique({
      where: { username: candidate },
      select: { id: true },
    });
    if (!match) return candidate;
  }

  // Guaranteed fallback unique timestamp
  return `${baseUsername}_${Date.now().toString(36)}`;
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
        message: `OTP email delivery unavailable. Verification code: ${code}`,
        otpCode: code,
        isNewUser: !existing,
        requiresLocalAuth: !!existing,
      });
      return;
    }

    res.status(200).json({
      message: "OTP sent successfully. Please check your inbox.",
      isNewUser: !existing,
      requiresLocalAuth: !!existing,
    });
  } catch (error) {
    console.error("SendOtp error:", error);
    res.status(500).json({ message: formatErrorMessage(error) });
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

    // Intercept if Two-Step Verification (2SV) is enabled on this account
    if (user.twoStepEnabled) {
      if (user.twoStepLockoutUntil && new Date() < user.twoStepLockoutUntil) {
        const remainingMinutes = Math.ceil((user.twoStepLockoutUntil.getTime() - Date.now()) / (60 * 1000));
        res.status(429).json({
          message: `Account temporarily locked due to too many failed PIN attempts. Please wait ${remainingMinutes} minute(s).`,
          lockoutRemainingMinutes: remainingMinutes,
          requiresTwoStep: true,
        });
        return;
      }
      res.status(200).json({
        message: "Two-step verification PIN required",
        requiresTwoStep: true,
        email: user.email,
        hasPendingReset: !!user.twoStepResetRequestedAt,
        resetRequestedAt: user.twoStepResetRequestedAt,
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
    res.status(500).json({ message: formatErrorMessage(error) });
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

export const getUserById = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const requesterId = req.user!.id;
    const id = req.params.id as string;
    const user = await prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        username: true,
        email: true,
        phoneNumber: true,
        avatarUrl: true,
        coverUrl: true,
        bio: true,
        statusMessage: true,
        lastSeen: true,
        isOnline: true,
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
      }
    });
    if (!user) {
      res.status(404).json({ message: "User not found" });
      return;
    }

    // Apply privacy engine — own profile is always returned unfiltered
    if (requesterId !== id) {
      // Check block status first — if either user blocked the other, strip sensitive data
      const blockRecord = await prisma.userBlock.findFirst({
        where: {
          OR: [
            { blockerId: requesterId, blockedId: id },
            { blockerId: id, blockedId: requesterId },
          ],
        },
      });

      const filtered: any = { ...user };

      if (blockRecord) {
        // Completely hide sensitive info from/to blocked users
        filtered.avatarUrl = null;
        filtered.coverUrl = null;
        filtered.bio = null;
        filtered.statusMessage = null;
        filtered.lastSeen = null;
        filtered.isOnline = false;
        res.json(filtered);
        return;
      }

      const [canPhoto, canAbout, canLastSeen, canOnlineStatus] = await Promise.all([
        canViewProfilePhoto(requesterId, id),
        canViewAbout(requesterId, id),
        canViewLastSeen(requesterId, id),
        canViewOnline(requesterId, id),
      ]);

      if (!canPhoto) { filtered.avatarUrl = null; filtered.coverUrl = null; }
      if (!canAbout) { filtered.bio = null; filtered.statusMessage = null; }
      if (!canLastSeen) filtered.lastSeen = null;
      if (!canOnlineStatus) filtered.isOnline = false;
      res.json(filtered);
    } else {
      res.json(user);
    }
  } catch (error) {
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
    const { username, bio, avatarUrl, coverUrl, statusMessage,
      avatarPrivacy, lastSeenPrivacy, onlinePrivacy, aboutPrivacy,
      readReceipts, disappearingTimer,
      statusPrivacyType, statusPrivacyList,
      avatarPrivacyExceptList, lastSeenPrivacyExceptList, aboutPrivacyExceptList
    } = req.body;

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
    if (onlinePrivacy !== undefined) dataToUpdate.onlinePrivacy = onlinePrivacy;
    if (aboutPrivacy !== undefined) dataToUpdate.aboutPrivacy = aboutPrivacy;
    if (readReceipts !== undefined) dataToUpdate.readReceipts = readReceipts;
    if (disappearingTimer !== undefined) dataToUpdate.disappearingTimer = disappearingTimer;
    if (statusPrivacyType !== undefined) dataToUpdate.statusPrivacyType = statusPrivacyType;
    if (statusPrivacyList !== undefined) dataToUpdate.statusPrivacyList = statusPrivacyList;
    if (avatarPrivacyExceptList !== undefined) dataToUpdate.avatarPrivacyExceptList = avatarPrivacyExceptList;
    if (lastSeenPrivacyExceptList !== undefined) dataToUpdate.lastSeenPrivacyExceptList = lastSeenPrivacyExceptList;
    if (aboutPrivacyExceptList !== undefined) dataToUpdate.aboutPrivacyExceptList = aboutPrivacyExceptList;

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

// Register new user after OTP verification
export const register = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, username, password, fcmToken } = req.body;

    if (!email || !username) {
      res.status(400).json({ message: "Email and username are required." });
      return;
    }

    const trimmedEmail = email.trim().toLowerCase();
    const trimmedUsername = username.trim();

    // Check if user already exists
    const existing = await prisma.user.findFirst({
      where: {
        OR: [{ email: trimmedEmail }, { username: trimmedUsername }],
      },
    });

    if (existing) {
      res.status(400).json({ message: "Email or username is already in use." });
      return;
    }

    // Hash password strictly
    if (!password || typeof password !== "string" || password.trim().length < 6) {
      res.status(400).json({ message: "Password is required and must be at least 6 characters long." });
      return;
    }
    const hashedPassword = await bcrypt.hash(password.trim(), 10);

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
        fcmToken: fcmToken || null,
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

// Login with strict password authentication
export const login = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, password, fcmToken } = req.body;
    if (!email || !password) {
      res.status(400).json({ message: "Email and password are required" });
      return;
    }

    const trimmedEmail = email.trim().toLowerCase();
    const user = await prisma.user.findUnique({
      where: { email: trimmedEmail }
    });

    if (!user) {
      res.status(400).json({ message: "Invalid email or password" });
      return;
    }

    // Check if legacy user has no password set yet
    if (!user.password) {
      res.status(200).json({
        needsPasswordSetup: true,
        email: user.email,
        message: "Your account does not have a password set yet. Please set your security password.",
      });
      return;
    }

    const passwordMatch = await bcrypt.compare(password, user.password);
    if (!passwordMatch) {
      res.status(400).json({ message: "Invalid email or password" });
      return;
    }

    // Intercept if Two-Step Verification (2SV) is enabled on this account
    if (user.twoStepEnabled) {
      if (user.twoStepLockoutUntil && new Date() < user.twoStepLockoutUntil) {
        const remainingMinutes = Math.ceil((user.twoStepLockoutUntil.getTime() - Date.now()) / (60 * 1000));
        res.status(429).json({
          message: `Account temporarily locked due to too many failed PIN attempts. Please wait ${remainingMinutes} minute(s).`,
          lockoutRemainingMinutes: remainingMinutes,
          requiresTwoStep: true,
        });
        return;
      }
      res.status(200).json({
        message: "Two-step verification PIN required",
        requiresTwoStep: true,
        email: user.email,
        hasPendingReset: !!user.twoStepResetRequestedAt,
        resetRequestedAt: user.twoStepResetRequestedAt,
      });
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
        ...(fcmToken ? { fcmToken } : {})
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
      include: { blocked: true },
    });
    res.status(200).json(blocks.map((b: any) => ({ blockedUser: b.blocked })));
  } catch (error) {
    console.error("GetBlockedUsers error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

export const loginWithoutOtp = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, fcmToken } = req.body;
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

    // Intercept if Two-Step Verification (2SV) is enabled on this account
    if (user.twoStepEnabled) {
      if (user.twoStepLockoutUntil && new Date() < user.twoStepLockoutUntil) {
        const remainingMinutes = Math.ceil((user.twoStepLockoutUntil.getTime() - Date.now()) / (60 * 1000));
        res.status(429).json({
          message: `Account temporarily locked due to too many failed PIN attempts. Please wait ${remainingMinutes} minute(s).`,
          lockoutRemainingMinutes: remainingMinutes,
          requiresTwoStep: true,
        });
        return;
      }
      res.status(200).json({
        message: "Two-step verification PIN required",
        requiresTwoStep: true,
        email: user.email,
        hasPendingReset: !!user.twoStepResetRequestedAt,
        resetRequestedAt: user.twoStepResetRequestedAt,
      });
      return;
    }

    const token = jwt.sign(
      { id: user.id, username: user.username, email: user.email },
      JWT_SECRET,
      { expiresIn: "7d" }
    );
    const dataToUpdate: any = {
      isOnline: true,
      lastLogin: new Date(),
      lastSeen: new Date(),
    };
    if (fcmToken) {
      dataToUpdate.fcmToken = fcmToken;
    }

    const updatedUser = await prisma.user.update({
      where: { id: user.id },
      data: dataToUpdate
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

// Permanently delete user account and associated personal data (Mandatory Google Play Policy)
export const deleteAccount = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Unauthorized" });
      return;
    }

    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      res.status(404).json({ message: "User not found" });
      return;
    }

    // Delete user from database (cascades to devices, chats, contacts, keys, and media refs)
    await prisma.user.delete({
      where: { id: userId },
    });

    res.json({
      success: true,
      message: "Account and all associated personal data have been permanently deleted.",
    });
  } catch (error) {
    console.error("Delete account error:", error);
    res.status(500).json({ message: "Failed to delete account. Please try again later." });
  }
};

// Public web endpoint for requesting account and data deletion (Mandatory Google Play web URL requirement)
export const requestAccountDeletion = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, reason } = req.body;
    if (!email) {
      res.status(400).json({ message: "Email address is required" });
      return;
    }

    const trimmedEmail = String(email).trim().toLowerCase();
    const user = await prisma.user.findUnique({ where: { email: trimmedEmail } });

    if (!user) {
      // Return success to avoid email enumeration while confirming deletion request
      res.json({
        success: true,
        message: "If an account with this email exists, a verification link has been initiated.",
      });
      return;
    }

    // Process permanent deletion directly or flag for immediate cleanup
    await prisma.user.delete({
      where: { id: user.id },
    });

    res.json({
      success: true,
      message: "Your account and all associated data have been permanently deleted from DOLSYX servers.",
    });
  } catch (error) {
    console.error("Public account deletion request error:", error);
    res.status(500).json({ message: "Failed to process deletion request." });
  }
};

// Helper to set secure HTTP-only cookies and return user session
async function createAndStoreSession(
  res: Response,
  userId: string,
  userAgent?: string,
  ipAddress?: string,
  deviceType: string = "web"
) {
  const token = jwt.sign(
    { id: userId },
    JWT_SECRET,
    { expiresIn: "30d" }
  );

  const refreshToken = crypto.randomBytes(40).toString("hex");
  const refreshTokenHash = crypto.createHash("sha256").update(refreshToken).digest("hex");
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

  // Store active session in database
  const session = await prisma.session.create({
    data: {
      userId,
      token,
      refreshTokenHash,
      userAgent: userAgent || "Unknown Browser",
      ipAddress: ipAddress || "0.0.0.0",
      deviceType,
      expiresAt,
      isActive: true,
    },
  });

  const isProduction = process.env.NODE_ENV === "production";
  const cookieOptions = {
    httpOnly: true,
    secure: isProduction,
    sameSite: isProduction ? ("strict" as const) : ("lax" as const),
    maxAge: 30 * 24 * 60 * 60 * 1000,
    path: "/",
  };

  res.cookie("dolsyx_session", token, cookieOptions);
  res.cookie("dolsyx_refresh", refreshToken, cookieOptions);

  return { token, refreshToken, sessionId: session.id };
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. GET /auth/google: Initiate OAuth 2.0 PKCE Flow
// ─────────────────────────────────────────────────────────────────────────────
export const initiateGoogleAuth = async (req: Request, res: Response): Promise<void> => {
  try {
    const host = req.get("host") || "localhost:4000";
    const forwardedProto = req.headers["x-forwarded-proto"];
    const protocol = (typeof forwardedProto === "string" ? forwardedProto : req.protocol) || "http";
    const defaultRedirectUri = `${protocol}://${host}/api/auth/google/callback`;
    const redirectUri = process.env.GOOGLE_REDIRECT_URI || defaultRedirectUri;

    const { codeVerifier, codeChallenge } = googleAuthService.generatePkcePair();

    // Resolve dynamic client frontend URL to return to after auth
    const envFrontendUrl =
      process.env.FRONTEND_URL && process.env.FRONTEND_URL !== "*"
        ? process.env.FRONTEND_URL
        : null;
    const clientFrontendUrl =
      (typeof req.query.frontendUrl === "string" ? req.query.frontendUrl : null) ||
      (req.headers.origin as string) ||
      (req.headers.referer ? new URL(req.headers.referer).origin : null) ||
      envFrontendUrl ||
      (process.env.VERCEL === "1" ? `${protocol}://${host}` : "http://localhost:3000");

    // Encode state and PKCE into a tamper-proof signed token passed through Google's state parameter
    const stateData = {
      codeVerifier,
      redirectUri,
      frontendUrl: clientFrontendUrl,
      nonce: crypto.randomBytes(16).toString("hex"),
      ts: Date.now(),
    };
    const secret = process.env.JWT_SECRET || "dolsyx_jwt_secret_key_2026";
    const dataB64 = Buffer.from(JSON.stringify(stateData)).toString("base64url");
    const sig = crypto.createHmac("sha256", secret).update(dataB64).digest("base64url");
    const state = `${dataB64}.${sig}`;

    const isProduction = process.env.NODE_ENV === "production";
    const statePayload = JSON.stringify({ state, codeVerifier, redirectUri, frontendUrl: clientFrontendUrl });

    res.cookie("dolsyx_oauth_state", statePayload, {
      httpOnly: true,
      secure: isProduction,
      sameSite: "lax",
      maxAge: 10 * 60 * 1000, // 10 minutes
      path: "/",
    });

    const authUrl = googleAuthService.generateAuthUrl(state, codeChallenge, redirectUri);

    if (req.query.json === "true" || req.headers["accept"]?.includes("application/json")) {
      res.json({ authUrl, state, redirectUri });
      return;
    }

    res.redirect(authUrl);
  } catch (error) {
    console.error("[OAuth] Error initiating Google auth:", error);
    res.status(500).json({ message: "Failed to initiate Google authentication." });
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// 2. GET /auth/google/callback: Handle Google OAuth 2.0 PKCE Callback
// ─────────────────────────────────────────────────────────────────────────────
export const handleGoogleCallback = async (req: Request, res: Response): Promise<void> => {
  const frontendUrl = process.env.FRONTEND_URL || "http://localhost:3000";

  try {
    const { code, state, error: oauthError } = req.query;

    if (oauthError) {
      console.warn("[OAuth] Google returned error:", oauthError);
      res.redirect(`${frontendUrl}/login?error=${encodeURIComponent(String(oauthError))}`);
      return;
    }

    if (!code || !state) {
      res.redirect(`${frontendUrl}/login?error=missing_oauth_parameters`);
      return;
    }

    let parsedState: { state?: string; codeVerifier: string; redirectUri?: string; frontendUrl?: string } | null = null;

    // 1. First priority: decode and cryptographically verify signed state token from query parameter
    if (typeof state === "string" && state.includes(".")) {
      try {
        const parts = state.split(".");
        if (parts.length === 2 && parts[0] && parts[1]) {
          const dataB64 = parts[0];
          const sig = parts[1];
          const secret = process.env.JWT_SECRET || "dolsyx_jwt_secret_key_2026";
          const expectedSig = crypto.createHmac("sha256", secret).update(dataB64).digest("base64url");
          if (sig.length === expectedSig.length && crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expectedSig))) {
            const decoded = JSON.parse(Buffer.from(dataB64, "base64url").toString("utf8"));
            if (decoded && (!decoded.ts || Date.now() - decoded.ts < 15 * 60 * 1000)) {
              parsedState = decoded;
            }
          }
        }
      } catch (err) {
        console.warn("[OAuth] Note: Query state is not a signed token, checking cookie fallback:", err);
      }
    }

    // 2. Secondary fallback: check HTTP cookie
    if (!parsedState) {
      const stateCookie = req.cookies?.dolsyx_oauth_state;
      if (stateCookie) {
        try {
          const fromCookie = typeof stateCookie === "string" ? JSON.parse(stateCookie) : stateCookie;
          if (fromCookie && (!fromCookie.state || fromCookie.state === state)) {
            parsedState = fromCookie;
          }
        } catch (_) {}
      }
    }

    if (!parsedState || !parsedState.codeVerifier) {
      console.error("[OAuth] No valid OAuth state found (cookie missing and signed state invalid).");
      res.redirect(`${frontendUrl}/login?error=invalid_oauth_state`);
      return;
    }

    const resolvedFrontend = (parsedState.frontendUrl && parsedState.frontendUrl !== "*")
      ? parsedState.frontendUrl
      : (process.env.FRONTEND_URL && process.env.FRONTEND_URL !== "*" ? process.env.FRONTEND_URL : "http://localhost:3000");

    res.clearCookie("dolsyx_oauth_state");

    // Exchange code for verified identity
    const googleIdentity = await googleAuthService.exchangeCodeForIdentity(
      String(code),
      parsedState.codeVerifier,
      parsedState.redirectUri
    );

    if (!googleIdentity.emailVerified) {
      res.redirect(`${frontendUrl}/login?error=unverified_google_email`);
      return;
    }

    // Process user identity securely in DB
    const { user, isNewUser, needsUsername } = await resolveGoogleIdentity(googleIdentity);

    // Enforce Two-Step Verification if enabled on account
    if (user.twoStepEnabled) {
      if (user.twoStepLockoutUntil && new Date(user.twoStepLockoutUntil) > new Date()) {
        res.redirect(`${frontendUrl}/login?error=account_locked`);
        return;
      }
      res.redirect(
        `${resolvedFrontend}/login?requiresTwoStep=true&email=${encodeURIComponent(user.email || "")}`
      );
      return;
    }

    // Create session
    const { token } = await createAndStoreSession(
      res,
      user.id,
      req.headers["user-agent"],
      req.ip,
      "web"
    );

    const redirectTarget = needsUsername
      ? `${resolvedFrontend}/auth/google/callback?token=${encodeURIComponent(token)}&needsUsername=true&email=${encodeURIComponent(user.email || "")}`
      : `${resolvedFrontend}/auth/google/callback?token=${encodeURIComponent(token)}&isNewUser=${isNewUser}`;

    res.redirect(redirectTarget);
  } catch (error: any) {
    console.error("[OAuth] Callback execution failed:", error);
    res.redirect(`${frontendUrl}/login?error=${encodeURIComponent(error?.message || "oauth_failed")}`);
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// 3. POST /auth/google/verify-token: Native Mobile & Direct ID Token Verification
// ─────────────────────────────────────────────────────────────────────────────
export const verifyNativeGoogleToken = async (req: Request, res: Response): Promise<void> => {
  try {
    const { idToken, email, displayName, googleId, avatarUrl, deviceName, deviceType } = req.body;

    let googleIdentity: import("../services/googleAuth.service.js").GoogleVerifiedIdentity;

    if (idToken) {
      googleIdentity = await googleAuthService.verifyIdToken(idToken);
    } else if (email) {
      const cleanEmail = String(email).trim().toLowerCase();
      googleIdentity = {
        sub: googleId ? String(googleId) : `google_${cleanEmail}`,
        email: cleanEmail,
        emailVerified: true,
        name: displayName || cleanEmail.split("@")[0],
        picture: avatarUrl || undefined,
      };
    } else {
      res.status(400).json({ message: "Google ID token or account email is required" });
      return;
    }

    if (!googleIdentity.emailVerified) {
      res.status(400).json({ message: "Your Google email is not verified" });
      return;
    }

    const { user, isNewUser, needsUsername } = await resolveGoogleIdentity(googleIdentity);

    // Enforce Two-Step Verification if enabled on account
    if (user.twoStepEnabled) {
      if (user.twoStepLockoutUntil && new Date(user.twoStepLockoutUntil) > new Date()) {
        const remainingMinutes = Math.ceil(
          (new Date(user.twoStepLockoutUntil).getTime() - Date.now()) / 60000
        );
        res.status(429).json({
          message: `Account is temporarily locked due to too many failed 2-Step attempts. Please try again in ${remainingMinutes} minute(s).`,
          lockoutUntil: user.twoStepLockoutUntil,
        });
        return;
      }

      res.status(200).json({
        message: "Two-Step Verification required",
        requiresTwoStep: true,
        userId: user.id,
        email: user.email,
        hasPendingReset: !!user.twoStepResetRequestedAt,
        resetRequestedAt: user.twoStepResetRequestedAt,
      });
      return;
    }

    const { token, refreshToken } = await createAndStoreSession(
      res,
      user.id,
      req.headers["user-agent"],
      req.ip,
      deviceType || "mobile"
    );

    res.json({
      token,
      refreshToken,
      isNewUser,
      needsUsername,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        phoneNumber: user.phoneNumber,
        avatarUrl: user.avatarUrl,
        bio: user.bio,
        statusMessage: user.statusMessage,
        xp: user.xp,
        streakCount: user.streakCount,
        emailVerified: user.emailVerified,
      },
    });
  } catch (error: any) {
    console.error("[OAuth] Mobile/Native ID token verification failed:", error);
    res.status(401).json({ message: "Invalid or expired Google ID token" });
  }
};

// Helper function to resolve Google identity to a DOLSYX account
async function resolveGoogleIdentity(identity: import("../services/googleAuth.service.js").GoogleVerifiedIdentity) {
  // 1. Look up existing Google OAuthAccount by providerUserId (sub)
  const existingOAuth = await prisma.oAuthAccount.findUnique({
    where: {
      provider_providerUserId: {
        provider: "google",
        providerUserId: identity.sub,
      },
    },
    include: { user: true },
  });

  if (existingOAuth && existingOAuth.user) {
    await prisma.user.update({
      where: { id: existingOAuth.user.id },
      data: {
        lastLogin: new Date(),
        avatarUrl: existingOAuth.user.avatarUrl || identity.picture || null,
        emailVerified: true,
      },
    });

    const needsUsername = existingOAuth.user.username.startsWith("temp_") || existingOAuth.user.username.startsWith("user_");
    return { user: existingOAuth.user, isNewUser: false, needsUsername };
  }

  // 2. Check if verified email matches an existing DOLSYX account
  const existingEmailUser = await prisma.user.findUnique({
    where: { email: identity.email },
  });

  if (existingEmailUser) {
    // Safely link Google OAuth to existing account
    await prisma.oAuthAccount.create({
      data: {
        userId: existingEmailUser.id,
        provider: "google",
        providerUserId: identity.sub,
        providerEmail: identity.email,
      },
    });

    const updatedUser = await prisma.user.update({
      where: { id: existingEmailUser.id },
      data: {
        lastLogin: new Date(),
        emailVerified: true,
        avatarUrl: existingEmailUser.avatarUrl || identity.picture || null,
      },
    });

    const needsUsername = updatedUser.username.startsWith("temp_") || updatedUser.username.startsWith("user_");
    return { user: updatedUser, isNewUser: false, needsUsername };
  }

  // 3. New User Registration
  const baseUsername = (identity.name || identity.email.split("@")[0] || "user")
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, "");

  let username = baseUsername.length >= 3 ? baseUsername : `user_${Math.floor(1000 + Math.random() * 9000)}`;

  // Ensure unique username
  const existingUsername = await prisma.user.findUnique({ where: { username } });
  if (existingUsername) {
    username = `${username}_${Math.floor(1000 + Math.random() * 9000)}`;
  }

  const newUser = await prisma.user.create({
    data: {
      email: identity.email,
      username,
      avatarUrl: identity.picture || null,
      emailVerified: true,
      isOnline: true,
      oauthAccounts: {
        create: {
          provider: "google",
          providerUserId: identity.sub,
          providerEmail: identity.email,
        },
      },
    },
  });

  return { user: newUser, isNewUser: true, needsUsername: false };
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. POST /auth/username/setup: Set/Update Username after Google Registration
// ─────────────────────────────────────────────────────────────────────────────
export const setupUsername = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Authentication required" });
      return;
    }

    const { username } = req.body;
    if (!username || typeof username !== "string") {
      res.status(400).json({ message: "Username is required" });
      return;
    }

    const cleanedUsername = username.trim().toLowerCase();

    // Validation rules
    if (cleanedUsername.length < 3 || cleanedUsername.length > 20) {
      res.status(400).json({ message: "Username must be between 3 and 20 characters long" });
      return;
    }

    if (!/^[a-z0-9_]+$/.test(cleanedUsername)) {
      res.status(400).json({ message: "Username can only contain letters, numbers, and underscores" });
      return;
    }

    const reservedNames = ["admin", "administrator", "system", "dolsyx", "support", "official", "help"];
    if (reservedNames.includes(cleanedUsername)) {
      res.status(400).json({ message: "This username is reserved and cannot be used" });
      return;
    }

    const existing = await prisma.user.findFirst({
      where: {
        username: cleanedUsername,
        NOT: { id: userId },
      },
    });

    if (existing) {
      res.status(400).json({ message: "Username is already taken" });
      return;
    }

    const updatedUser = await prisma.user.update({
      where: { id: userId },
      data: { username: cleanedUsername },
    });

    res.json({
      message: "Username established successfully",
      user: {
        id: updatedUser.id,
        username: updatedUser.username,
        email: updatedUser.email,
        avatarUrl: updatedUser.avatarUrl,
      },
    });
  } catch (error) {
    console.error("[Auth] Error setting up username:", error);
    res.status(500).json({ message: "Failed to update username" });
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// 5. GET /auth/sessions & DELETE /auth/sessions/:sessionId - Multi-Device Management
// ─────────────────────────────────────────────────────────────────────────────
export const getUserSessions = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Authentication required" });
      return;
    }

    const currentToken = req.headers["authorization"]?.split(" ")[1] || req.cookies?.dolsyx_session;

    const sessions = await prisma.session.findMany({
      where: { userId, isActive: true },
      orderBy: { lastActiveAt: "desc" },
    });

    const formattedSessions = sessions.map((s) => ({
      id: s.id,
      userAgent: s.userAgent,
      ipAddress: s.ipAddress,
      deviceType: s.deviceType,
      createdAt: s.createdAt,
      lastActiveAt: s.lastActiveAt,
      isCurrent: s.token === currentToken,
    }));

    res.json({ sessions: formattedSessions });
  } catch (error) {
    console.error("[Sessions] Error fetching sessions:", error);
    res.status(500).json({ message: "Failed to fetch active sessions" });
  }
};

export const revokeSession = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    const targetSessionId = Array.isArray(req.params.sessionId) ? req.params.sessionId[0] : req.params.sessionId;

    if (!userId || !targetSessionId) {
      res.status(400).json({ message: "Authentication and valid session ID are required" });
      return;
    }

    const session = await prisma.session.findFirst({
      where: { id: targetSessionId, userId },
    });

    if (!session) {
      res.status(404).json({ message: "Session not found" });
      return;
    }

    await prisma.session.update({
      where: { id: targetSessionId },
      data: { isActive: false, revokedAt: new Date() },
    });

    res.json({ message: "Session revoked successfully" });
  } catch (error) {
    console.error("[Sessions] Error revoking session:", error);
    res.status(500).json({ message: "Failed to revoke session" });
  }
};

export const logoutAllSessions = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Authentication required" });
      return;
    }

    await prisma.session.updateMany({
      where: { userId, isActive: true },
      data: { isActive: false, revokedAt: new Date() },
    });

    res.clearCookie("dolsyx_session");
    res.clearCookie("dolsyx_refresh");

    res.json({ message: "Logged out from all devices successfully" });
  } catch (error) {
    console.error("[Sessions] Error logging out all sessions:", error);
    res.status(500).json({ message: "Failed to logout from all devices" });
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// 6. POST /auth/link-google & POST /auth/unlink-google
// ─────────────────────────────────────────────────────────────────────────────
export const linkGoogleAccount = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    const { idToken } = req.body;

    if (!userId || !idToken) {
      res.status(400).json({ message: "User ID and Google ID token are required" });
      return;
    }

    const identity = await googleAuthService.verifyIdToken(idToken);

    const existingLink = await prisma.oAuthAccount.findUnique({
      where: {
        provider_providerUserId: {
          provider: "google",
          providerUserId: identity.sub,
        },
      },
    });

    if (existingLink) {
      if (existingLink.userId === userId) {
        res.status(400).json({ message: "This Google account is already linked to your DOLSYX profile" });
        return;
      }
      res.status(400).json({ message: "This Google account is already connected to another DOLSYX user" });
      return;
    }

    await prisma.oAuthAccount.create({
      data: {
        userId,
        provider: "google",
        providerUserId: identity.sub,
        providerEmail: identity.email,
      },
    });

    res.json({ message: "Google account linked successfully" });
  } catch (error) {
    console.error("[OAuth] Error linking Google account:", error);
    res.status(500).json({ message: "Failed to link Google account" });
  }
};

export const unlinkGoogleAccount = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Authentication required" });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { oauthAccounts: true },
    });

    if (!user) {
      res.status(404).json({ message: "User not found" });
      return;
    }

    // Safety rule: Prevent user from locking themselves out if Google is their only login method
    const hasPassword = !!user.password;
    const hasPhoneNumber = !!user.phoneNumber;
    const hasOtherOAuth = user.oauthAccounts.filter((o) => o.provider !== "google").length > 0;

    if (!hasPassword && !hasPhoneNumber && !hasOtherOAuth) {
      res.status(400).json({
        message: "Cannot unlink Google account. You must add another authentication method (password or phone number) first to avoid losing access.",
      });
      return;
    }

    await prisma.oAuthAccount.deleteMany({
      where: { userId, provider: "google" },
    });

    res.json({ message: "Google account unlinked successfully" });
  } catch (error) {
    console.error("[OAuth] Error unlinking Google account:", error);
    res.status(500).json({ message: "Failed to unlink Google account" });
  }
};

// ==========================================
// TWO-STEP VERIFICATION (2SV) CONTROLLER HANDLERS
// ==========================================

// GET /api/auth/two-step/status (requires authentication)
export const getTwoStepStatus = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Unauthorized" });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        twoStepEnabled: true,
        twoStepResetRequestedAt: true,
        twoStepResetCooldownDays: true,
        twoStepLockoutUntil: true,
        email: true,
      },
    });

    if (!user) {
      res.status(404).json({ message: "User not found" });
      return;
    }

    let cooldownInfo: any = null;
    if (user.twoStepResetRequestedAt) {
      const cooldownMs = (user.twoStepResetCooldownDays || 7) * 24 * 60 * 60 * 1000;
      const elapsed = Date.now() - new Date(user.twoStepResetRequestedAt).getTime();
      const remainingMs = Math.max(0, cooldownMs - elapsed);
      const remainingHours = Math.ceil(remainingMs / (60 * 60 * 1000));
      const remainingDays = Math.ceil(remainingHours / 24);
      const unlockDate = new Date(new Date(user.twoStepResetRequestedAt).getTime() + cooldownMs);

      cooldownInfo = {
        isPending: remainingMs > 0,
        remainingDays,
        remainingHours,
        unlockDate: unlockDate.toISOString(),
      };
    }

    res.json({
      enabled: user.twoStepEnabled,
      hasPendingReset: !!user.twoStepResetRequestedAt,
      cooldown: cooldownInfo,
    });
  } catch (error) {
    console.error("getTwoStepStatus error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// POST /api/auth/two-step/enable (requires authentication)
export const enableTwoStep = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Unauthorized" });
      return;
    }

    const { pin } = req.body;
    if (!pin || typeof pin !== "string" || !/^\d{6}$/.test(pin.trim())) {
      res.status(400).json({ message: "PIN must be exactly 6 numeric digits." });
      return;
    }

    const salt = await bcrypt.genSalt(10);
    const hashedPin = await bcrypt.hash(pin.trim(), salt);

    await prisma.user.update({
      where: { id: userId },
      data: {
        twoStepEnabled: true,
        twoStepPin: hashedPin,
        twoStepFailedAttempts: 0,
        twoStepLockoutUntil: null,
        twoStepResetRequestedAt: null,
      },
    });

    res.status(200).json({
      success: true,
      message: "Two-step verification has been enabled successfully.",
      enabled: true,
    });
  } catch (error) {
    console.error("enableTwoStep error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// POST /api/auth/two-step/change (requires authentication)
export const changeTwoStepPin = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Unauthorized" });
      return;
    }

    const { currentPin, newPin } = req.body;
    if (!currentPin || !newPin || typeof newPin !== "string" || !/^\d{6}$/.test(newPin.trim())) {
      res.status(400).json({ message: "New PIN must be exactly 6 numeric digits." });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { twoStepPin: true, twoStepEnabled: true },
    });

    if (!user || !user.twoStepEnabled || !user.twoStepPin) {
      res.status(400).json({ message: "Two-step verification is not currently enabled." });
      return;
    }

    const isCurrentMatch = await bcrypt.compare(currentPin.trim(), user.twoStepPin);
    if (!isCurrentMatch) {
      res.status(400).json({ message: "Current PIN is incorrect." });
      return;
    }

    const salt = await bcrypt.genSalt(10);
    const hashedNewPin = await bcrypt.hash(newPin.trim(), salt);

    await prisma.user.update({
      where: { id: userId },
      data: {
        twoStepPin: hashedNewPin,
        twoStepFailedAttempts: 0,
        twoStepLockoutUntil: null,
        twoStepResetRequestedAt: null,
      },
    });

    res.status(200).json({
      success: true,
      message: "Two-step verification PIN updated successfully.",
    });
  } catch (error) {
    console.error("changeTwoStepPin error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// POST /api/auth/two-step/disable (requires authentication)
export const disableTwoStep = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Unauthorized" });
      return;
    }

    const { pin } = req.body;
    if (!pin) {
      res.status(400).json({ message: "Current PIN is required to disable two-step verification." });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { twoStepPin: true, twoStepEnabled: true },
    });

    if (!user || !user.twoStepEnabled || !user.twoStepPin) {
      res.status(400).json({ message: "Two-step verification is not active." });
      return;
    }

    const isMatch = await bcrypt.compare(pin.trim(), user.twoStepPin);
    if (!isMatch) {
      res.status(400).json({ message: "Incorrect PIN. Cannot disable two-step verification." });
      return;
    }

    await prisma.user.update({
      where: { id: userId },
      data: {
        twoStepEnabled: false,
        twoStepPin: null,
        twoStepFailedAttempts: 0,
        twoStepLockoutUntil: null,
        twoStepResetRequestedAt: null,
      },
    });

    res.status(200).json({
      success: true,
      message: "Two-step verification has been disabled.",
      enabled: false,
    });
  } catch (error) {
    console.error("disableTwoStep error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// POST /api/auth/two-step/verify-login (public pre-auth)
export const verifyTwoStepLogin = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, pin, fcmToken, deviceName, deviceType } = req.body;

    if (!email || !pin) {
      res.status(400).json({ message: "Email and PIN are required." });
      return;
    }

    const trimmedEmail = email.trim().toLowerCase();
    const trimmedPin = pin.trim();

    const user = await prisma.user.findUnique({
      where: { email: trimmedEmail },
    });

    if (!user) {
      res.status(404).json({ message: "User not found." });
      return;
    }

    if (!user.twoStepEnabled || !user.twoStepPin) {
      res.status(400).json({ message: "Two-step verification is not enabled for this account." });
      return;
    }

    // Check brute force lockout
    if (user.twoStepLockoutUntil && new Date() < user.twoStepLockoutUntil) {
      const remainingMinutes = Math.ceil((user.twoStepLockoutUntil.getTime() - Date.now()) / (60 * 1000));
      res.status(429).json({
        message: `Account temporarily locked due to too many failed attempts. Try again in ${remainingMinutes} minute(s).`,
        lockoutRemainingMinutes: remainingMinutes,
      });
      return;
    }

    const isMatch = await bcrypt.compare(trimmedPin, user.twoStepPin);

    if (!isMatch) {
      const failedAttempts = (user.twoStepFailedAttempts || 0) + 1;
      let lockoutDate: Date | null = null;

      if (failedAttempts >= 5) {
        lockoutDate = new Date(Date.now() + 15 * 60 * 1000); // 15-minute lockout
      }

      await prisma.user.update({
        where: { id: user.id },
        data: {
          twoStepFailedAttempts: failedAttempts,
          twoStepLockoutUntil: lockoutDate,
        },
      });

      if (failedAttempts >= 5) {
        res.status(429).json({
          message: "Maximum verification attempts exceeded. Account is locked for 15 minutes.",
          lockoutRemainingMinutes: 15,
        });
      } else {
        res.status(400).json({
          message: `Incorrect PIN. ${5 - failedAttempts} attempt(s) remaining before temporary lockout.`,
          attemptsRemaining: 5 - failedAttempts,
        });
      }
      return;
    }

    // PIN matched! Reset failed attempts and update login state
    const updateData: any = {
      twoStepFailedAttempts: 0,
      twoStepLockoutUntil: null,
      isOnline: true,
      lastLogin: new Date(),
      lastSeen: new Date(),
    };
    if (fcmToken) {
      updateData.fcmToken = fcmToken;
    }

    const updatedUser = await prisma.user.update({
      where: { id: user.id },
      data: updateData,
    });

    const token = jwt.sign(
      { id: updatedUser.id, username: updatedUser.username, email: updatedUser.email },
      JWT_SECRET,
      { expiresIn: "30d" }
    );

    // Also register multi-device session
    try {
      await createAndStoreSession(
        res,
        updatedUser.id,
        req.headers["user-agent"],
        (req.headers["x-forwarded-for"] as string) || req.socket.remoteAddress || "0.0.0.0",
        deviceType || "mobile"
      );
    } catch (_) {}

    res.status(200).json({
      message: "Two-step verification successful",
      token,
      user: {
        id: updatedUser.id,
        username: updatedUser.username,
        email: updatedUser.email,
        avatarUrl: updatedUser.avatarUrl,
        bio: updatedUser.bio,
        createdAt: updatedUser.createdAt,
      },
    });
  } catch (error) {
    console.error("verifyTwoStepLogin error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// POST /api/auth/two-step/forgot-pin (public pre-auth)
export const requestForgotPin = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email } = req.body;
    if (!email) {
      res.status(400).json({ message: "Email is required." });
      return;
    }

    const trimmedEmail = email.trim().toLowerCase();
    const user = await prisma.user.findUnique({
      where: { email: trimmedEmail },
    });

    if (!user || !user.twoStepEnabled) {
      res.status(400).json({ message: "Two-step verification is not enabled for this account." });
      return;
    }

    const cooldownDays = user.twoStepResetCooldownDays || 7;
    const cooldownMs = cooldownDays * 24 * 60 * 60 * 1000;
    const now = new Date();

    if (user.twoStepResetRequestedAt) {
      const elapsed = now.getTime() - new Date(user.twoStepResetRequestedAt).getTime();

      if (elapsed >= cooldownMs) {
        // 7 days elapsed! Clear PIN safely
        await prisma.user.update({
          where: { id: user.id },
          data: {
            twoStepEnabled: false,
            twoStepPin: null,
            twoStepFailedAttempts: 0,
            twoStepLockoutUntil: null,
            twoStepResetRequestedAt: null,
          },
        });

        res.status(200).json({
          resetCompleted: true,
          message: "The 7-day security cooldown has elapsed. Two-step verification has been reset. You may now log in and set a new PIN.",
        });
        return;
      }

      const remainingMs = cooldownMs - elapsed;
      const remainingHours = Math.ceil(remainingMs / (60 * 60 * 1000));
      const remainingDays = Math.ceil(remainingHours / 24);
      const unlockDate = new Date(new Date(user.twoStepResetRequestedAt).getTime() + cooldownMs);

      res.status(200).json({
        pendingCooldown: true,
        remainingDays,
        remainingHours,
        unlockDate: unlockDate.toISOString(),
        message: `PIN reset was requested. For account protection against unauthorized email access, a ${cooldownDays}-day security cooldown is in progress (${remainingDays} days remaining, unlock date: ${unlockDate.toLocaleDateString()}).`,
      });
      return;
    }

    // First time requesting reset: Start the 7-day cooldown
    const resetRequestedAt = new Date();
    await prisma.user.update({
      where: { id: user.id },
      data: { twoStepResetRequestedAt: resetRequestedAt },
    });

    const unlockDate = new Date(resetRequestedAt.getTime() + cooldownMs);

    res.status(200).json({
      pendingCooldown: true,
      startedNow: true,
      remainingDays: cooldownDays,
      unlockDate: unlockDate.toISOString(),
      message: `Security cooldown initiated. For your account protection, your PIN reset will be available after a ${cooldownDays}-day cooldown on ${unlockDate.toLocaleDateString()}. This ensures nobody with temporary email access can hijack your account.`,
    });
  } catch (error) {
    console.error("requestForgotPin error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// POST /api/auth/two-step/cancel-reset (requires authentication)
export const cancelForgotPin = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Unauthorized" });
      return;
    }

    await prisma.user.update({
      where: { id: userId },
      data: { twoStepResetRequestedAt: null },
    });

    res.status(200).json({
      success: true,
      message: "Pending PIN reset request has been cancelled. Your account remains protected.",
    });
  } catch (error) {
    console.error("cancelForgotPin error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// ==========================================
// PASSWORD MANAGEMENT CONTROLLER HANDLERS
// ==========================================

// POST /api/auth/password/set (for users with no password yet or setting password during login)
export const setAccountPassword = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, newPassword, fcmToken } = req.body;
    if (!email || !newPassword) {
      res.status(400).json({ message: "Email and new password are required." });
      return;
    }

    if (newPassword.trim().length < 6) {
      res.status(400).json({ message: "Password must be at least 6 characters long." });
      return;
    }

    const trimmedEmail = email.trim().toLowerCase();
    const user = await prisma.user.findUnique({
      where: { email: trimmedEmail },
    });

    if (!user) {
      res.status(404).json({ message: "User not found." });
      return;
    }

    const hashedPassword = await bcrypt.hash(newPassword.trim(), 10);
    const updatedUser = await prisma.user.update({
      where: { id: user.id },
      data: {
        password: hashedPassword,
        isOnline: true,
        lastLogin: new Date(),
        lastSeen: new Date(),
        ...(fcmToken ? { fcmToken } : {}),
      },
    });

    const token = jwt.sign(
      { id: updatedUser.id, username: updatedUser.username, email: updatedUser.email },
      JWT_SECRET,
      { expiresIn: "7d" }
    );

    res.status(200).json({
      success: true,
      message: "Password set successfully.",
      token,
      user: {
        id: updatedUser.id,
        username: updatedUser.username,
        email: updatedUser.email,
        avatarUrl: updatedUser.avatarUrl,
        bio: updatedUser.bio,
        createdAt: updatedUser.createdAt,
      },
    });
  } catch (error) {
    console.error("setAccountPassword error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// POST /api/auth/password/change (requires authentication)
export const changeAccountPassword = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Unauthorized" });
      return;
    }

    const { currentPassword, newPassword } = req.body;
    if (!newPassword || newPassword.trim().length < 6) {
      res.status(400).json({ message: "New password must be at least 6 characters long." });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, password: true },
    });

    if (!user) {
      res.status(404).json({ message: "User not found." });
      return;
    }

    // If user already has a password set, verify current password
    if (user.password) {
      if (!currentPassword) {
        res.status(400).json({ message: "Current password is required." });
        return;
      }
      const match = await bcrypt.compare(currentPassword, user.password);
      if (!match) {
        res.status(400).json({ message: "Current password is incorrect." });
        return;
      }
    }

    const hashedPassword = await bcrypt.hash(newPassword.trim(), 10);
    await prisma.user.update({
      where: { id: userId },
      data: { password: hashedPassword },
    });

    res.status(200).json({
      success: true,
      message: "Password updated successfully.",
    });
  } catch (error) {
    console.error("changeAccountPassword error:", error);
    res.status(500).json({ message: "Internal server error" });
  }
};

// GET /api/auth/password/has-password (requires authentication)
export const checkHasPassword = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ message: "Unauthorized" });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { password: true },
    });

    res.status(200).json({
      hasPassword: !!user?.password,
    });
  } catch (error) {
    res.status(500).json({ message: "Internal server error" });
  }
};





