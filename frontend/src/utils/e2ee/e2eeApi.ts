/**
 * E2EE API Client — Handles all backend communication for key management,
 * message delivery, and encrypted backup.
 */

const API_BASE = process.env.NEXT_PUBLIC_API_URL || '';

async function authFetch(endpoint: string, options: RequestInit = {}, token: string): Promise<Response> {
  const res = await fetch(`${API_BASE}${endpoint}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
      ...options.headers,
    },
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body?.error || `Request failed: ${res.status}`);
  }

  return res;
}

// ─────────────────────────────────────────────────────────────────────────────
// Key Management
// ─────────────────────────────────────────────────────────────────────────────

export interface UploadKeysPayload {
  deviceId: number;
  identityKeyPublic: string;
  signedPreKeyPublic: string;
  signedPreKeySignature: string;
  oneTimePreKeys: Array<{ keyId: number; publicKey: string }>;
}

export async function uploadKeys(payload: UploadKeysPayload, token: string): Promise<void> {
  await authFetch('/api/keys/upload', {
    method: 'POST',
    body: JSON.stringify(payload),
  }, token);
}

export async function uploadOneTimePreKeys(
  deviceId: number,
  oneTimePreKeys: Array<{ keyId: number; publicKey: string }>,
  token: string
): Promise<void> {
  // For replenishment — only sends new OPKs (server will add them to existing batch)
  await authFetch('/api/keys/upload', {
    method: 'POST',
    body: JSON.stringify({ deviceId, oneTimePreKeys, replenishOnly: true }),
  }, token);
}

export interface RecipientKeyBundle {
  userId: string;
  devices: Array<{
    deviceId: number;
    identityKeyPublic: string;
    signedPreKeyPublic: string;
    signedPreKeySignature: string;
    oneTimePreKey?: { keyId: number; publicKey: string } | null;
  }>;
}

export async function fetchRecipientKeys(email: string, token: string): Promise<RecipientKeyBundle> {
  const res = await authFetch(`/api/keys/fetch/${encodeURIComponent(email)}`, {}, token);
  const body = await res.json();
  return body.data;
}

// ─────────────────────────────────────────────────────────────────────────────
// Encrypted Message Delivery
// ─────────────────────────────────────────────────────────────────────────────

export interface EncryptedMessageRecipient {
  recipientDeviceId: string; // The prisma Device.id (UUID)
  recipientUserId: string;
  type: 1 | 2;
  ciphertext: string;
}

export async function sendEncryptedMessage(payload: {
  senderDeviceId: number;
  conversationId: string;
  recipients: EncryptedMessageRecipient[];
}, token: string): Promise<void> {
  await authFetch('/api/messages/send', {
    method: 'POST',
    body: JSON.stringify(payload),
  }, token);
}

export interface SyncedMessage {
  id: string;
  senderUserId: string;
  senderEmail: string;
  senderDeviceId: number;
  type: number;
  ciphertext: string;
  timestamp: string;
}

export async function syncMessages(deviceId: number, token: string): Promise<SyncedMessage[]> {
  const res = await authFetch(`/api/messages/sync?deviceId=${deviceId}`, {}, token);
  const body = await res.json();
  return body.data ?? [];
}

// ─────────────────────────────────────────────────────────────────────────────
// Encrypted Backup
// ─────────────────────────────────────────────────────────────────────────────

export async function saveEncryptedBackup(payload: {
  encryptedData: string;
  salt: string;
  nonce: string;
}, token: string): Promise<void> {
  await authFetch('/api/backup/save', {
    method: 'POST',
    body: JSON.stringify(payload),
  }, token);
}

export async function loadEncryptedBackup(token: string): Promise<{
  encryptedData: string;
  salt: string;
  nonce: string;
  updatedAt: string;
} | null> {
  try {
    const res = await authFetch('/api/backup/load', {}, token);
    const body = await res.json();
    return body.data;
  } catch {
    return null; // No backup exists yet
  }
}
