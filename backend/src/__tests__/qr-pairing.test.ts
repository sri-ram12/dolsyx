import test from "node:test";
import assert from "node:assert/strict";
import crypto from "crypto";
import { PairingService } from "../services/pairing.service.js";

test("DOLSYX Secure Linked Device QR Login - Comprehensive Test Suite", async (t) => {

  await t.test("1. Pairing Creation: Generates high-entropy pairingId, challenge, and valid expiry", () => {
    PairingService.clearAll();
    const session = PairingService.createSession({
      userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      ip: "192.168.1.100",
    }, 90);

    assert.ok(session.pairingId.startsWith("dolsyx_pair_"), "pairingId must start with dolsyx_pair_");
    assert.equal(session.challenge.length, 64, "challenge must be 32 bytes (64 hex characters)");
    assert.ok(session.expiresAt > Date.now(), "expiresAt must be in the future");

    const retrieved = PairingService.getSession(session.pairingId);
    assert.ok(retrieved, "Session must exist in store");
    assert.equal(retrieved.status, "PENDING", "Initial status must be PENDING");
    assert.equal(retrieved.requestingDeviceMetadata.browser, "Google Chrome");
    assert.equal(retrieved.requestingDeviceMetadata.os, "Windows");
    assert.equal(retrieved.requestingDeviceMetadata.platform, "Windows PC");
  });

  await t.test("2. Expiration Rejection: Expired QR pairing cannot be scanned", async () => {
    PairingService.clearAll();
    // Create with 0.1s TTL
    const session = PairingService.createSession({ userAgent: "Chrome" }, 0.1);
    
    // Wait 150ms to exceed TTL
    await new Promise((r) => setTimeout(r, 150));

    const scanResult = PairingService.scanSession(session.pairingId, session.challenge, "user_mobile_123");
    assert.equal(scanResult.success, false, "Scanning expired pairing must fail");
    assert.match(scanResult.error || "", /expired/i, "Error must indicate expiration");
  });

  await t.test("3. Challenge Validation: Invalid challenge fails scan and approve", () => {
    PairingService.clearAll();
    const session = PairingService.createSession({ userAgent: "Chrome" }, 90);
    const fakeChallenge = crypto.randomBytes(32).toString("hex");

    const scanResult = PairingService.scanSession(session.pairingId, fakeChallenge, "user_mobile_123");
    assert.equal(scanResult.success, false, "Scan with incorrect challenge must fail");
    assert.match(scanResult.error || "", /challenge/i);
  });

  await t.test("4. Replay Protection: Cannot scan same QR twice", () => {
    PairingService.clearAll();
    const session = PairingService.createSession({ userAgent: "Chrome" }, 90);

    // First scan succeeds
    const firstScan = PairingService.scanSession(session.pairingId, session.challenge, "user_mobile_123");
    assert.equal(firstScan.success, true);
    assert.equal(firstScan.session?.status, "SCANNED");

    // Replay / second scan attempt must fail
    const secondScan = PairingService.scanSession(session.pairingId, session.challenge, "user_mobile_123");
    assert.equal(secondScan.success, false, "Re-scanning must be rejected");
    assert.match(secondScan.error || "", /invalid pairing state/i);
  });

  await t.test("5. Authorization Protection: Only the user who scanned can approve", () => {
    PairingService.clearAll();
    const session = PairingService.createSession({ userAgent: "Chrome" }, 90);

    // User A scans
    PairingService.scanSession(session.pairingId, session.challenge, "user_A");

    // Attacker User B tries to approve User A's pairing
    const maliciousApproval = PairingService.approveSession(session.pairingId, session.challenge, "user_B_attacker");
    assert.equal(maliciousApproval.success, false, "Unauthorized user cannot approve pairing");
    assert.match(maliciousApproval.error || "", /authenticated user/i);

    // Legitimate User A approves
    const legitimateApproval = PairingService.approveSession(session.pairingId, session.challenge, "user_A");
    assert.equal(legitimateApproval.success, true, "Authorized user must be able to approve");
    assert.equal(legitimateApproval.session?.status, "APPROVED");
  });

  await t.test("6. Double Approval Protection: Cannot approve an already approved session", () => {
    PairingService.clearAll();
    const session = PairingService.createSession({ userAgent: "Chrome" }, 90);

    PairingService.scanSession(session.pairingId, session.challenge, "user_A");
    const firstApproval = PairingService.approveSession(session.pairingId, session.challenge, "user_A");
    assert.equal(firstApproval.success, true);

    // Rapid double click / duplicate approval attempt
    const secondApproval = PairingService.approveSession(session.pairingId, session.challenge, "user_A");
    assert.equal(secondApproval.success, false, "Double approval must be rejected");
  });

  await t.test("7. Single-Use Consumption: Pairing can only be consumed once", () => {
    PairingService.clearAll();
    const session = PairingService.createSession({ userAgent: "Chrome" }, 90);

    PairingService.scanSession(session.pairingId, session.challenge, "user_A");
    PairingService.approveSession(session.pairingId, session.challenge, "user_A");

    // First consumption succeeds
    const firstConsume = PairingService.consumeSession(session.pairingId, session.challenge);
    assert.equal(firstConsume.success, true);
    assert.equal(firstConsume.userId, "user_A");

    // Verify status is CONSUMED
    const stored = PairingService.getSession(session.pairingId);
    assert.equal(stored?.status, "CONSUMED");

    // Second consumption attempt must fail
    const secondConsume = PairingService.consumeSession(session.pairingId, session.challenge);
    assert.equal(secondConsume.success, false, "Double consumption must be rejected");
    assert.match(secondConsume.error || "", /already been consumed/i);
  });

  await t.test("8. State Machine Protection: Cannot consume an unapproved pairing", () => {
    PairingService.clearAll();
    const session = PairingService.createSession({ userAgent: "Chrome" }, 90);

    // Attempting to consume while PENDING must fail
    const prematureConsume = PairingService.consumeSession(session.pairingId, session.challenge);
    assert.equal(prematureConsume.success, false);
    assert.match(prematureConsume.error || "", /not approved/i);
  });

  await t.test("9. Rejection Handling: Rejecting transitions to REJECTED and blocks consumption", () => {
    PairingService.clearAll();
    const session = PairingService.createSession({ userAgent: "Chrome" }, 90);

    PairingService.scanSession(session.pairingId, session.challenge, "user_A");
    const rejectResult = PairingService.rejectSession(session.pairingId, "user_A");
    assert.equal(rejectResult.success, true);

    const stored = PairingService.getSession(session.pairingId);
    assert.equal(stored?.status, "REJECTED");

    const consumeAttempt = PairingService.consumeSession(session.pairingId, session.challenge);
    assert.equal(consumeAttempt.success, false);
  });

  await t.test("10. Multiple Devices: Each pairing maintains independent state and tokens", () => {
    PairingService.clearAll();

    // Device 1: Laptop Chrome
    const session1 = PairingService.createSession({ userAgent: "Chrome on Windows NT 10.0" }, 90);
    // Device 2: MacBook Safari
    const session2 = PairingService.createSession({ userAgent: "Safari on Mac OS X" }, 90);

    assert.notEqual(session1.pairingId, session2.pairingId);
    assert.notEqual(session1.challenge, session2.challenge);

    // User approves Device 1
    PairingService.scanSession(session1.pairingId, session1.challenge, "user_multi");
    PairingService.approveSession(session1.pairingId, session1.challenge, "user_multi");
    const consume1 = PairingService.consumeSession(session1.pairingId, session1.challenge);

    assert.equal(consume1.success, true);
    assert.equal(consume1.deviceMetadata?.browser, "Google Chrome");
    assert.equal(consume1.deviceMetadata?.os, "Windows");

    // Device 2 remains unaffected in PENDING state
    const dev2Session = PairingService.getSession(session2.pairingId);
    assert.equal(dev2Session?.status, "PENDING");
    assert.equal(dev2Session?.requestingDeviceMetadata.browser, "Apple Safari");
    assert.equal(dev2Session?.requestingDeviceMetadata.os, "macOS");
  });
});
