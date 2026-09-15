interface RateLimitRecord {
  timestamps: number[];
}

export class AIRateLimiter {
  private static userRequests: Map<string, RateLimitRecord> = new Map();
  private static readonly WINDOW_MS = 60 * 1000; // 1 minute window
  private static readonly MAX_REQUESTS_PER_WINDOW = parseInt(process.env.AI_RATE_LIMIT_PER_MINUTE || '30', 10);

  /**
   * Checks if user/IP has exceeded rate limit.
   */
  public static checkLimit(identifier: string): { allowed: boolean; remaining: number; resetMs: number } {
    const now = Date.now();
    let record = this.userRequests.get(identifier);

    if (!record) {
      record = { timestamps: [] };
      this.userRequests.set(identifier, record);
    }

    // Clean up timestamps older than sliding window
    record.timestamps = record.timestamps.filter(ts => now - ts < this.WINDOW_MS);

    if (record.timestamps.length >= this.MAX_REQUESTS_PER_WINDOW) {
      const oldest = record.timestamps[0] ?? now;
      const resetMs = Math.max(0, this.WINDOW_MS - (now - oldest));
      return {
        allowed: false,
        remaining: 0,
        resetMs,
      };
    }

    record.timestamps.push(now);
    const remaining = this.MAX_REQUESTS_PER_WINDOW - record.timestamps.length;
    return {
      allowed: true,
      remaining,
      resetMs: this.WINDOW_MS,
    };
  }

  /**
   * Periodic memory cleanup of inactive rate limit keys
   */
  public static cleanup(): void {
    const now = Date.now();
    for (const [key, record] of this.userRequests.entries()) {
      record.timestamps = record.timestamps.filter(ts => now - ts < this.WINDOW_MS);
      if (record.timestamps.length === 0) {
        this.userRequests.delete(key);
      }
    }
  }
}

// Clean up every 5 minutes
setInterval(() => AIRateLimiter.cleanup(), 5 * 60 * 1000).unref();
