import type { Request, Response } from "express";
import crypto from "crypto";
import jwt from "jsonwebtoken";
import { prisma } from "../config/db.js";
import type { AuthRequest } from "../middleware/auth.middleware.js";
import { PairingService } from "../services/pairing.service.js";

const JWT_SECRET = process.env.JWT_SECRET || "dolsyx_super_secret_key_123456";

/**
 * 1. POST /api/devices/pair/create
 * Laptop generates a temporary high-entropy pairing reference & challenge
 */
export const createPairing = async (req: Request, res: Response): Promise<void> => {
  try {
    const userAgent = req.headers["user-agent"] || "";
    const ip = req.ip || req.socket.remoteAddress || "";

    const session = PairingService.createSession({ userAgent, ip }, 90);

    res.json({
      success: true,
      pairingId: session.pairingId,
      challenge: session.challenge,
      expiresAt: session.expiresAt,
      status: "PENDING",
    });
  } catch (error) {
    console.error("[DevicePairing] Error creating pairing session:", error);
    res.status(500).json({ success: false, message: "Failed to create pairing session" });
  }
};

/**
 * 2. POST /api/devices/pair/scan
 * Mobile device scans QR code with Bearer token authentication
 */
export const scanPairing = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ success: false, message: "Authentication required to scan pairing QR" });
      return;
    }

    const { pairingId, challenge } = req.body;
    if (!pairingId || !challenge) {
      res.status(400).json({ success: false, message: "pairingId and challenge are required" });
      return;
    }

    const result = PairingService.scanSession(pairingId, challenge, userId);
    if (!result.success || !result.session) {
      res.status(400).json({ success: false, message: result.error || "Failed to scan pairing QR" });
      return;
    }

    // Broadcast PAIRING_SCANNED via WebSocket to laptop room
    const io = req.app.get("io");
    if (io) {
      io.to(`pairing_${pairingId}`).emit("PAIRING_SCANNED", {
        pairingId,
        status: "SCANNED",
        timestamp: Date.now(),
      });
    }

    res.json({
      success: true,
      status: "SCANNED",
      device: {
        browser: result.session.requestingDeviceMetadata.browser,
        os: result.session.requestingDeviceMetadata.os,
        platform: result.session.requestingDeviceMetadata.platform,
        location: result.session.requestingDeviceMetadata.location || "Local Network",
        requestedAt: result.session.createdAt,
      },
    });
  } catch (error) {
    console.error("[DevicePairing] Error scanning pairing session:", error);
    res.status(500).json({ success: false, message: "Failed to scan pairing session" });
  }
};

/**
 * 3. POST /api/devices/pair/approve
 * Mobile user explicitly confirms and approves linking the laptop
 */
export const approvePairing = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ success: false, message: "Authentication required to approve pairing" });
      return;
    }

    const { pairingId, challenge } = req.body;
    if (!pairingId || !challenge) {
      res.status(400).json({ success: false, message: "pairingId and challenge are required" });
      return;
    }

    const result = PairingService.approveSession(pairingId, challenge, userId);
    if (!result.success || !result.session) {
      res.status(400).json({ success: false, message: result.error || "Failed to approve pairing" });
      return;
    }

    // Broadcast PAIRING_APPROVED via WebSocket to laptop room
    const io = req.app.get("io");
    if (io) {
      io.to(`pairing_${pairingId}`).emit("PAIRING_APPROVED", {
        pairingId,
        status: "APPROVED",
        timestamp: Date.now(),
      });
    }

    res.json({
      success: true,
      message: "Device pairing approved successfully",
      status: "APPROVED",
    });
  } catch (error) {
    console.error("[DevicePairing] Error approving pairing session:", error);
    res.status(500).json({ success: false, message: "Failed to approve pairing session" });
  }
};

/**
 * 4. POST /api/devices/pair/reject
 * Mobile user cancels / rejects device linking
 */
export const rejectPairing = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ success: false, message: "Authentication required" });
      return;
    }

    const { pairingId } = req.body;
    if (!pairingId) {
      res.status(400).json({ success: false, message: "pairingId is required" });
      return;
    }

    const result = PairingService.rejectSession(pairingId, userId);
    if (!result.success) {
      res.status(400).json({ success: false, message: result.error || "Failed to reject pairing" });
      return;
    }

    // Broadcast PAIRING_REJECTED via WebSocket to laptop room
    const io = req.app.get("io");
    if (io) {
      io.to(`pairing_${pairingId}`).emit("PAIRING_REJECTED", {
        pairingId,
        status: "REJECTED",
      });
    }

    res.json({ success: true, message: "Device pairing cancelled" });
  } catch (error) {
    console.error("[DevicePairing] Error rejecting pairing session:", error);
    res.status(500).json({ success: false, message: "Failed to reject pairing session" });
  }
};

/**
 * 5. POST /api/devices/pair/consume
 * Laptop exchanges approved pairing for an independent authenticated session
 */
