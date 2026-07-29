import * as crypto from 'crypto';

export class AesGcm {
  private static readonly ALGORITHM = 'aes-256-gcm';
  private static readonly NONCE_LENGTH = 12; // 96 bits for GCM
  private static readonly TAG_LENGTH = 16;   // 128 bits for GCM auth tag

  /**
   * Encrypts plaintext using AES-256-GCM.
   * 
   * @param plaintext The data to encrypt
   * @param key The 32-byte (256-bit) encryption key
   * @returns An object containing the ciphertext, nonce (iv), and authentication tag.
   */
  static encrypt(plaintext: Buffer | string, key: Buffer): { ciphertext: Buffer, nonce: Buffer, tag: Buffer } {
    if (key.length !== 32) {
      throw new Error('Key must be exactly 32 bytes (256 bits) for AES-256-GCM');
    }

    const nonce = crypto.randomBytes(this.NONCE_LENGTH);
    const cipher = crypto.createCipheriv(this.ALGORITHM, key, nonce);
    
    const buf = Buffer.isBuffer(plaintext) ? plaintext : Buffer.from(plaintext, 'utf8');
    
    let ciphertext = cipher.update(buf);
    ciphertext = Buffer.concat([ciphertext, cipher.final()]);
    
    const tag = cipher.getAuthTag();

    return { ciphertext, nonce, tag };
  }

  /**
   * Decrypts ciphertext using AES-256-GCM.
   * 
   * @param ciphertext The encrypted data
   * @param key The 32-byte encryption key
   * @param nonce The 12-byte initialization vector (iv) used during encryption
   * @param tag The 16-byte authentication tag produced during encryption
   * @returns The decrypted plaintext Buffer
   */
  static decrypt(ciphertext: Buffer, key: Buffer, nonce: Buffer, tag: Buffer): Buffer {
    if (key.length !== 32) {
      throw new Error('Key must be exactly 32 bytes (256 bits) for AES-256-GCM');
    }
    if (nonce.length !== this.NONCE_LENGTH) {
      throw new Error(`Nonce must be exactly ${this.NONCE_LENGTH} bytes`);
    }
    if (tag.length !== this.TAG_LENGTH) {
      throw new Error(`Authentication tag must be exactly ${this.TAG_LENGTH} bytes`);
    }

    const decipher = crypto.createDecipheriv(this.ALGORITHM, key, nonce);
    decipher.setAuthTag(tag);

    let plaintext = decipher.update(ciphertext);
    plaintext = Buffer.concat([plaintext, decipher.final()]);

    return plaintext;
  }
}
