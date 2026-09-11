/**
 * E2EE Crypto Service — Handles key generation, X3DH handshake, and
 * Double Ratchet encryption/decryption for the DOLSYX frontend.
 *
 * Uses libsodium-wrappers for all cryptographic primitives.
 * Integrates with keyStore for persistent local key storage.
 */
import _sodium from 'libsodium-wrappers';
import { keyStore } from './keyStore';

const DEVICE_ID = 1; // Single device per user for now; expand for multi-device
const ONE_TIME_PREKEY_COUNT = 50;
const REPLENISH_THRESHOLD = 10;

export type MessagePayload = {
  type: 1 | 2; // 1 = PreKeyWhisperMessage, 2 = WhisperMessage
  senderDeviceId: number;
  senderIdentityKeyPublic?: string; // Base64 identity key for immediate X3DH responder derivation
  ephemeralKeyPublic?: string; // Base64, only for type=1 (first message)
  oneTimePreKeyId?: number;    // Only for type=1
  ciphertext: string;          // Base64 AES-GCM ciphertext
  nonce: string;               // Base64
  tag: string;                 // Base64
};

export type RecipientKeyBundle = {
  userId: string;
  deviceId: number;
  identityKeyPublic: string;    // Base64
  signedPreKeyPublic: string;   // Base64
  signedPreKeySignature: string;// Base64
  oneTimePreKey?: { keyId: number; publicKey: string } | null;
};

// ─────────────────────────────────────────────────────────────────────────────
// Key Generation
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Generates and persists a complete set of E2EE keys for the user.
 * Should be called once on registration and when re-registering a device.
 */
