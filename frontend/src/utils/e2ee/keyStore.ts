/**
 * E2EE Key Store — IndexedDB-backed storage for local cryptographic keys.
 * Keys NEVER leave the device in plaintext.
 * Uses the `idb` library for a promise-based IndexedDB API.
 */
import { openDB, DBSchema, IDBPDatabase } from 'idb';

const DB_NAME = 'dolsyx_e2ee';
const DB_VERSION = 1;

interface E2EEKeyPair {
  publicKey: Uint8Array;
  privateKey: Uint8Array;
}

interface KeyStoreSchema extends DBSchema {
  identity_keypair: {
    key: string; // userId
    value: {
      userId: string;
      publicKey: Uint8Array;
      privateKey: Uint8Array;
    };
  };
  signed_prekeys: {
    key: number; // deviceId number key
    value: {
      deviceId: number;
      keyId: number;
      publicKey: Uint8Array;
      privateKey: Uint8Array;
      signature: Uint8Array;
      createdAt: number;
    };
  };
  one_time_prekeys: {
    key: number; // keyId
    value: {
      keyId: number;
      publicKey: Uint8Array;
      privateKey: Uint8Array;
    };
  };
  ratchet_sessions: {
    key: string; // conversationId or recipientUserId
    value: {
      sessionId: string;
      state: string; // JSON-serialized RatchetState
      updatedAt: number;
    };
  };
}

let db: IDBPDatabase<KeyStoreSchema> | null = null;

async function getDb(): Promise<IDBPDatabase<KeyStoreSchema>> {
  if (db) return db;
  db = await openDB<KeyStoreSchema>(DB_NAME, DB_VERSION, {
    upgrade(database) {
      if (!database.objectStoreNames.contains('identity_keypair')) {
        database.createObjectStore('identity_keypair', { keyPath: 'userId' });
      }
      if (!database.objectStoreNames.contains('signed_prekeys')) {
        database.createObjectStore('signed_prekeys', { keyPath: 'deviceId' });
      }
      if (!database.objectStoreNames.contains('one_time_prekeys')) {
        database.createObjectStore('one_time_prekeys', { keyPath: 'keyId' });
      }
      if (!database.objectStoreNames.contains('ratchet_sessions')) {
        database.createObjectStore('ratchet_sessions', { keyPath: 'sessionId' });
      }
    }
  });
  return db;
}

export const keyStore = {
  // ─── Identity Key ────────────────────────────────────────────────────────────
  async saveIdentityKeyPair(userId: string, keyPair: E2EEKeyPair): Promise<void> {
    const database = await getDb();
    await database.put('identity_keypair', {
      userId,
      publicKey: keyPair.publicKey,
      privateKey: keyPair.privateKey
    });
  },

  async getIdentityKeyPair(userId: string): Promise<E2EEKeyPair | null> {
    const database = await getDb();
    const record = await database.get('identity_keypair', userId);
    if (!record) return null;
    return { publicKey: record.publicKey, privateKey: record.privateKey };
  },

  // ─── Signed PreKey ──────────────────────────────────────────────────────────
  async saveSignedPreKey(deviceId: number, keyId: number, keyPair: E2EEKeyPair, signature: Uint8Array): Promise<void> {
    const database = await getDb();
    await database.put('signed_prekeys', {
      deviceId,
      keyId,
      publicKey: keyPair.publicKey,
      privateKey: keyPair.privateKey,
      signature,
      createdAt: Date.now()
    });
  },

  async getSignedPreKey(deviceId: number): Promise<{ keyId: number; keyPair: E2EEKeyPair; signature: Uint8Array } | null> {
    const database = await getDb();
    const record = await database.get('signed_prekeys', deviceId);
    if (!record) return null;
    return {
      keyId: record.keyId,
      keyPair: { publicKey: record.publicKey, privateKey: record.privateKey },
      signature: record.signature
    };
  },

  // ─── One-Time PreKeys ────────────────────────────────────────────────────────
  async saveOneTimePreKeys(keys: Array<{ keyId: number; publicKey: Uint8Array; privateKey: Uint8Array }>): Promise<void> {
    const database = await getDb();
    const tx = database.transaction('one_time_prekeys', 'readwrite');
    await Promise.all(keys.map(k => tx.store.put(k)));
    await tx.done;
  },

  async getOneTimePreKey(keyId: number): Promise<E2EEKeyPair | null> {
    const database = await getDb();
    const record = await database.get('one_time_prekeys', keyId);
    if (!record) return null;
    return { publicKey: record.publicKey, privateKey: record.privateKey };
  },

  async deleteOneTimePreKey(keyId: number): Promise<void> {
    const database = await getDb();
    await database.delete('one_time_prekeys', keyId);
  },

  async countOneTimePreKeys(): Promise<number> {
    const database = await getDb();
    return database.count('one_time_prekeys');
  },

  async getAllOneTimePreKeyPublics(): Promise<Array<{ keyId: number; publicKey: Uint8Array }>> {
    const database = await getDb();
    const all = await database.getAll('one_time_prekeys');
    return all.map(k => ({ keyId: k.keyId, publicKey: k.publicKey }));
  },

  // ─── Ratchet Sessions ────────────────────────────────────────────────────────
  async saveRatchetSession(sessionId: string, state: object): Promise<void> {
    const database = await getDb();
    await database.put('ratchet_sessions', {
      sessionId,
      state: JSON.stringify(state),
      updatedAt: Date.now()
    });
  },

  async getRatchetSession(sessionId: string): Promise<object | null> {
    const database = await getDb();
    const record = await database.get('ratchet_sessions', sessionId);
    if (!record) return null;
    return JSON.parse(record.state);
  },

  async deleteRatchetSession(sessionId: string): Promise<void> {
    const database = await getDb();
    await database.delete('ratchet_sessions', sessionId);
  },

  // ─── Wipe All Local Keys (e.g., on logout) ───────────────────────────────────
  async clearAll(): Promise<void> {
    const database = await getDb();
    const tx = database.transaction(
      ['identity_keypair', 'signed_prekeys', 'one_time_prekeys', 'ratchet_sessions'],
      'readwrite'
    );
    await Promise.all([
      tx.objectStore('identity_keypair').clear(),
      tx.objectStore('signed_prekeys').clear(),
      tx.objectStore('one_time_prekeys').clear(),
      tx.objectStore('ratchet_sessions').clear()
    ]);
    await tx.done;
  }
};
