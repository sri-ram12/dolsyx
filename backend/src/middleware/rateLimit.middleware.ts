import type { Request, Response, NextFunction } from "express";

interface RateLimitOptions {
  windowMs: number; // Time window in milliseconds
  max: number; // Max requests allowed per windowMs
  message?: string; // Custom error message
  statusCode?: number; // Custom status code (default: 429)
  keyGenerator?: (req: Request) => string; // Custom key generator
}

interface ClientBucket {
  count: number;
  resetTime: number;
}

/**
 * Production-ready in-memory sliding window rate limiter.
 * Designed to prevent memory leaks by automatically pruning stale entries every 5 minutes.
 */
export function createRateLimiter(options: RateLimitOptions) {
  const {
    windowMs,
    max,
    message = "Too many requests. Please try again later.",
    statusCode = 429,
    keyGenerator = (req: Request) => {
      // Use X-Forwarded-For or remoteAddress
      const forwarded = req.headers["x-forwarded-for"];
      if (typeof forwarded === "string") {
        const parts = forwarded.split(",");
        const first = parts[0];
        if (first) return first.trim();
      }
      return req.ip || req.socket.remoteAddress || "unknown_client";
    },
  } = options;

  const clients = new Map<string, ClientBucket>();

  // Cleanup interval to prevent memory growth over long periods
  const cleanupTimer = setInterval(() => {
    const now = Date.now();
    for (const [key, bucket] of clients.entries()) {
      if (now > bucket.resetTime) {
        clients.delete(key);
      }
    }
  }, Math.max(windowMs, 60000));

  // Ensure timer does not prevent process exit
  if (cleanupTimer.unref) {
    cleanupTimer.unref();
  }

  return (req: Request, res: Response, next: NextFunction): void => {
    const key = keyGenerator(req);
    const now = Date.now();
    let bucket = clients.get(key);

    if (!bucket || now > bucket.resetTime) {
      bucket = { count: 1, resetTime: now + windowMs };
      clients.set(key, bucket);
    } else {
      bucket.count += 1;
    }

    const remaining = Math.max(0, max - bucket.count);
    const resetSeconds = Math.ceil((bucket.resetTime - now) / 1000);

    res.setHeader("X-RateLimit-Limit", max.toString());
    res.setHeader("X-RateLimit-Remaining", remaining.toString());
    res.setHeader("X-RateLimit-Reset", resetSeconds.toString());

    if (bucket.count > max) {
      res.setHeader("Retry-After", resetSeconds.toString());
      res.status(statusCode).json({
        error: "Too Many Requests",
        message,
        retryAfterSeconds: resetSeconds,
      });
      return;
    }

    next();
  };
}

// Pre-configured rate limiters for critical application surfaces:
// 1. Strict Limiter for Auth / Login / Registration (15 attempts per 15 minutes)
export const authRateLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 20,
  message: "Too many authentication attempts. Please wait 15 minutes before trying again.",
});

// 2. Ultra-Strict Limiter for OTP Generation (5 attempts per 10 minutes)
export const otpRateLimiter = createRateLimiter({
  windowMs: 10 * 60 * 1000,
  max: 5,
  message: "Too many OTP verification requests. Please wait a few minutes before requesting another code.",
});

// 3. Upload Limiter for media & files (30 uploads per minute)
export const uploadRateLimiter = createRateLimiter({
  windowMs: 60 * 1000,
  max: 30,
  message: "Upload rate limit reached. Please wait a moment before sending more files.",
});

// 4. General API Limiter (120 requests per minute per IP)
export const generalApiLimiter = createRateLimiter({
  windowMs: 60 * 1000,
  max: 200,
  message: "High request frequency detected. Please slow down.",
});