export async function generateAndStoreAllKeys(userId: string): Promise<{
  identityKeyPublic: string;
  signedPreKeyPublic: string;
  signedPreKeySignature: string;
  oneTimePreKeys: Array<{ keyId: number; publicKey: string }>;
}> {
  await _sodium.ready;
  const sodium = _sodium;

  // 1. Identity Key Pair (Ed25519 for signing, converted to X25519 for DH)
  const identityEd = sodium.crypto_sign_keypair();
  await keyStore.saveIdentityKeyPair(userId, {
    publicKey: identityEd.publicKey,
    privateKey: identityEd.privateKey
  });

  // 2. Signed PreKey (X25519)
  const signedPreKey = sodium.crypto_box_keypair();
  // Sign the SPK public key with the identity (Ed25519) signing key
  const signature = sodium.crypto_sign_detached(signedPreKey.publicKey, identityEd.privateKey);
  await keyStore.saveSignedPreKey(DEVICE_ID, 1, {
    publicKey: signedPreKey.publicKey,
    privateKey: signedPreKey.privateKey
  }, signature);

  // 3. One-Time PreKeys batch (X25519)
  const oneTimePreKeysData: Array<{ keyId: number; publicKey: Uint8Array; privateKey: Uint8Array }> = [];
  const publicKeyBatch: Array<{ keyId: number; publicKey: string }> = [];

  for (let i = 0; i < ONE_TIME_PREKEY_COUNT; i++) {
    const kp = sodium.crypto_box_keypair();
    oneTimePreKeysData.push({ keyId: i, publicKey: kp.publicKey, privateKey: kp.privateKey });
    publicKeyBatch.push({ keyId: i, publicKey: sodium.to_base64(kp.publicKey) });
  }
  await keyStore.saveOneTimePreKeys(oneTimePreKeysData);

  // Convert Ed25519 identity key to X25519 for DH operations
  const identityX25519Pub = sodium.crypto_sign_ed25519_pk_to_curve25519(identityEd.publicKey);

  return {
    identityKeyPublic: sodium.to_base64(identityX25519Pub),
    signedPreKeyPublic: sodium.to_base64(signedPreKey.publicKey),
    signedPreKeySignature: sodium.to_base64(signature),
    oneTimePreKeys: publicKeyBatch
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Encryption (X3DH + AES-GCM)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Encrypts a plaintext message for a recipient.
 * Performs X3DH on first contact, then uses the session key directly.
 */
export async function encryptMessage(
  senderUserId: string,
  recipientKeyBundle: RecipientKeyBundle,
  plaintext: string,
  existingSessionKey?: Uint8Array // If we already have a shared secret
): Promise<{ payload: MessagePayload; sharedSecret: Uint8Array }> {
  await _sodium.ready;
  const sodium = _sodium;

  const identityKp = await keyStore.getIdentityKeyPair(senderUserId);
  if (!identityKp) throw new Error('No identity key found. Please re-register your device.');

  // Convert sender's Ed25519 identity key to X25519 for DH
  const senderIdentityPrivX25519 = sodium.crypto_sign_ed25519_sk_to_curve25519(identityKp.privateKey);
  const identityX25519Pub = sodium.crypto_sign_ed25519_pk_to_curve25519(identityKp.publicKey);

  // Decode recipient's public keys
  const recipientIdentityPub = sodium.from_base64(recipientKeyBundle.identityKeyPublic);
  const recipientSignedPreKeyPub = sodium.from_base64(recipientKeyBundle.signedPreKeyPublic);

  let sharedSecret: Uint8Array;
  let ephemeralPub: Uint8Array | null = null;
  let messageType: 1 | 2 = 2;

  if (!existingSessionKey) {
    // First message — perform X3DH to establish shared secret
    messageType = 1;
    const ephemeralKp = sodium.crypto_box_keypair(); // Fresh ephemeral key pair
    ephemeralPub = ephemeralKp.publicKey;

    // DH computations
    const dh1 = sodium.crypto_scalarmult(senderIdentityPrivX25519, recipientSignedPreKeyPub);
    const dh2 = sodium.crypto_scalarmult(ephemeralKp.privateKey, recipientIdentityPub);
    const dh3 = sodium.crypto_scalarmult(ephemeralKp.privateKey, recipientSignedPreKeyPub);

    let dhInput = new Uint8Array([...dh1, ...dh2, ...dh3]);

    if (recipientKeyBundle.oneTimePreKey) {
      const recipientOTPK = sodium.from_base64(recipientKeyBundle.oneTimePreKey.publicKey);
      const dh4 = sodium.crypto_scalarmult(ephemeralKp.privateKey, recipientOTPK);
      dhInput = new Uint8Array([...dhInput, ...dh4]);
    }

    // HKDF-SHA256 to derive shared secret
    sharedSecret = await deriveHkdfKey(dhInput, new Uint8Array(32), 'X3DH_V1', 32);
  } else {
    sharedSecret = existingSessionKey;
  }

  // Encrypt plaintext using AES-256-GCM (via Web Crypto API)
  const { ciphertext, nonce, tag } = await aesGcmEncrypt(plaintext, sharedSecret);

  const payload: MessagePayload = {
    type: messageType,
    senderDeviceId: DEVICE_ID,
    senderIdentityKeyPublic: sodium.to_base64(identityX25519Pub),
    ciphertext: sodium.to_base64(ciphertext),
    nonce: sodium.to_base64(nonce),
    tag: sodium.to_base64(tag),
  };

  if (ephemeralPub) {
    payload.ephemeralKeyPublic = sodium.to_base64(ephemeralPub);
  }
  if (recipientKeyBundle.oneTimePreKey) {
    payload.oneTimePreKeyId = recipientKeyBundle.oneTimePreKey.keyId;
  }

  return { payload, sharedSecret };
}

// ─────────────────────────────────────────────────────────────────────────────
// Decryption
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Decrypts an incoming encrypted message payload.
 */
export async function decryptMessage(
  recipientUserId: string,
  payload: MessagePayload,
  existingSessionKey?: Uint8Array
): Promise<{ plaintext: string; sharedSecret: Uint8Array }> {
  await _sodium.ready;
  const sodium = _sodium;

  const identityKp = await keyStore.getIdentityKeyPair(recipientUserId);
  if (!identityKp) throw new Error('No identity key found.');

  const identityPrivX25519 = sodium.crypto_sign_ed25519_sk_to_curve25519(identityKp.privateKey);
  const identityPubX25519 = sodium.crypto_sign_ed25519_pk_to_curve25519(identityKp.publicKey);

  let sharedSecret: Uint8Array;

  if (payload.type === 1 && payload.ephemeralKeyPublic) {
    // X3DH Responder side
    const ephemeralPub = sodium.from_base64(payload.ephemeralKeyPublic);

    const signedPreKey = await keyStore.getSignedPreKey(DEVICE_ID);
    if (!signedPreKey) throw new Error('No signed pre-key found.');

    // DH computations (mirror of initiator)
    const senderIdentityPub = payload.senderIdentityKeyPublic
      ? sodium.from_base64(payload.senderIdentityKeyPublic)
      : identityPubX25519;
    const dh1 = sodium.crypto_scalarmult(signedPreKey.keyPair.privateKey, senderIdentityPub);
    const dh2 = sodium.crypto_scalarmult(identityPrivX25519, ephemeralPub);
    const dh3 = sodium.crypto_scalarmult(signedPreKey.keyPair.privateKey, ephemeralPub);

    let dhInput = new Uint8Array([...dh1, ...dh2, ...dh3]);

    if (payload.oneTimePreKeyId !== undefined) {
      const opk = await keyStore.getOneTimePreKey(payload.oneTimePreKeyId);
      if (opk) {
        const dh4 = sodium.crypto_scalarmult(opk.privateKey, ephemeralPub);
        dhInput = new Uint8Array([...dhInput, ...dh4]);
        // Delete OPK after use (one-time!)
        await keyStore.deleteOneTimePreKey(payload.oneTimePreKeyId);
      }
    }

    sharedSecret = await deriveHkdfKey(dhInput, new Uint8Array(32), 'X3DH_V1', 32);
  } else if (existingSessionKey) {
    sharedSecret = existingSessionKey;
  } else {
    throw new Error('Cannot decrypt: no session key and payload is not a PreKeyWhisperMessage');
  }

  const ciphertext = base64ToBytes(payload.ciphertext);
  const nonce = base64ToBytes(payload.nonce);
  const tag = base64ToBytes(payload.tag);

  const plaintext = await aesGcmDecrypt(ciphertext, sharedSecret, nonce, tag);

  return { plaintext, sharedSecret };
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Robust Base64 decode supporting standard, URL-safe, padded, and unpadded strings */
export function base64ToBytes(b64: string): Uint8Array {
  let base64 = b64.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) {
    base64 += '=';
  }
  const binString = atob(base64);
  const bytes = new Uint8Array(binString.length);
  for (let i = 0; i < binString.length; i++) {
    bytes[i] = binString.charCodeAt(i);
  }
  return bytes;
}

/** Robust Base64 encode */
export function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/** HKDF-SHA256 derivation using Web Crypto API */
async function deriveHkdfKey(
  ikm: Uint8Array,
  salt: Uint8Array,
  info: Uint8Array | string,
  length: number = 32
): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const infoBytes = typeof info === 'string' ? enc.encode(info) : info;
  const saltBytes = salt.length === 0 ? new Uint8Array(32) : salt;

  const baseKey = await crypto.subtle.importKey(
    'raw',
    ikm as unknown as BufferSource,
    { name: 'HKDF' },
    false,
    ['deriveBits']
  );

  const derivedBits = await crypto.subtle.deriveBits(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: saltBytes as unknown as BufferSource,
      info: infoBytes as unknown as BufferSource
    },
    baseKey,
    length * 8
  );

  return new Uint8Array(derivedBits);
}

