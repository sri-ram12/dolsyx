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

interface CachedUser {
  user: any;
  cachedAt: number;
}

const userCache = new Map<string, CachedUser>();
const USER_CACHE_TTL_MS = 30000; // 30 seconds TTL

// Invalidate cache entry helper
export const invalidateUserCache = (userId: string) => {
  userCache.delete(userId);
};

// ── Session Heartbeat Throttle ────────────────────────────────────────────────
// Track per-token last heartbeat time so we only write lastActiveAt once per 5 min.
const heartbeatThrottle = new Map<string, number>();
const HEARTBEAT_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes

const updateSessionHeartbeat = (token: string): void => {
  const now = Date.now();
  const lastBeat = heartbeatThrottle.get(token) ?? 0;
  if (now - lastBeat < HEARTBEAT_INTERVAL_MS) return;
  heartbeatThrottle.set(token, now);

  // Prune stale entries if throttle map grows large
  if (heartbeatThrottle.size > 5000) {
    for (const [k, v] of heartbeatThrottle) {
      if (now - v > HEARTBEAT_INTERVAL_MS * 2) heartbeatThrottle.delete(k);
    }
  }

  // Fire-and-forget — never blocks the request
  prisma.session
    .updateMany({
      where: { token, isActive: true },
      data: { lastActiveAt: new Date() },
    })
    .catch(() => {});
};

export const authenticateToken = async (
  req: AuthRequest,
  res: Response,
  next: NextFunction
): Promise<void> => {
  const authHeader = req.headers["authorization"];
  let token = authHeader && authHeader.split(" ")[1];

  if (!token && (req as any).cookies?.dolsyx_session) {
    token = (req as any).cookies.dolsyx_session;
  }

  if (!token) {
    res.status(401).json({ message: "Access token or active session cookie required" });
    return;
  }

  try {
    const secret = process.env.JWT_SECRET || "dolsyx_super_secret_key_123456";
    const decoded = jwt.verify(token, secret) as {
      id: string;
      username: string;
    };

    if (!decoded || !decoded.id) {
      res.status(401).json({ message: "Invalid token payload" });
      return;
    }

    const now = Date.now();
    const cached = userCache.get(decoded.id);

    let user = cached && (now - cached.cachedAt < USER_CACHE_TTL_MS) ? cached.user : null;

    if (!user) {
      user = await prisma.user.findUnique({
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

      userCache.set(decoded.id, { user, cachedAt: now });
    }

    req.user = user;

    // Phase 17 & Security: Instant Revocation & IP Anomaly Defense
    // If a session record exists and has been marked inactive (revoked or logged out), deny immediately
    try {
      const session = await prisma.session.findUnique({
        where: { token },
        select: { id: true, isActive: true, ipAddress: true, deviceType: true },
      });
      if (session && !session.isActive) {
        res.status(401).json({ message: "Session has been revoked. Please log in again." });
        return;
      }
      if (session && session.ipAddress) {
        const clientIp = req.ip || req.socket.remoteAddress || "";
        if (clientIp && session.ipAddress !== clientIp) {
          // Dispatch security alert event via socket to user
          const io = req.app.get("io");
          if (io) {
            io.to(user.id).emit("SECURITY_ALERT_IP_CHANGE", {
              sessionId: session.id,
              deviceType: session.deviceType,
              previousIp: session.ipAddress,
              currentIp: clientIp,
              detectedAt: new Date().toISOString(),
            });
          }
        }
      }
    } catch (_) {
      // Non-blocking in case of DB transient error
    }

    // Phase 17: Heartbeat — update session lastActiveAt (throttled, fire-and-forget)
    updateSessionHeartbeat(token);

    next();
  } catch (error: any) {
    if (error?.name === "TokenExpiredError") {
      res.status(401).json({ message: "Token has expired. Please log in again." });
      return;
    }
    res.status(403).json({ message: "Invalid or expired token" });
  }
};
