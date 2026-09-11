import crypto from "crypto";

export type PairingStatus =
  | "PENDING"
  | "SCANNED"
  | "AWAITING_CONFIRMATION"
  | "APPROVED"
  | "CONSUMED"
  | "REJECTED"
  | "EXPIRED";

export interface DeviceMetadata {
  browser: string;
  os: string;
  platform: string;
  ipHash?: string | undefined;
  location?: string | undefined;
  userAgent?: string | undefined;
}

export interface PairingSession {
  pairingId: string;
  challengeHash: string;
  status: PairingStatus;
  createdAt: number;
  expiresAt: number;
  scannedAt?: number | undefined;
  approvedAt?: number | undefined;
  consumedAt?: number | undefined;
  scannedByUserId?: string | undefined;
  approvedUserId?: string | undefined;
  requestingDeviceMetadata: DeviceMetadata;
  createdSessionId?: string | undefined;
}

// In-memory store for active pairing sessions (synchronized server-side state machine)
const activePairingSessions = new Map<string, PairingSession>();

// Parse User-Agent into privacy-safe, clean device descriptors
export function parseUserAgent(ua?: string): { browser: string; os: string; platform: string } {
  if (!ua) {
    return { browser: "Web Browser", os: "Unknown OS", platform: "Computer" };
  }

  let browser = "Web Browser";
  if (ua.includes("Edg/") || ua.includes("Edge")) browser = "Microsoft Edge";
  else if ((ua.includes("Chrome/") || ua.includes("Chrome")) && !ua.includes("Chromium")) browser = "Google Chrome";
  else if (ua.includes("Firefox/") || ua.includes("Firefox")) browser = "Mozilla Firefox";
  else if (ua.includes("Safari/") || ua.includes("Safari")) browser = "Apple Safari";
  else if (ua.includes("Opera") || ua.includes("OPR/")) browser = "Opera";

  let os = "Desktop";
  let platform = "Computer";
  if (ua.includes("Windows NT 10.0") || ua.includes("Windows NT 11.0")) {
    os = "Windows";
    platform = "Windows PC";
  } else if (ua.includes("Windows")) {
    os = "Windows";
    platform = "Windows PC";
  } else if (ua.includes("Mac OS X")) {
    os = "macOS";
    platform = "Mac";
  } else if (ua.includes("Linux") && !ua.includes("Android")) {
    os = "Linux";
    platform = "Linux Computer";
  } else if (ua.includes("Android")) {
    os = "Android";
    platform = "Android Device";
  } else if (ua.includes("iPhone") || ua.includes("iPad")) {
    os = "iOS";
    platform = "Apple Device";
  }

  return { browser, os, platform };
}

// Hash IP address for privacy-safe audit trails
export function hashIp(ip?: string): string {
  if (!ip) return "unknown";
  return crypto.createHash("sha256").update(ip + "dolsyx_salt_2026").digest("hex").substring(0, 12);
}

// Periodic cleanup of expired pairing sessions every 30 seconds
setInterval(() => {
  const now = Date.now();
  for (const [id, session] of activePairingSessions.entries()) {
    if (now > session.expiresAt + 60000 || session.status === "CONSUMED") {
      activePairingSessions.delete(id);
    }
  }
}, 30000);

export class PairingService {
  /**
   * Create a new temporary pairing session
   * @param metadata Client user-agent and IP information
   * @param ttlSeconds Expiration in seconds (default: 90 seconds)
   */
  static createSession(
    metadata: { userAgent?: string; ip?: string },
    ttlSeconds: number = 90
  ): { pairingId: string; challenge: string; expiresAt: number } {
    const pairingId = `dolsyx_pair_${crypto.randomBytes(16).toString("hex")}`;
    const challenge = crypto.randomBytes(32).toString("hex");
    const challengeHash = crypto.createHash("sha256").update(challenge).digest("hex");

    const parsedDevice = parseUserAgent(metadata.userAgent);
    const ipHash = hashIp(metadata.ip);

    const now = Date.now();
    const expiresAt = now + ttlSeconds * 1000;

    const session: PairingSession = {
      pairingId,
      challengeHash,
      status: "PENDING",
      createdAt: now,
      expiresAt,
      requestingDeviceMetadata: {
        ...parsedDevice,
        ipHash,
        location: "Local Network",
        userAgent: metadata.userAgent,
      },
    };

    activePairingSessions.set(pairingId, session);

    return {
      pairingId,
      challenge,
      expiresAt,
    };
  }

  /**
   * Get an active pairing session by ID, auto-marking EXPIRED if time exceeded
   */
  static getSession(pairingId: string): PairingSession | null {
    const session = activePairingSessions.get(pairingId);
    if (!session) return null;

    if (Date.now() > session.expiresAt && session.status !== "CONSUMED") {
      session.status = "EXPIRED";
    }

    return session;
  }