export const consumePairing = async (req: Request, res: Response): Promise<void> => {
  try {
    const { pairingId, challenge } = req.body;
    if (!pairingId || !challenge) {
      res.status(400).json({ success: false, message: "pairingId and challenge are required" });
      return;
    }

    // Atomic validation and transition to CONSUMED
    const result = PairingService.consumeSession(pairingId, challenge);
    if (!result.success || !result.userId) {
      res.status(400).json({ success: false, message: result.error || "Failed to consume pairing" });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: result.userId },
      select: {
        id: true,
        username: true,
        email: true,
        phoneNumber: true,
        avatarUrl: true,
        bio: true,
        createdAt: true,
      },
    });

    if (!user) {
      res.status(404).json({ success: false, message: "User not found" });
      return;
    }

    // Create an INDEPENDENT Laptop Session (never copy mobile session)
    const userAgent = req.headers["user-agent"] || result.deviceMetadata?.userAgent || "DOLSYX Web Browser";
    const ipAddress = req.ip || req.socket.remoteAddress || "0.0.0.0";
    const deviceName = `${result.deviceMetadata?.browser || "Web"} on ${result.deviceMetadata?.os || "PC"}`;

    const token = jwt.sign(
      { id: user.id, username: user.username, email: user.email },
      JWT_SECRET,
      { expiresIn: "30d" }
    );

    const refreshToken = crypto.randomBytes(40).toString("hex");
    const refreshTokenHash = crypto.createHash("sha256").update(refreshToken).digest("hex");
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

    const session = await prisma.session.create({
      data: {
        userId: user.id,
        token,
        refreshTokenHash,
        userAgent,
        ipAddress,
        deviceName,
        deviceType: "web",
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

    res.json({
      success: true,
      message: "Laptop authenticated successfully",
      token,
      refreshToken,
      sessionId: session.id,
      user,
    });
  } catch (error) {
    console.error("[DevicePairing] Error consuming pairing session:", error);
    res.status(500).json({ success: false, message: "Failed to establish laptop session" });
  }
};

/**
 * 6. GET /api/devices/pair/status/:pairingId
 * Polling fallback for status checks
 */
export const getPairingStatus = async (req: Request, res: Response): Promise<void> => {
  try {
    const rawId = req.params["pairingId"];
    const pairingId = Array.isArray(rawId) ? rawId[0] : rawId;

    if (!pairingId) {
      res.status(400).json({ status: "ERROR", message: "Missing pairingId" });
      return;
    }

    const session = PairingService.getSession(pairingId);
    if (!session) {
      res.json({ status: "EXPIRED" });
      return;
    }

    res.json({
      status: session.status,
      expiresAt: session.expiresAt,
      device: session.status === "SCANNED" || session.status === "APPROVED"
        ? {
            browser: session.requestingDeviceMetadata.browser,
            os: session.requestingDeviceMetadata.os,
            platform: session.requestingDeviceMetadata.platform,
          }
        : undefined,
    });
  } catch (error) {
    res.status(500).json({ status: "ERROR", message: "Failed to get pairing status" });
  }
};

/**
 * 7. GET /api/devices
 * List all active linked devices / sessions for authenticated user
 */
export const getLinkedDevices = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ success: false, message: "Authentication required" });
      return;
    }

    const currentToken = req.headers["authorization"]?.split(" ")[1] || (req as any).cookies?.dolsyx_session;

    const sessions = await prisma.session.findMany({
      where: { userId, isActive: true },
      orderBy: { lastActiveAt: "desc" },
    });

    const formattedDevices = sessions.map((s) => ({
      id: s.id,
      name: s.deviceName || `${s.deviceType.toUpperCase()} Device`,
      deviceType: s.deviceType,
      userAgent: s.userAgent,
      lastActive: s.lastActiveAt.toISOString(),
      createdAt: s.createdAt.toISOString(),
      isCurrent: s.token === currentToken,
      status: s.token === currentToken ? "Active now" : "Linked",
    }));

    res.json({ success: true, devices: formattedDevices });
  } catch (error) {
    console.error("[DevicePairing] Error fetching linked devices:", error);
    res.status(500).json({ success: false, message: "Failed to fetch linked devices" });
  }
};

/**
 * 8. DELETE /api/devices/:sessionId
 * Revoke a linked device / session and immediately notify via WebSocket
 */
export const revokeLinkedDevice = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    const rawSessionId = req.params["sessionId"];
    const targetSessionId = Array.isArray(rawSessionId) ? rawSessionId[0] : rawSessionId;

    if (!userId || !targetSessionId) {
      res.status(400).json({ success: false, message: "Valid sessionId required" });
      return;
    }

    const session = await prisma.session.findFirst({
      where: { id: targetSessionId, userId },
    });

    if (!session) {
      res.status(404).json({ success: false, message: "Session not found" });
      return;
    }

    // Mark inactive and record revocation time
    await prisma.session.update({
      where: { id: targetSessionId },
      data: { isActive: false, revokedAt: new Date() },
    });

    // Notify connected clients via WebSocket about device revocation
    const io = req.app.get("io");
    if (io) {
      io.to(userId).emit("DEVICE_REVOKED", {
        sessionId: targetSessionId,
        revokedAt: new Date().toISOString(),
      });
    }

    res.json({ success: true, message: "Device logged out successfully" });
  } catch (error) {
    console.error("[DevicePairing] Error revoking device session:", error);
    res.status(500).json({ success: false, message: "Failed to revoke device session" });
  }
};

/**
 * 9. POST /api/devices/logout-all
 * Log out all other linked devices
 */
export const logoutAllOtherDevices = async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ success: false, message: "Authentication required" });
      return;
    }

    const currentToken = req.headers["authorization"]?.split(" ")[1] || (req as any).cookies?.dolsyx_session;

    // Revoke all other sessions
    await prisma.session.updateMany({
      where: {
        userId,
        isActive: true,
        ...(currentToken ? { token: { not: currentToken } } : {}),
      },
      data: { isActive: false, revokedAt: new Date() },
    });

    // Notify all devices of revocation
    const io = req.app.get("io");
    if (io) {
      io.to(userId).emit("DEVICE_REVOKED", {
        allOtherDevices: true,
        revokedAt: new Date().toISOString(),
      });
    }

    res.json({ success: true, message: "All other devices logged out successfully" });
  } catch (error) {
    console.error("[DevicePairing] Error logging out all other devices:", error);
    res.status(500).json({ success: false, message: "Failed to log out devices" });
  }
};
