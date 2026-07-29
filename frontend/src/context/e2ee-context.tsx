'use client';

/**
 * E2EEContext — React context that provides E2EE state and operations
 * to the entire frontend app.
 *
 * Responsibilities:
 * - Initialize key generation on first login
 * - Upload public keys to server
 * - Provide encrypt/decrypt functions to chat components
 * - Listen for sync events and decrypt incoming messages
 * - Replenish one-time prekeys when running low
 */

import React, { createContext, useContext, useState, useCallback, useRef } from 'react';
import {
  generateAndStoreAllKeys,
  encryptMessage,
  decryptMessage,
  checkAndReplenishPreKeys,
  type RecipientKeyBundle,
  type MessagePayload,
} from '../utils/e2ee/cryptoService';
import {
  uploadKeys,
  fetchRecipientKeys,
  sendEncryptedMessage,
  syncMessages,
  uploadOneTimePreKeys,
  type SyncedMessage,
} from '../utils/e2ee/e2eeApi';
import { keyStore } from '../utils/e2ee/keyStore';

const DEVICE_ID = 1;

interface E2EEContextValue {
  isInitialized: boolean;
  isInitializing: boolean;
  initializeE2EE: (userId: string, token: string) => Promise<void>;
  encryptAndSend: (
    senderUserId: string,
    recipientEmail: string,
    conversationId: string,
    plaintext: string,
    token: string
  ) => Promise<void>;
  decryptIncoming: (
    recipientUserId: string,
    payload: MessagePayload,
    existingSessionKey?: Uint8Array
  ) => Promise<string>;
  syncAndDecryptAll: (
    userId: string,
    token: string
  ) => Promise<Array<{ senderEmail: string; plaintext: string; timestamp: string }>>;
  clearE2EEKeys: () => Promise<void>;
  error: string | null;
}

const E2EEContext = createContext<E2EEContextValue | null>(null);

export function E2EEProvider({ children }: { children: React.ReactNode }) {
  const [isInitialized, setIsInitialized] = useState(false);
  const [isInitializing, setIsInitializing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  // Cache of session keys: recipientUserId -> Uint8Array
  const sessionKeys = useRef<Map<string, Uint8Array>>(new Map());

  /**
   * Initialize E2EE for a logged-in user.
   * - Checks if keys already exist locally (returning user)
   * - If not, generates keys and uploads public keys to server (new device)
   */
  const initializeE2EE = useCallback(async (userId: string, token: string) => {
    if (isInitializing || isInitialized) return;
    setIsInitializing(true);
    setError(null);

    try {
      const existingIdentity = await keyStore.getIdentityKeyPair(userId);

      if (!existingIdentity) {
        // New device — generate all keys and upload
        console.log('[E2EE] Generating new key bundle...');
        const keyBundle = await generateAndStoreAllKeys(userId);
        await uploadKeys({ deviceId: DEVICE_ID, ...keyBundle }, token);
        console.log('[E2EE] Keys generated and uploaded.');
      } else {
        console.log('[E2EE] Existing keys found locally.');
        // Check prekey replenishment
        await checkAndReplenishPreKeys(userId, (keys) =>
          uploadOneTimePreKeys(DEVICE_ID, keys, token)
        );
      }

      setIsInitialized(true);
    } catch (err: any) {
      console.error('[E2EE] Initialization failed:', err);
      setError(err.message || 'E2EE initialization failed');
    } finally {
      setIsInitializing(false);
    }
  }, [isInitializing, isInitialized]);

  /**
   * Encrypt a plaintext message and send it to a recipient via the server.
   */
  const encryptAndSend = useCallback(async (
    senderUserId: string,
    recipientEmail: string,
    conversationId: string,
    plaintext: string,
    token: string
  ) => {
    setError(null);
    try {
      // Fetch recipient's public keys
      const recipientBundle = await fetchRecipientKeys(recipientEmail, token);

      if (!recipientBundle.devices || recipientBundle.devices.length === 0) {
        throw new Error('Recipient has no registered E2EE devices');
      }

      const recipients = [];

      for (const device of recipientBundle.devices) {
        const existingKey = sessionKeys.current.get(`${recipientBundle.userId}-${device.deviceId}`);

        const keyBundle: RecipientKeyBundle = {
          userId: recipientBundle.userId,
          deviceId: device.deviceId,
          identityKeyPublic: device.identityKeyPublic,
          signedPreKeyPublic: device.signedPreKeyPublic,
          signedPreKeySignature: device.signedPreKeySignature,
          oneTimePreKey: device.oneTimePreKey
        };

        const { payload, sharedSecret } = await encryptMessage(
          senderUserId,
          keyBundle,
          plaintext,
          existingKey
        );

        // Cache the shared secret for future messages
        sessionKeys.current.set(`${recipientBundle.userId}-${device.deviceId}`, sharedSecret);

        recipients.push({
          recipientDeviceId: `device-${device.deviceId}`, // Server lookup key
          recipientUserId: recipientBundle.userId,
          type: payload.type,
          ciphertext: JSON.stringify(payload), // Full payload as ciphertext blob
        });
      }

      await sendEncryptedMessage({ senderDeviceId: DEVICE_ID, conversationId, recipients }, token);
    } catch (err: any) {
      console.error('[E2EE] Failed to encrypt and send:', err);
      setError(err.message || 'Failed to send encrypted message');
      throw err;
    }
  }, []);

  /**
   * Decrypt a single incoming message payload.
   */
  const decryptIncoming = useCallback(async (
    recipientUserId: string,
    payload: MessagePayload,
    existingSessionKey?: Uint8Array
  ): Promise<string> => {
    const { plaintext, sharedSecret } = await decryptMessage(recipientUserId, payload, existingSessionKey);
    return plaintext;
  }, []);

  /**
   * Pull all undelivered encrypted messages from server and decrypt them.
   */
  const syncAndDecryptAll = useCallback(async (
    userId: string,
    token: string
  ): Promise<Array<{ senderEmail: string; plaintext: string; timestamp: string }>> => {
    const messages: SyncedMessage[] = await syncMessages(DEVICE_ID, token);
    const results = [];

    for (const msg of messages) {
      try {
        const payload: MessagePayload = JSON.parse(msg.ciphertext);
        const existingKey = sessionKeys.current.get(`${msg.senderUserId}-${msg.senderDeviceId}`);
        const { plaintext, sharedSecret } = await decryptMessage(userId, payload, existingKey);

        sessionKeys.current.set(`${msg.senderUserId}-${msg.senderDeviceId}`, sharedSecret);

        results.push({
          senderEmail: msg.senderEmail,
          plaintext,
          timestamp: msg.timestamp
        });
      } catch (decryptErr) {
        console.error(`[E2EE] Failed to decrypt message ${msg.id}:`, decryptErr);
      }
    }

    return results;
  }, []);

  /**
   * Clear all local E2EE key material (e.g., on logout).
   */
  const clearE2EEKeys = useCallback(async () => {
    await keyStore.clearAll();
    sessionKeys.current.clear();
    setIsInitialized(false);
  }, []);

  return (
    <E2EEContext.Provider value={{
      isInitialized,
      isInitializing,
      initializeE2EE,
      encryptAndSend,
      decryptIncoming,
      syncAndDecryptAll,
      clearE2EEKeys,
      error
    }}>
      {children}
    </E2EEContext.Provider>
  );
}

export function useE2EE(): E2EEContextValue {
  const ctx = useContext(E2EEContext);
  if (!ctx) {
    throw new Error('useE2EE must be used within an <E2EEProvider>');
  }
  return ctx;
}
