import * as crypto from 'crypto';

// Constants for HKDF info strings per Signal Double Ratchet spec
const KDF_RK_INFO = "KDF_RK";
const KDF_CK_INFO = "KDF_CK";

export interface RatchetState {
  DHs: Uint8Array;      // DH Ratchet key pair (private)
  DHr: Uint8Array | null; // DH Ratchet public key (remote)
  RK: Buffer;           // 32-byte Root Key
  CKs: Buffer | null;   // 32-byte Chain Key for sending
  CKr: Buffer | null;   // 32-byte Chain Key for receiving
  Ns: number;           // Message number for sending
  Nr: number;           // Message number for receiving
  PN: number;           // Number of messages in previous sending chain
  MKSKIPPED: Map<string, Buffer>; // Dictionary of skipped message keys
}

export interface EncryptedMessagePayload {
  header: {
    dh: Uint8Array; // Sender's current DH ratchet public key
    pn: number;     // Previous chain length
    n: number;      // Message number
  };
  ciphertext: Buffer;
  nonce: Buffer;
  tag: Buffer;
}

/**
 * Double Ratchet Algorithm implementation.
 * Combines a symmetric-key ratchet with a DH ratchet.
 */
export class DoubleRatchet {
  
  /**
   * Initialize a new Double Ratchet state (Alice initializing to talk to Bob).
   * @param SK Shared secret derived from X3DH
   * @param bobRatchetPubKey Bob's public ratchet key (often his signed prekey for the first message)
   * @param myRatchetKeyPair Alice's generated DH key pair for this ratchet
   */
  static initAlice(
    SK: Buffer,
    bobRatchetPubKey: Uint8Array,
    myRatchetKeyPair: { publicKey: Uint8Array; privateKey: Uint8Array }
  ): RatchetState {
    const state: RatchetState = {
      DHs: myRatchetKeyPair.privateKey,
      DHr: bobRatchetPubKey,
      RK: SK,
      CKs: null,
      CKr: null,
      Ns: 0,
      Nr: 0,
      PN: 0,
      MKSKIPPED: new Map(),
    };

    // Alice immediately does the first DH ratchet step to get her sending chain key
    const dhOut = this.dh(state.DHs, state.DHr!);
    const [rk, cks] = this.kdf_rk(state.RK, dhOut);
    state.RK = rk;
    state.CKs = cks;

    return state;
  }

  /**
   * Initialize a new Double Ratchet state (Bob initializing upon receiving Alice's first message).
   * @param SK Shared secret derived from X3DH
   * @param myRatchetKeyPair Bob's key pair (the one matching the pub key Alice used, usually the signed prekey)
   */
  static initBob(
    SK: Buffer,
    myRatchetKeyPair: { publicKey: Uint8Array; privateKey: Uint8Array }
  ): RatchetState {
    return {
      DHs: myRatchetKeyPair.privateKey,
      DHr: null,
      RK: SK,
      CKs: null,
      CKr: null,
      Ns: 0,
      Nr: 0,
      PN: 0,
      MKSKIPPED: new Map(),
    };
  }

  /**
   * Advances the sending chain and generates a Message Key.
   */
  static ratchetEncryptStep(state: RatchetState): { state: RatchetState; messageKey: Buffer } {
    if (!state.CKs) {
      throw new Error("Cannot encrypt without a sending chain key. Await remote DH ratchet step.");
    }
    const [cks, mk] = this.kdf_ck(state.CKs);
    state.CKs = cks;
    state.Ns += 1;
    return { state, messageKey: mk };
  }

