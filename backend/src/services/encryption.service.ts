import crypto from "crypto";

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12;
const KEY_LENGTH = 32;
const ITERATIONS = 10000;

class EncryptionService {
  private keys: Buffer[] = [];

  constructor() {
    const secrets = [
      process.env.JWT_SECRET,
      "dolsyx_super_secret_key_123456",
      "dolsyx_secret_key_2024"
    ].filter((s): s is string => Boolean(s && s.trim().length > 0));

    // Deduplicate secrets
    const uniqueSecrets = Array.from(new Set(secrets));
    this.keys = uniqueSecrets.map((secret) =>
      crypto.pbkdf2Sync(secret, "dolsyx_salt_123456", ITERATIONS, KEY_LENGTH, "sha256")
    );
  }

  public encrypt(text: string): string {
    if (!text) return "";
    try {
      const primaryKey = this.keys[0];
      if (!primaryKey) return text;

      const iv = crypto.randomBytes(IV_LENGTH);
      const cipher = crypto.createCipheriv(ALGORITHM, primaryKey, iv);
      let encrypted = cipher.update(text, "utf8", "hex");
      encrypted += cipher.final("hex");
      const authTag = cipher.getAuthTag().toString("hex");
      
      // Return: iv:authTag:encrypted
      return `${iv.toString("hex")}:${authTag}:${encrypted}`;
    } catch (err) {
      console.error("[EncryptionService] Encryption failed:", err);
      return text;
    }
  }

  public decrypt(cipherText: string): string {
    if (!cipherText || typeof cipherText !== "string") return "";
    const parts = cipherText.split(":");
    if (parts.length !== 3) {
      // Not encrypted (plain text or client E2EE JSON)
      return cipherText;
    }

    const ivStr = parts[0];
    const authTagStr = parts[1];
    const encrypted = parts[2];

    if (!ivStr || !authTagStr || !encrypted) {
      return cipherText;
    }

    // IV is 12 bytes = 24 hex chars; AuthTag is 16 bytes = 32 hex chars.
    // If lengths differ or non-hex, it is plain text / JSON with colons. Skip crypto failure overhead.
    if (ivStr.length !== 24 || authTagStr.length !== 32) {
      return cipherText;
    }

    // Attempt decryption with each candidate key until one succeeds
    for (const key of this.keys) {
      try {
        const iv = Buffer.from(ivStr, "hex");
        const authTag = Buffer.from(authTagStr, "hex");

        const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
        decipher.setAuthTag(authTag);

        let decrypted = decipher.update(encrypted, "hex", "utf8");
        decrypted += decipher.final("utf8");
        return decrypted;
      } catch (_) {
        // Try next key
      }
    }

    // If all fail, return raw cipherText
    return cipherText;
  }
}

export const encryptionService = new EncryptionService();
