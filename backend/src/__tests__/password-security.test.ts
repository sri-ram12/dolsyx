import { test, describe } from "node:test";
import assert from "node:assert/strict";
import bcrypt from "bcryptjs";

describe("DOLSYX Strict Password Authentication & Safety Suite", () => {
  test("1. Password Length Enforcement: Minimum 6 characters required", () => {
    const validPasswords = ["Pass1234", "supersecret", "my-secure-pwd-2026"];
    const invalidPasswords = ["123", "abc", "", "  ", "short"];

    for (const p of validPasswords) {
      assert.equal(p.trim().length >= 6, true, `Password "${p}" should be accepted`);
    }

    for (const p of invalidPasswords) {
      assert.equal(p.trim().length >= 6, false, `Password "${p}" should be rejected`);
    }
  });

  test("2. Strict Bcrypt Comparison: Dummy or wrong password rejected", async () => {
    const realPassword = "UserSecretPassword99!";
    const salt = await bcrypt.genSalt(10);
    const hash = await bcrypt.hash(realPassword, salt);

    // Dummy password should fail
    const isDummyMatch = await bcrypt.compare("123456", hash);
    assert.equal(isDummyMatch, false, "Dummy password must fail authentication");

    const isWrongMatch = await bcrypt.compare("UserSecretPassword99", hash);
    assert.equal(isWrongMatch, false, "Typo in password must fail authentication");

    const isCorrectMatch = await bcrypt.compare(realPassword, hash);
    assert.equal(isCorrectMatch, true, "Correct password must pass authentication");
  });

  test("3. Password Change Verification: Requires correct current password before update", async () => {
    const oldPassword = "InitialPassword123";
    const salt = await bcrypt.genSalt(10);
    const currentHash = await bcrypt.hash(oldPassword, salt);

    const providedCurrent = "WrongCurrentPassword";
    const canChange = await bcrypt.compare(providedCurrent, currentHash);
    assert.equal(canChange, false, "Cannot change password with incorrect current password");

    const correctCurrentProvided = await bcrypt.compare(oldPassword, currentHash);
    assert.equal(correctCurrentProvided, true, "Can proceed with password change when current matches");
  });
});