  /**
   * Advances the receiving chain or performs a DH ratchet step if a new DH public key is received.
   */
  static ratchetDecryptStep(
    state: RatchetState,
    header: EncryptedMessagePayload['header'],
    newLocalRatchetKeyPairGenerator: () => { publicKey: Uint8Array; privateKey: Uint8Array }
  ): { state: RatchetState; messageKey: Buffer } {
    
    // Check if we need to perform a DH ratchet step (new remote public key)
    if (!state.DHr || Buffer.compare(Buffer.from(header.dh), Buffer.from(state.DHr)) !== 0) {
      this.skipMessageKeys(state, header.pn);
      this.dhRatchet(state, header.dh, newLocalRatchetKeyPairGenerator);
    }
    
    this.skipMessageKeys(state, header.n);
    
    if (!state.CKr) {
        throw new Error("Receiving chain key is null");
    }
    const [ckr, mk] = this.kdf_ck(state.CKr);
    state.CKr = ckr;
    state.Nr += 1;
    
    return { state, messageKey: mk };
  }

  private static dhRatchet(
    state: RatchetState,
    headerDh: Uint8Array,
    newLocalRatchetKeyPairGenerator: () => { publicKey: Uint8Array; privateKey: Uint8Array }
  ) {
    state.PN = state.Ns;
    state.Ns = 0;
    state.Nr = 0;
    state.DHr = headerDh;

    // First DH half-step (receive)
    let dhOut = this.dh(state.DHs, state.DHr);
    let [rk, ckr] = this.kdf_rk(state.RK, dhOut);
    state.RK = rk;
    state.CKr = ckr;

    // Second DH half-step (send)
    const newKeyPair = newLocalRatchetKeyPairGenerator();
    state.DHs = newKeyPair.privateKey;
    dhOut = this.dh(state.DHs, state.DHr);
    let [rk2, cks] = this.kdf_rk(state.RK, dhOut);
    state.RK = rk2;
    state.CKs = cks;
  }

  private static skipMessageKeys(state: RatchetState, until: number) {
    if (state.Nr + 1000 < until) {
      throw new Error("Too many skipped messages");
    }
    if (state.CKr != null) {
      while (state.Nr < until) {
        const [ckr, mk] = this.kdf_ck(state.CKr);
        state.CKr = ckr;
        state.MKSKIPPED.set(`${Buffer.from(state.DHr!).toString('hex')}_${state.Nr}`, mk);
        state.Nr += 1;
      }
    }
  }

  // --- Cryptographic Primitives ---

  /** Diffie-Hellman function (Curve25519) */
  private static dh(privKey: Uint8Array, pubKey: Uint8Array): Buffer {
    // We are simulating the crypto operation using libsodium wrapper logic.
    // Since this file uses Node.js crypto, we would ideally use crypto.diffieHellman
    // However, X25519 requires specific handling. In a real app we'd use sodium.crypto_scalarmult here.
    // For the sake of minimizing dependencies in this specific snippet, we'll assume it's imported 
    // or passed in. To keep it clean, let's use node crypto.
    const ecdh = crypto.createECDH('x25519');
    ecdh.setPrivateKey(privKey);
    return ecdh.computeSecret(pubKey);
  }

  /**
   * KDF for Root Key chain. Takes 32-byte RK and 32-byte DH output.
   * Returns a pair (32-byte RK, 32-byte CK).
   */
  private static kdf_rk(rk: Buffer, dhOut: Buffer): [Buffer, Buffer] {
    const prk = crypto.createHmac('sha256', rk).update(dhOut).digest();
    
    const infoBytes = Buffer.from(KDF_RK_INFO);
    const t1 = crypto.createHmac('sha256', prk).update(Buffer.concat([infoBytes, Buffer.from([1])])).digest();
    const t2 = crypto.createHmac('sha256', prk).update(Buffer.concat([t1, infoBytes, Buffer.from([2])])).digest();
    
    return [t1, t2];
  }

  /**
   * KDF for Chain Key. Takes 32-byte CK.
   * Returns a pair (32-byte CK, 32-byte MK).
   */
  private static kdf_ck(ck: Buffer): [Buffer, Buffer] {
    const mk = crypto.createHmac('sha256', ck).update(Buffer.from([0x01])).digest();
    const nextCk = crypto.createHmac('sha256', ck).update(Buffer.from([0x02])).digest();
    return [nextCk, mk];
  }
}