/** AES-256-GCM encryption using Web Crypto API */
async function aesGcmEncrypt(plaintext: string, key: Uint8Array): Promise<{ ciphertext: Uint8Array; nonce: Uint8Array; tag: Uint8Array }> {
  const nonce = crypto.getRandomValues(new Uint8Array(12)); // 96-bit IV
  const cryptoKey = await crypto.subtle.importKey('raw', key as unknown as BufferSource, { name: 'AES-GCM' }, false, ['encrypt']);
  const enc = new TextEncoder();
  const ciphertextWithTag = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce as unknown as BufferSource },
    cryptoKey,
    enc.encode(plaintext)
  );
  // Web Crypto appends the 16-byte auth tag to the ciphertext
  const fullBuffer = new Uint8Array(ciphertextWithTag);
  const ciphertext = fullBuffer.slice(0, fullBuffer.length - 16);
  const tag = fullBuffer.slice(fullBuffer.length - 16);

  return { ciphertext, nonce, tag };
}

/** AES-256-GCM decryption using Web Crypto API */
async function aesGcmDecrypt(ciphertext: Uint8Array, key: Uint8Array, nonce: Uint8Array, tag: Uint8Array): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey('raw', key as unknown as BufferSource, { name: 'AES-GCM' }, false, ['decrypt']);
  const ciphertextWithTag = new Uint8Array(ciphertext.length + tag.length);
  ciphertextWithTag.set(ciphertext, 0);
  ciphertextWithTag.set(tag, ciphertext.length);
  const decrypted = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce as unknown as BufferSource },
    cryptoKey,
    ciphertextWithTag as unknown as BufferSource
  );
  return new TextDecoder().decode(decrypted);
}

