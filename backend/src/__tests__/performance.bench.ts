import test from "node:test";
import assert from "node:assert/strict";
import { encryptionService } from "../services/encryption.service.js";
import { evaluatePrivacyInMemory } from "../utils/privacy.engine.js";

test("DOLSYX Measurable Performance Benchmark Suite", async (t) => {

  await t.test("1. Encryption Service: Correctness & Ciphertext Verification", () => {
    const rawSecret = "Hello world! This is a secret message with colons: 10:30:45 and URLs https://dolsyx.com";
    const encrypted = encryptionService.encrypt(rawSecret);
    assert.notEqual(encrypted, rawSecret);
    const decrypted = encryptionService.decrypt(encrypted);
    assert.equal(decrypted, rawSecret, "Encrypted message must decrypt cleanly");

    // Test non-encrypted strings (pass-through)
    assert.equal(encryptionService.decrypt("Plain message"), "Plain message");
    assert.equal(encryptionService.decrypt("https://res.cloudinary.com/test.png"), "https://res.cloudinary.com/test.png");
    assert.equal(encryptionService.decrypt('{"type":1,"ciphertext":"dGVzdA=="}'), '{"type":1,"ciphertext":"dGVzdA=="}');
  });

  await t.test("2. Encryption Service: Benchmark colons / non-encrypted pass-through performance", () => {
    const testStrings = [
      '{"type":1,"ciphertext":"dGVzdA=="}',
      "Meeting time: 10:30 today",
      "https://res.cloudinary.com/test.png",
      "Regular text message without colons",
      "Three:colons:here:check",
    ];

    const iterations = 5000;
    const start = performance.now();
    for (let i = 0; i < iterations; i++) {
      for (const s of testStrings) {
        encryptionService.decrypt(s);
      }
    }
    const elapsedMs = performance.now() - start;
    const opsPerSec = Math.round((iterations * testStrings.length) / (elapsedMs / 1000));
    console.log(`[BENCHMARK] Decrypt non-encrypted strings: ${elapsedMs.toFixed(2)}ms for ${iterations * testStrings.length} calls (~${opsPerSec.toLocaleString()} ops/sec)`);
    assert.ok(elapsedMs >= 0);
  });

  await t.test("3. Privacy Engine: Correctness & Fast-Path Evaluation", () => {
    const targetUser = {
      id: "target-user-1",
      avatarPrivacy: "EVERYONE",
      avatarPrivacyExceptList: "[]",
      lastSeenPrivacy: "MY_CONTACTS",
      lastSeenPrivacyExceptList: "[]",
      onlinePrivacy: "SAME_AS_LAST_SEEN",
      aboutPrivacy: "EVERYONE",
      aboutPrivacyExceptList: "[]",
    };

    const res1 = evaluatePrivacyInMemory("requester-1", targetUser, false, true);
    assert.equal(res1.canPhoto, true);
    assert.equal(res1.canLastSeen, true);
    assert.equal(res1.canOnlineStatus, true);
    assert.equal(res1.canAbout, true);

    const res2 = evaluatePrivacyInMemory("requester-1", targetUser, false, false);
    assert.equal(res2.canPhoto, true);
    assert.equal(res2.canLastSeen, false, "Non-contact should not see lastSeen under MY_CONTACTS");
    assert.equal(res2.canOnlineStatus, false);

    const resBlocked = evaluatePrivacyInMemory("requester-1", targetUser, true, true);
    assert.equal(resBlocked.canPhoto, false);
    assert.equal(resBlocked.canLastSeen, false);
    assert.equal(resBlocked.canOnlineStatus, false);

    // Test EXCEPT list with user in list
    const userWithExcept = {
      id: "target-user-2",
      avatarPrivacy: "EXCEPT",
      avatarPrivacyExceptList: JSON.stringify(["requester-blocked-user", "other-id"]),
      lastSeenPrivacy: "EXCEPT",
      lastSeenPrivacyExceptList: JSON.stringify(["other-user-only"]),
      onlinePrivacy: "EVERYONE",
      aboutPrivacy: "EVERYONE",
    };
    const resExcept1 = evaluatePrivacyInMemory("requester-blocked-user", userWithExcept, false, true);
    assert.equal(resExcept1.canPhoto, false, "User in avatar EXCEPT list should be blocked");
    assert.equal(resExcept1.canLastSeen, true, "User NOT in lastSeen EXCEPT list should see lastSeen");
  });

  await t.test("4. Privacy Engine: Benchmark in-memory privacy checks", () => {
    const targetUsers = [
      { id: "u1", avatarPrivacy: "EVERYONE", avatarPrivacyExceptList: "[]", lastSeenPrivacy: "MY_CONTACTS", lastSeenPrivacyExceptList: "[]", onlinePrivacy: "SAME_AS_LAST_SEEN", aboutPrivacy: "EVERYONE", aboutPrivacyExceptList: "[]" },
      { id: "u2", avatarPrivacy: "MY_CONTACTS", avatarPrivacyExceptList: "[]", lastSeenPrivacy: "NOBODY", lastSeenPrivacyExceptList: "[]", onlinePrivacy: "NOBODY", aboutPrivacy: "MY_CONTACTS", aboutPrivacyExceptList: "[]" },
      { id: "u3", avatarPrivacy: "NOBODY", avatarPrivacyExceptList: "[]", lastSeenPrivacy: "EVERYONE", lastSeenPrivacyExceptList: "[]", onlinePrivacy: "EVERYONE", aboutPrivacy: "NOBODY", aboutPrivacyExceptList: "[]" },
      { id: "u4", avatarPrivacy: "EXCEPT", avatarPrivacyExceptList: JSON.stringify(["excluded-1", "excluded-2"]), lastSeenPrivacy: "EXCEPT", lastSeenPrivacyExceptList: "[]", onlinePrivacy: "EXCEPT", aboutPrivacy: "EVERYONE" },
    ];

    const iterations = 10000;
    const start = performance.now();
    for (let i = 0; i < iterations; i++) {
      for (const u of targetUsers) {
        evaluatePrivacyInMemory("req-user", u, false, true);
      }
    }
    const elapsedMs = performance.now() - start;
    const opsPerSec = Math.round((iterations * targetUsers.length) / (elapsedMs / 1000));
    console.log(`[BENCHMARK] Privacy evaluations: ${elapsedMs.toFixed(2)}ms for ${iterations * targetUsers.length} calls (~${opsPerSec.toLocaleString()} ops/sec)`);
    assert.ok(elapsedMs >= 0);
  });
});
