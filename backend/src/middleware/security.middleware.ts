import type { Request, Response, NextFunction } from "express";
import crypto from "crypto";

const DOLSYX_APP_SECRET = process.env.DOLSYX_APP_SECRET || "dolsyx_tamper_seal_2025_sec_token";
const MIN_SUPPORTED_VERSION = "1.0.0";

/**
 * Parses semantic version string "X.Y.Z" into an integer tuple for comparison.
 */
function parseSemVer(v: string): [number, number, number] {
  const parts = v.replace(/[^0-9.]/g, "").split(".").map((n) => Number(n) || 0);
  return [parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0];
}

function isVersionSupported(clientVer: string, minVer: string): boolean {
  const [cMaj, cMin, cPat] = parseSemVer(clientVer);
  const [mMaj, mMin, mPat] = parseSemVer(minVer);

  if (cMaj !== mMaj) return cMaj > mMaj;
  if (cMin !== mMin) return cMin > mMin;
  return cPat >= mPat;
}

/**
 * Standard OWASP security headers middleware.
 * Hardens API responses against MIME sniffing, clickjacking, and XSS attacks.
 */
export function securityHeadersMiddleware(req: Request, res: Response, next: NextFunction): void {
  // Prevent MIME-sniffing
  res.setHeader("X-Content-Type-Options", "nosniff");
  // Prevent clickjacking
  res.setHeader("X-Frame-Options", "DENY");
  // XSS protection for older browsers
  res.setHeader("X-XSS-Protection", "1; mode=block");
  // Enforce HTTPS
  res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload");
  // Control referrer leakage
  res.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
  // Disable dangerous permissions
  res.setHeader("Permissions-Policy", "camera=(self), microphone=(self), geolocation=(self)");

  next();
}

/**
 * Anti-Tamper & Request Integrity Verification Middleware.
 * Validates request signatures (HMAC-SHA256) when present and prevents replay attacks.
 */
export function requestIntegrityMiddleware(req: Request, res: Response, next: NextFunction): void {
  const signature = req.headers["x-dolsyx-signature"] as string | undefined;
  const timestamp = req.headers["x-dolsyx-timestamp"] as string | undefined;
  const clientVersion = req.headers["x-dolsyx-client-version"] as string | undefined;

  // 1. Client Version Check (if supplied by native app)
  if (clientVersion) {
    if (!isVersionSupported(clientVersion, MIN_SUPPORTED_VERSION)) {
      res.status(426).json({
        error: "Upgrade Required",
        message: `Your client version (${clientVersion}) is deprecated. Minimum required is ${MIN_SUPPORTED_VERSION}. Please update the app.`,
      });
      return;
    }
  }

  // 2. Request Signature Verification (HMAC-SHA256)
  // If the client provides a signature, verify its cryptographic authenticity
  if (signature && timestamp) {
    const ts = parseInt(timestamp, 10);
    const now = Date.now();

    // Replay attack window: Reject requests older or newer than 5 minutes (300,000 ms)
    if (isNaN(ts) || Math.abs(now - ts) > 300000) {
      res.status(401).json({
        error: "Signature Expired",
        message: "Request timestamp is outside the acceptable integrity window.",
      });
      return;
    }

    // Compute expected HMAC over: method + path + timestamp + serialized body
    const bodyStr = req.body && Object.keys(req.body).length > 0 ? JSON.stringify(req.body) : "";
    const canonicalPayload = `${req.method.toUpperCase()}:${req.originalUrl || req.url}:${timestamp}:${bodyStr}`;

    const expectedSignature = crypto
      .createHmac("sha256", DOLSYX_APP_SECRET)
      .update(canonicalPayload)
      .digest("hex");

    const sigBuf = Buffer.from(signature, "hex");
    const expBuf = Buffer.from(expectedSignature, "hex");

    if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
      res.status(403).json({
        error: "Tampering Detected",
        message: "Request integrity signature mismatch. Operation denied.",
      });
      return;
    }
  }

  next();
}

/**
 * Rate-limit bypass detection and IP spoofing prevention middleware.
 * Validates and normalizes client IP headers.
 */
export function antiSpoofingMiddleware(req: Request, _res: Response, next: NextFunction): void {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string") {
    // Detect abnormal header structure (e.g., CRLF injection or excessively long proxy chains)
    if (forwarded.includes("\r") || forwarded.includes("\n") || forwarded.length > 500) {
      console.warn("[Security] Suspicious X-Forwarded-For header detected:", forwarded);
      // Strip suspicious header
      delete req.headers["x-forwarded-for"];
    }
  }
  next();
}