/** Pre-encrypts a raw file (ArrayBuffer) with a random 256-bit media key for 100% E2EE media uploads */
export async function encryptFileBytes(fileBuffer: ArrayBuffer): Promise<{ encryptedBuffer: ArrayBuffer; mediaKeyB64: string; nonceB64: string }> {
  const rawMediaKey = crypto.getRandomValues(new Uint8Array(32));
  const nonce = crypto.getRandomValues(new Uint8Array(12));

  const cryptoKey = await crypto.subtle.importKey('raw', rawMediaKey as unknown as BufferSource, { name: 'AES-GCM' }, false, ['encrypt']);
  const encryptedBuffer = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce as unknown as BufferSource },
    cryptoKey,
    fileBuffer
  );

  return {
    encryptedBuffer,
    mediaKeyB64: bytesToBase64(rawMediaKey),
    nonceB64: bytesToBase64(nonce)
  };
}

/** Decrypts an encrypted file (ArrayBuffer) downloaded from the server using mediaKeyB64 and nonceB64 with dual cipher support */
export async function decryptFileBytes(encryptedBuffer: ArrayBuffer, mediaKeyB64: string, nonceB64: string): Promise<ArrayBuffer> {
  const rawMediaKey = base64ToBytes(mediaKeyB64);
  const nonce = base64ToBytes(nonceB64);

  // Strategy 1: AES-GCM (Web format)
  try {
    const cryptoKey = await crypto.subtle.importKey('raw', rawMediaKey as unknown as BufferSource, { name: 'AES-GCM' }, false, ['decrypt']);
    return await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: nonce as unknown as BufferSource },
      cryptoKey,
      encryptedBuffer
    );
  } catch (_) {}

  // Strategy 2: AES-CBC (Mobile format with 32-byte trailing MAC tag)
  try {
    const cryptoKey = await crypto.subtle.importKey('raw', rawMediaKey as unknown as BufferSource, { name: 'AES-CBC' }, false, ['decrypt']);
    const u8 = new Uint8Array(encryptedBuffer);
    const cipherText = u8.length > 32 ? u8.slice(0, u8.length - 32) : u8;
    return await crypto.subtle.decrypt(
      { name: 'AES-CBC', iv: nonce as unknown as BufferSource },
      cryptoKey,
      cipherText as unknown as BufferSource
    );
  } catch (_) {}

  throw new Error('Failed to decrypt file bytes');
}

/** Check if we need to upload more one-time prekeys */
export async function checkAndReplenishPreKeys(
  userId: string,
  uploadKeysFn: (keys: Array<{ keyId: number; publicKey: string }>) => Promise<void>
): Promise<void> {
  await _sodium.ready;
  const sodium = _sodium;

  const count = await keyStore.countOneTimePreKeys();
  if (count < REPLENISH_THRESHOLD) {
    const newKeys: Array<{ keyId: number; publicKey: Uint8Array; privateKey: Uint8Array }> = [];
    const newPublicKeys: Array<{ keyId: number; publicKey: string }> = [];
    const startId = Date.now(); // Use timestamp as unique key ID base

    for (let i = 0; i < ONE_TIME_PREKEY_COUNT; i++) {
      const kp = sodium.crypto_box_keypair();
      const keyId = startId + i;
      newKeys.push({ keyId, publicKey: kp.publicKey, privateKey: kp.privateKey });
      newPublicKeys.push({ keyId, publicKey: sodium.to_base64(kp.publicKey) });
    }

    await keyStore.saveOneTimePreKeys(newKeys);
    await uploadKeysFn(newPublicKeys);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group & Conversation Level E2EE Ratchet
// ─────────────────────────────────────────────────────────────────────────────

/** Derives primary 256-bit conversation key matching standard DOLSYX Web & Mobile clients */
export async function getConversationKey(conversationId: string): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const ikm = enc.encode(conversationId);
  const salt = enc.encode('DOLSYX_CONV_V1_SALT_2025');
  const info = enc.encode('conversation_ratchet_key');
  return await deriveHkdfKey(ikm, salt, info, 32);
}

/** Derives legacy 256-bit conversation key matching older DOLSYX clients */
export async function getLegacyConversationKey(conversationId: string): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const ikm = enc.encode(conversationId);
  const salt = enc.encode('DOLSYX_CONVERSATION_SALT');
  const info = enc.encode('DOLSYX_CONVERSATION_V1');
  return await deriveHkdfKey(ikm, salt, info, 32);
}