  /**
   * Verify challenge validity using constant-time comparison
   */
  private static verifyChallenge(rawChallenge: string, expectedHash: string): boolean {
    if (!rawChallenge) return false;
    const computedHash = crypto.createHash("sha256").update(rawChallenge).digest("hex");
    try {
      const bufA = Buffer.from(computedHash, "utf8");
      const bufB = Buffer.from(expectedHash, "utf8");
      return bufA.length === bufB.length && crypto.timingSafeEqual(bufA, bufB);
    } catch {
      return false;
    }
  }

  /**
   * Mobile device scans the QR code
   */
  static scanSession(
    pairingId: string,
    challenge: string,
    userId: string
  ): { success: boolean; session?: PairingSession; error?: string } {
    const session = this.getSession(pairingId);
    if (!session) {
      return { success: false, error: "QR pairing session not found" };
    }

    if (session.status === "EXPIRED" || Date.now() > session.expiresAt) {
      session.status = "EXPIRED";
      return { success: false, error: "This QR code has expired" };
    }

    if (session.status === "CONSUMED") {
      return { success: false, error: "This QR code has already been used" };
    }

    if (session.status !== "PENDING") {
      return { success: false, error: `Invalid pairing state: ${session.status}` };
    }

    if (!this.verifyChallenge(challenge, session.challengeHash)) {
      return { success: false, error: "Invalid cryptographic challenge" };
    }

    // Transition to SCANNED
    session.status = "SCANNED";
    session.scannedAt = Date.now();
    session.scannedByUserId = userId;

    return { success: true, session };
  }

  /**
   * Mobile user explicitly approves the pairing request
   */
  static approveSession(
    pairingId: string,
    challenge: string,
    userId: string
  ): { success: boolean; session?: PairingSession; error?: string } {
    const session = this.getSession(pairingId);
    if (!session) {
      return { success: false, error: "QR pairing session not found" };
    }

    if (session.status === "EXPIRED" || Date.now() > session.expiresAt) {
      session.status = "EXPIRED";
      return { success: false, error: "This QR code has expired" };
    }

    if (session.status === "CONSUMED") {
      return { success: false, error: "This QR code has already been used" };
    }

    // Only allow approval if it was scanned by the same authenticated user
    if (session.status !== "SCANNED" && session.status !== "AWAITING_CONFIRMATION") {
      return { success: false, error: `Cannot approve pairing in status: ${session.status}` };
    }

    if (session.scannedByUserId !== userId) {
      return { success: false, error: "Pairing session does not belong to your authenticated user" };
    }

    if (!this.verifyChallenge(challenge, session.challengeHash)) {
      return { success: false, error: "Invalid cryptographic challenge" };
    }

    // Transition to APPROVED
    session.status = "APPROVED";
    session.approvedAt = Date.now();
    session.approvedUserId = userId;

    return { success: true, session };
  }

  /**
   * Mobile user explicitly cancels / rejects the pairing request
   */
  static rejectSession(
    pairingId: string,
    userId: string
  ): { success: boolean; error?: string } {
    const session = this.getSession(pairingId);
    if (!session) {
      return { success: false, error: "QR pairing session not found" };
    }

    if (session.scannedByUserId && session.scannedByUserId !== userId) {
      return { success: false, error: "Unauthorized rejection" };
    }

    session.status = "REJECTED";
    return { success: true };
  }

  /**
   * Laptop exchanges approved state for an independent authenticated session
   * Atomically transitions APPROVED -> CONSUMED (single-use guarantee)
   */
  static consumeSession(
    pairingId: string,
    challenge: string
  ): {
    success: boolean;
    userId?: string;
    deviceMetadata?: DeviceMetadata;
    error?: string;
  } {
    const session = this.getSession(pairingId);
    if (!session) {
      return { success: false, error: "QR pairing session not found" };
    }

    if (session.status === "CONSUMED") {
      return { success: false, error: "This pairing session has already been consumed" };
    }

    if (session.status === "EXPIRED" || Date.now() > session.expiresAt) {
      session.status = "EXPIRED";
      return { success: false, error: "This pairing session has expired" };
    }

    if (session.status !== "APPROVED") {
      return { success: false, error: `Pairing session is not approved (Status: ${session.status})` };
    }

    if (!session.approvedUserId) {
      return { success: false, error: "No authenticated user associated with this pairing" };
    }

    if (!this.verifyChallenge(challenge, session.challengeHash)) {
      return { success: false, error: "Invalid cryptographic challenge" };
    }

    // Atomic transition to CONSUMED
    session.status = "CONSUMED";
    session.consumedAt = Date.now();

    return {
      success: true,
      userId: session.approvedUserId,
      deviceMetadata: session.requestingDeviceMetadata,
    };
  }

  /**
   * Helper for testing/clearing state
   */
  static clearAll(): void {
    activePairingSessions.clear();
  }
}
