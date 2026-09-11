import test from "node:test";
import assert from "node:assert/strict";
import { createRateLimiter } from "../middleware/rateLimit.middleware.js";

test("DOLSYX Reliability & Resilience Test Suite", async (t) => {

  await t.test("1. Rate Limiter: Allows requests under limit and sets correct rate headers", () => {
    const limiter = createRateLimiter({
      windowMs: 5000,
      max: 3,
      message: "Limit exceeded",
      keyGenerator: () => "test-client-1",
    });

    const headers: Record<string, string> = {};
    let statusSet = 200;
    let nextCalled = false;

    const mockReq: any = { headers: {}, ip: "127.0.0.1", socket: {} };
    const mockRes: any = {
      setHeader: (key: string, val: string) => { headers[key] = val; },
      status: (code: number) => { statusSet = code; return mockRes; },
      json: (_body: any) => mockRes,
    };
    const mockNext = () => { nextCalled = true; };

    // Request 1
    limiter(mockReq, mockRes, mockNext);
    assert.equal(nextCalled, true, "First request must pass through");
    assert.equal(headers["X-RateLimit-Limit"], "3");
    assert.equal(headers["X-RateLimit-Remaining"], "2");

    // Request 2
    nextCalled = false;
    limiter(mockReq, mockRes, mockNext);
    assert.equal(nextCalled, true, "Second request must pass through");
    assert.equal(headers["X-RateLimit-Remaining"], "1");

    // Request 3
    nextCalled = false;
    limiter(mockReq, mockRes, mockNext);
    assert.equal(nextCalled, true, "Third request must pass through");
    assert.equal(headers["X-RateLimit-Remaining"], "0");

    // Request 4 (Should be blocked)
    nextCalled = false;
    let errorJson: any = null;
    mockRes.json = (body: any) => { errorJson = body; return mockRes; };
    limiter(mockReq, mockRes, mockNext);

    assert.equal(nextCalled, false, "Fourth request must be blocked");
    assert.equal(statusSet, 429, "Response status must be 429 Too Many Requests");
    assert.equal(errorJson.error, "Too Many Requests");
    assert.ok(headers["Retry-After"], "Retry-After header must be provided");
  });

  await t.test("2. Rate Limiter: Multiple clients are isolated independently", () => {
    const limiter = createRateLimiter({
      windowMs: 5000,
      max: 1,
      keyGenerator: (req: any) => req.clientIp,
    });

    let clientANext = false;
    let clientBNext = false;

    const mockRes: any = {
      setHeader: () => {},
      status: () => mockRes,
      json: () => mockRes,
    };

    // Client A request 1 (passes)
    limiter({ clientIp: "10.0.0.1", headers: {}, socket: {} } as any, mockRes, () => { clientANext = true; });
    assert.equal(clientANext, true);

    // Client B request 1 (passes, not affected by A)
    limiter({ clientIp: "10.0.0.2", headers: {}, socket: {} } as any, mockRes, () => { clientBNext = true; });
    assert.equal(clientBNext, true);

    // Client A request 2 (blocked)
    clientANext = false;
    limiter({ clientIp: "10.0.0.1", headers: {}, socket: {} } as any, mockRes, () => { clientANext = true; });
    assert.equal(clientANext, false, "Client A should be throttled on second request");
  });

  await t.test("3. Memory Hygiene: Rate limiter handles key cleanup smoothly", async () => {
    const limiter = createRateLimiter({
      windowMs: 50, // very short window
      max: 1,
      keyGenerator: () => "expiring-client",
    });

    const mockRes: any = {
      setHeader: () => {},
      status: () => mockRes,
      json: () => mockRes,
    };

    let allowed = false;
    limiter({ headers: {}, socket: {} } as any, mockRes, () => { allowed = true; });
    assert.equal(allowed, true);

    // Wait for window expiration
    await new Promise((r) => setTimeout(r, 70));

    // Request after window expiry should pass again
    allowed = false;
    limiter({ headers: {}, socket: {} } as any, mockRes, () => { allowed = true; });
    assert.equal(allowed, true, "Request after window expiration must succeed");
  });
});
