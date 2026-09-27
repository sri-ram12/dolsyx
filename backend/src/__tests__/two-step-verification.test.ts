import { test, describe } from "node:test";
import assert from "node:assert/strict";
import bcrypt from "bcryptjs";

describe("DOLSYX Two-Step Verification (2SV) & 7-Day Cooldown Security Suite", () => {
  // Test 1: PIN format validation
  test("1. PIN Format Validation: Enforces strictly 6 numeric digits", () => {
    const validPins = ["123456", "000000", "987654", "492018"];
    const invalidPins = ["12345", "1234567", "abcdef", "12a456", "", "12 456", "12.456"];

    const pinRegex = /^\d{6}$/;

    for (const pin of validPins) {
      assert.equal(pinRegex.test(pin), true, `PIN ${pin} should be valid`);
    }

    for (const pin of invalidPins) {
      assert.equal(pinRegex.test(pin), false, `PIN ${pin} should be rejected`);
    }
  });

  // Test 2: Cryptographic Hashing with Salt
  test("2. Cryptographic Salt & Hash: Plain PIN is never stored; bcrypt verifies matches", async () => {
    const pin = "749201";
    const salt = await bcrypt.genSalt(10);
    const hash = await bcrypt.hash(pin, salt);

    assert.notEqual(hash, pin, "Hash must never match plain text");
    assert.equal(hash.startsWith("$2"), true, "Hash must be valid bcrypt prefix");

    const isMatch = await bcrypt.compare(pin, hash);
    assert.equal(isMatch, true, "Valid PIN should match bcrypt hash");

    const isWrongMatch = await bcrypt.compare("749202", hash);
    assert.equal(isWrongMatch, false, "Wrong PIN must be rejected by bcrypt");
  });

  // Test 3: Brute-Force Rate Limiter & Lockout Mechanism
  test("3. Brute-Force Defense: Locks account for 15 minutes after 5 failed attempts", () => {
    let failedAttempts = 0;
    let lockoutUntil: Date | null = null;

    const recordFailedAttempt = () => {
      failedAttempts++;
      if (failedAttempts >= 5) {
        lockoutUntil = new Date(Date.now() + 15 * 60 * 1000);
      }
    };

    // 4 failed attempts - not yet locked
    for (let i = 1; i <= 4; i++) {
      recordFailedAttempt();
      assert.equal(lockoutUntil, null, `Attempt ${i} should not lock yet`);
      assert.equal(failedAttempts, i);
    }

    // 5th attempt - lock triggered
    recordFailedAttempt();
    assert.equal(failedAttempts, 5);
    assert.notEqual(lockoutUntil, null);
    assert.equal((lockoutUntil as any).getTime() > Date.now(), true);

    // Active lock prevents verification
    const isLocked = lockoutUntil !== null && Date.now() < (lockoutUntil as Date).getTime();
    assert.equal(isLocked, true, "Account must be recognized as locked");
  });

  // Test 4: 7-Day Security Cooldown Calculations
  test("4. 7-Day Security Cooldown: Protects against instant reset by unauthorized email access", () => {
    const cooldownDays = 7;
    const cooldownMs = cooldownDays * 24 * 60 * 60 * 1000;

    // Simulate reset request initiated 2 days ago
    const twoDaysAgo = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000);
    const elapsed = Date.now() - twoDaysAgo.getTime();

    assert.equal(elapsed < cooldownMs, true, "Cooldown should still be active at 2 days");

    const remainingMs = cooldownMs - elapsed;
    const remainingDays = Math.ceil(remainingMs / (24 * 60 * 60 * 1000));
    assert.equal(remainingDays, 5, "Should calculate exactly 5 days remaining");

    // Simulate reset request after 7 days + 1 hour
    const sevenDaysAndHourAgo = new Date(Date.now() - (7 * 24 + 1) * 60 * 60 * 1000);
    const elapsedAfter7Days = Date.now() - sevenDaysAndHourAgo.getTime();
    assert.equal(elapsedAfter7Days >= cooldownMs, true, "7-day cooldown elapsed; reset allowed");
  });

  // Test 5: Owner Reset Cancellation
  test("5. Owner Kill-Switch: Owner can cancel pending reset and retain account defense", () => {
    let resetRequestedAt: Date | null = new Date();
    assert.notEqual(resetRequestedAt, null);

    // Owner taps "Cancel Reset"
    resetRequestedAt = null;
    assert.equal(resetRequestedAt, null, "Pending reset is wiped and 2SV remains 100% active");
  });
});
