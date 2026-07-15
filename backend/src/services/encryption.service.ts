import crypto from "crypto";

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12;
const KEY_LENGTH = 32;
const ITERATIONS = 10000;

class EncryptionService {
  private key: Buffer;

  constructor() {
    const secret = process.env.JWT_SECRET || "dolsyx_super_secret_key_123456";
    // Generate a secure key deterministically using PBKDF2
    this.key = crypto.pbkdf2Sync(secret, "dolsyx_salt_123456", ITERATIONS, KEY_LENGTH, "sha256");
  }

  public encrypt(text: string): string {
    if (!text) return "";
    try {
      const iv = crypto.randomBytes(IV_LENGTH);
      const cipher = crypto.createCipheriv(ALGORITHM, this.key, iv);
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
    if (!cipherText) return "";
    try {
      const parts = cipherText.split(":");
      if (parts.length !== 3) {
        // Not encrypted (or old plain text messages)
        return cipherText;
      }
      
      const ivStr = parts[0];
      const authTagStr = parts[1];
      const encrypted = parts[2];
      
      if (!ivStr || !authTagStr || !encrypted) {
        return cipherText;
      }
      
      const iv = Buffer.from(ivStr, "hex");
      const authTag = Buffer.from(authTagStr, "hex");
      
      const decipher = crypto.createDecipheriv(ALGORITHM, this.key, iv);
      decipher.setAuthTag(authTag);
      
      let decrypted = decipher.update(encrypted, "hex", "utf8");
      decrypted += decipher.final("utf8");
      return decrypted;
    } catch (err) {
      // If decryption fails, it could be that it wasn't encrypted
      return cipherText;
    }
  }
}

export const encryptionService = new EncryptionService();
