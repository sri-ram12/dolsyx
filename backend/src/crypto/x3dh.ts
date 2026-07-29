import _sodium from 'libsodium-wrappers';

// Constants for HKDF info strings
const X3DH_INFO = "X3DH_V1";

export class X3DH {
  /**
   * Generates a shared secret using X3DH as the Initiator (Alice sending to Bob).
   * 
   * @param myIdentityKeyPriv Alice's private identity key (Curve25519)
   * @param myEphemeralKeyPriv Alice's ephemeral private key (Curve25519)
   * @param theirIdentityKeyPub Bob's public identity key (Curve25519)
   * @param theirSignedPreKeyPub Bob's public signed pre-key (Curve25519)
   * @param theirOneTimePreKeyPub Bob's public one-time pre-key (Curve25519) - Optional
   * @returns The 32-byte shared secret (SK)
   */
  static async initiator(
    myIdentityKeyPriv: Uint8Array,
    myEphemeralKeyPriv: Uint8Array,
    theirIdentityKeyPub: Uint8Array,
    theirSignedPreKeyPub: Uint8Array,
    theirOneTimePreKeyPub?: Uint8Array
  ): Promise<Uint8Array> {
    await _sodium.ready;
    const sodium = _sodium;

    // DH1 = DH(IK_A, SPK_B)
    const dh1 = sodium.crypto_scalarmult(myIdentityKeyPriv, theirSignedPreKeyPub);
    // DH2 = DH(EK_A, IK_B)
    const dh2 = sodium.crypto_scalarmult(myEphemeralKeyPriv, theirIdentityKeyPub);
    // DH3 = DH(EK_A, SPK_B)
    const dh3 = sodium.crypto_scalarmult(myEphemeralKeyPriv, theirSignedPreKeyPub);
    
    let sharedSecretInput = new Uint8Array([...dh1, ...dh2, ...dh3]);

    if (theirOneTimePreKeyPub) {
      // DH4 = DH(EK_A, OPK_B)
      const dh4 = sodium.crypto_scalarmult(myEphemeralKeyPriv, theirOneTimePreKeyPub);
      sharedSecretInput = new Uint8Array([...sharedSecretInput, ...dh4]);
    }
    
    return this.hkdfSha256(sharedSecretInput, new Uint8Array(32), X3DH_INFO, 32);
  }

  /**
   * Generates a shared secret using X3DH as the Responder (Bob receiving from Alice).
   * 
   * @param myIdentityKeyPriv Bob's private identity key (Curve25519)
   * @param mySignedPreKeyPriv Bob's private signed pre-key (Curve25519)
   * @param myOneTimePreKeyPriv Bob's private one-time pre-key (Curve25519) - Optional
   * @param theirIdentityKeyPub Alice's public identity key (Curve25519)
   * @param theirEphemeralKeyPub Alice's public ephemeral key (Curve25519)
   * @returns The 32-byte shared secret (SK)
   */
  static async responder(
    myIdentityKeyPriv: Uint8Array,
    mySignedPreKeyPriv: Uint8Array,
    theirIdentityKeyPub: Uint8Array,
    theirEphemeralKeyPub: Uint8Array,
    myOneTimePreKeyPriv?: Uint8Array
  ): Promise<Uint8Array> {
    await _sodium.ready;
    const sodium = _sodium;

    // DH1 = DH(SPK_B, IK_A) = DH(IK_A, SPK_B)
    const dh1 = sodium.crypto_scalarmult(mySignedPreKeyPriv, theirIdentityKeyPub);
    // DH2 = DH(IK_B, EK_A) = DH(EK_A, IK_B)
    const dh2 = sodium.crypto_scalarmult(myIdentityKeyPriv, theirEphemeralKeyPub);
    // DH3 = DH(SPK_B, EK_A) = DH(EK_A, SPK_B)
    const dh3 = sodium.crypto_scalarmult(mySignedPreKeyPriv, theirEphemeralKeyPub);
    
    let sharedSecretInput = new Uint8Array([...dh1, ...dh2, ...dh3]);

    if (myOneTimePreKeyPriv) {
      // DH4 = DH(OPK_B, EK_A) = DH(EK_A, OPK_B)
      const dh4 = sodium.crypto_scalarmult(myOneTimePreKeyPriv, theirEphemeralKeyPub);
      sharedSecretInput = new Uint8Array([...sharedSecretInput, ...dh4]);
    }

    return this.hkdfSha256(sharedSecretInput, new Uint8Array(32), X3DH_INFO, 32);
  }

  /**
   * HKDF-SHA256 Implementation (Extract and Expand)
   */
  private static hkdfSha256(
    ikm: Uint8Array, 
    salt: Uint8Array, 
    info: string, 
    length: number
  ): Uint8Array {
    const sodium = _sodium; // Assumes ready
    
    // 1. Extract: PRK = HMAC-SHA256(salt, IKM)
    const prk = sodium.crypto_auth_hmacsha256(ikm, salt.length === 0 ? new Uint8Array(32) : salt);

    // 2. Expand: T(1) = HMAC-SHA256(PRK, info | 0x01)
    const infoBytes = sodium.from_string(info);
    const expandInput = new Uint8Array([...infoBytes, 0x01]);
    const t1 = sodium.crypto_auth_hmacsha256(expandInput, prk);

    return t1.slice(0, length);
  }

  /**
   * Utility to convert Ed25519 Public Key to X25519 Public Key
   */
  static async ed25519ToX25519Public(ed25519Pub: Uint8Array): Promise<Uint8Array> {
    await _sodium.ready;
    return _sodium.crypto_sign_ed25519_pk_to_curve25519(ed25519Pub);
  }

  /**
   * Utility to convert Ed25519 Private Key to X25519 Private Key
   */
  static async ed25519ToX25519Private(ed25519Priv: Uint8Array): Promise<Uint8Array> {
    await _sodium.ready;
    return _sodium.crypto_sign_ed25519_sk_to_curve25519(ed25519Priv);
  }
}