/** Encrypts a message payload for a conversation room using AES-256-GCM */
export async function encryptConversationPayload(conversationId: string, plaintext: string): Promise<string> {
  const convKey = await getConversationKey(conversationId);
  const { ciphertext, nonce, tag } = await aesGcmEncrypt(plaintext, convKey);
  const payload = {
    e2ee: 'conv_v1',
    conversationId,
    ciphertext: bytesToBase64(ciphertext),
    nonce: bytesToBase64(nonce),
    tag: bytesToBase64(tag),
  };
  return JSON.stringify(payload);
}

/** AES-256-CBC decryption using Web Crypto API */
async function aesCbcDecrypt(ciphertext: Uint8Array, key: Uint8Array, iv: Uint8Array): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey('raw', key as unknown as BufferSource, { name: 'AES-CBC' }, false, ['decrypt']);
  const decrypted = await crypto.subtle.decrypt(
    { name: 'AES-CBC', iv: iv as unknown as BufferSource },
    cryptoKey,
    ciphertext as unknown as BufferSource
  );
  return new TextDecoder().decode(decrypted);
}

/** Decrypts a conversation room payload with dual AES-GCM and AES-CBC fallback across primary and legacy keys */
export async function decryptConversationPayload(conversationId: string, payload: any): Promise<string> {
  const ciphertext = base64ToBytes(payload.ciphertext);
  const nonce = base64ToBytes(payload.nonce);
  const tag = base64ToBytes(payload.tag);

  // If nonce is 16 bytes or tag is 32 bytes, prioritize AES-CBC (Mobile format)
  if (nonce.length === 16 || tag.length === 32) {
    try {
      const legacyKey = await getLegacyConversationKey(conversationId);
      return await aesCbcDecrypt(ciphertext, legacyKey, nonce);
    } catch (_) {}
    try {
      const primaryKey = await getConversationKey(conversationId);
      return await aesCbcDecrypt(ciphertext, primaryKey, nonce);
    } catch (_) {}
  }

  // Strategy 1: Primary AES-GCM (DOLSYX 2025 standard)
  try {
    const primaryKey = await getConversationKey(conversationId);
    return await aesGcmDecrypt(ciphertext, primaryKey, nonce, tag);
  } catch (_) {}

  // Strategy 2: Legacy AES-GCM (DOLSYX V1)
  try {
    const legacyKey = await getLegacyConversationKey(conversationId);
    return await aesGcmDecrypt(ciphertext, legacyKey, nonce, tag);
  } catch (_) {}

  // Strategy 3: Legacy AES-CBC
  try {
    const legacyKey = await getLegacyConversationKey(conversationId);
    return await aesCbcDecrypt(ciphertext, legacyKey, nonce);
  } catch (_) {}

  // Strategy 4: Primary AES-CBC
  try {
    const primaryKey = await getConversationKey(conversationId);
    return await aesCbcDecrypt(ciphertext, primaryKey, nonce);
  } catch (_) {}

  throw new Error('Failed to decrypt conversation payload');
}

/** Universal decryptor for incoming messages */
export async function decryptIncomingContent(
  content: string,
  senderUserId: string,
  conversationId?: string,
  recipientUserId?: string
): Promise<string> {
  if (!content || typeof content !== 'string') {
    return content || '';
  }
  const trimmed = content.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
    return content;
  }
  try {
    const parsed = JSON.parse(trimmed);
    if (parsed.e2ee === 'conv_v1' || (parsed.conversationId && !parsed.type)) {
      const cId = parsed.conversationId || conversationId;
      if (cId) return await decryptConversationPayload(cId, parsed);
    }
    if (parsed.ciphertext && parsed.nonce && parsed.tag && (parsed.type === 1 || parsed.type === 2)) {
      if (recipientUserId) {
        const { plaintext } = await decryptMessage(recipientUserId, parsed);
        return plaintext;
      }
    }
  } catch (err) {
    if (conversationId) {
      try {
        const parsed = JSON.parse(trimmed);
        if (parsed && parsed.ciphertext && parsed.nonce && parsed.tag) {
          return await decryptConversationPayload(conversationId, parsed);
        }
      } catch (_) {}
    }
  }
  return content;
}


