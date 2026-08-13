import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents the Signal Protocol message types.
/// Type 1 = PreKeyWhisperMessage (first message, includes the X3DH ephemeral key).
/// Type 2 = WhisperMessage (subsequent messages, uses the established session key).
class MessagePayload {
  final int type;
  final int senderDeviceId;
  final String? ephemeralKeyPublic; // Base64, only for type=1
  final int? oneTimePreKeyId; // Only for type=1
  final String ciphertext; // Base64
  final String nonce; // Base64
  final String tag; // Base64

  MessagePayload({
    required this.type,
    required this.senderDeviceId,
    this.ephemeralKeyPublic,
    this.oneTimePreKeyId,
    required this.ciphertext,
    required this.nonce,
    required this.tag,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'senderDeviceId': senderDeviceId,
        if (ephemeralKeyPublic != null) 'ephemeralKeyPublic': ephemeralKeyPublic,
        if (oneTimePreKeyId != null) 'oneTimePreKeyId': oneTimePreKeyId,
        'ciphertext': ciphertext,
        'nonce': nonce,
        'tag': tag,
      };

  factory MessagePayload.fromJson(Map<String, dynamic> json) => MessagePayload(
        type: json['type'] as int,
        senderDeviceId: json['senderDeviceId'] as int,
        ephemeralKeyPublic: json['ephemeralKeyPublic'] as String?,
        oneTimePreKeyId: json['oneTimePreKeyId'] as int?,
        ciphertext: json['ciphertext'] as String,
        nonce: json['nonce'] as String,
        tag: json['tag'] as String,
      );
}

const int _deviceId = 1;
const int _oneTimePreKeyCount = 50;
const String _identityPublicKey = 'e2ee_identity_public';
const String _identityPrivateKey = 'e2ee_identity_private';
const String _signedPreKeyPublic = 'e2ee_signed_public';
const String _signedPreKeyPrivate = 'e2ee_signed_private';
const String _sessionPrefix = 'e2ee_session_';
const String _otpkPrefix = 'e2ee_otpk_';
const String _otpkCountKey = 'e2ee_otpk_count';
const String _otpkIdsKey = 'e2ee_otpk_ids';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _x25519 = X25519();
  final _aesCbc = AesCbc.with256bits(macAlgorithm: Hmac.sha256());
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  // ─────────────────────────────────────────────────────────────────────────
  // Key Generation
  // ─────────────────────────────────────────────────────────────────────────

  /// Generates all E2EE keys on first login and persists them locally.
  /// Returns a payload suitable for uploading to the server.
  Future<Map<String, dynamic>> generateAndStoreAllKeys(String userId) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Identity Key Pair (X25519)
    final identityKeyPair = await _x25519.newKeyPair();
    final identityPublicKey = await identityKeyPair.extractPublicKey();
    final identityPrivateBytes = await identityKeyPair.extractPrivateKeyBytes();

    await prefs.setString(_identityPublicKey, _bytesToBase64(identityPublicKey.bytes));
    await prefs.setString(_identityPrivateKey, _bytesToBase64(identityPrivateBytes));

    // 2. Signed PreKey (X25519) — we store the "signature" as a HMAC of the public key
    //    using the identity private key (simplified since Ed25519 isn't available natively in cryptography package)
    final signedPreKeyPair = await _x25519.newKeyPair();
    final signedPreKeyPublic = await signedPreKeyPair.extractPublicKey();
    final signedPreKeyPrivateBytes = await signedPreKeyPair.extractPrivateKeyBytes();

    // Sign = HMAC-SHA256(signedPreKeyPublic, identityPrivateKey)
    final signatureBytes = await _hmacSign(signedPreKeyPublic.bytes, identityPrivateBytes);

    await prefs.setString(_signedPreKeyPublic, _bytesToBase64(signedPreKeyPublic.bytes));
    await prefs.setString(_signedPreKeyPrivate, _bytesToBase64(signedPreKeyPrivateBytes));

    // 3. One-Time PreKeys
    final otpkPublicBatch = <Map<String, dynamic>>[];
    final otpkIds = <int>[];

    for (int i = 0; i < _oneTimePreKeyCount; i++) {
      final kp = await _x25519.newKeyPair();
      final pub = await kp.extractPublicKey();
      final priv = await kp.extractPrivateKeyBytes();
      await prefs.setString('$_otpkPrefix${i}_pub', _bytesToBase64(pub.bytes));
      await prefs.setString('$_otpkPrefix${i}_priv', _bytesToBase64(priv));
      otpkIds.add(i);
      otpkPublicBatch.add({'keyId': i, 'publicKey': _bytesToBase64(pub.bytes)});
    }

    await prefs.setInt(_otpkCountKey, _oneTimePreKeyCount);
    await prefs.setString(_otpkIdsKey, jsonEncode(otpkIds));

    return {
      'deviceId': _deviceId,
      'identityKeyPublic': _bytesToBase64(identityPublicKey.bytes),
      'signedPreKeyPublic': _bytesToBase64(signedPreKeyPublic.bytes),
      'signedPreKeySignature': _bytesToBase64(signatureBytes),
      'oneTimePreKeys': otpkPublicBatch,
    };
  }

  /// Returns true if the device already has keys generated.
  Future<bool> hasKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_identityPublicKey) != null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Encryption (X3DH + AES-CBC)
  // ─────────────────────────────────────────────────────────────────────────

  /// Encrypts [plaintext] for [recipientKeyBundle] using X3DH.
  /// Returns an E2EE [MessagePayload] ready to be sent to the server.
  Future<MessagePayload> encryptMessage({
    required Map<String, dynamic> recipientKeyBundle,
    required String plaintext,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Check if we have an existing session
    final recipientUserId = (recipientKeyBundle['userId'] ?? recipientKeyBundle['id'] ?? recipientKeyBundle['_id'] ?? '').toString();
    final existingSession = recipientUserId.isNotEmpty ? prefs.getString('$_sessionPrefix$recipientUserId') : null;

    Uint8List sessionKey;
    String? ephemeralKeyPublicB64;
    int? oneTimePreKeyId;
    int msgType = 2; // default to type 2 (existing session); overridden below for type 1

    if (existingSession != null) {
      // Type 2 — use existing session key
      sessionKey = base64Decode(existingSession);
      msgType = 2;
    } else {
      // Type 1 — perform X3DH to establish a new session
      msgType = 1;
      final myIdentityPrivateBytes = base64Decode(prefs.getString(_identityPrivateKey)!);

      // Decode recipient's keys
      final List<dynamic> devices = (recipientKeyBundle['devices'] as List<dynamic>?) ?? [];
      if (devices.isEmpty) {
        throw Exception('No E2EE devices found for recipient');
      }
      final device = devices.first as Map<String, dynamic>;

      final recipientIdentityKeyBytes = base64Decode(device['identityKeyPublic'] as String);
      final recipientSignedPreKeyBytes = base64Decode(device['signedPreKeyPublic'] as String);
      final otpk = device['oneTimePreKey'] as Map<String, dynamic>?;

      // Generate ephemeral key pair
      final ephemeralKeyPair = await _x25519.newKeyPair();
      final ephemeralPublic = await ephemeralKeyPair.extractPublicKey();
      final ephemeralPrivateBytes = await ephemeralKeyPair.extractPrivateKeyBytes();
      ephemeralKeyPublicB64 = _bytesToBase64(ephemeralPublic.bytes);

      // X3DH: Compute DH1, DH2, DH3, (DH4 if OTPK)
      // DH1 = DH(IK_A, SPK_B)
      // DH2 = DH(EK_A, IK_B)
      // DH3 = DH(EK_A, SPK_B)
      // DH4 = DH(EK_A, OTPK_B) [optional]

      final dh1 = await _dh(myIdentityPrivateBytes, recipientSignedPreKeyBytes);
      final dh2 = await _dh(ephemeralPrivateBytes, recipientIdentityKeyBytes);
      final dh3 = await _dh(ephemeralPrivateBytes, recipientSignedPreKeyBytes);

      final dhMaterial = <int>[...dh1, ...dh2, ...dh3];

      if (otpk != null) {
        final otpkBytes = base64Decode(otpk['publicKey'] as String);
        final dh4 = await _dh(ephemeralPrivateBytes, otpkBytes);
        dhMaterial.addAll(dh4);
        oneTimePreKeyId = otpk['keyId'] as int;
      }

      // HKDF to derive 32-byte session key
      sessionKey = await _deriveSessionKey(Uint8List.fromList(dhMaterial));

      // Save session for future messages
      await prefs.setString('$_sessionPrefix$recipientUserId', _bytesToBase64(sessionKey));
    }

    // Encrypt with AES-256-CBC
    final plaintextBytes = utf8.encode(plaintext);
    final nonce = _generateNonce(16);
    final secretKey = SecretKey(sessionKey);
    final secretBox = await _aesCbc.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    return MessagePayload(
      type: msgType,
      senderDeviceId: _deviceId,
      ephemeralKeyPublic: ephemeralKeyPublicB64,
      oneTimePreKeyId: oneTimePreKeyId,
      ciphertext: _bytesToBase64(secretBox.cipherText),
      nonce: _bytesToBase64(nonce),
      tag: _bytesToBase64(secretBox.mac.bytes),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Decryption
  // ─────────────────────────────────────────────────────────────────────────

  /// Decrypts an incoming [MessagePayload] from [senderUserId].
  Future<String> decryptMessage({
    required String senderUserId,
    required MessagePayload payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    Uint8List sessionKey;

    if (payload.type == 2) {
      // Type 2 — must have existing session
      final existingSession = prefs.getString('$_sessionPrefix$senderUserId');
      if (existingSession == null) throw Exception('No session found for $senderUserId');
      sessionKey = base64Decode(existingSession);
    } else {
      // Type 1 — compute X3DH on our end to derive the session key
      final myIdentityPrivateBytes = base64Decode(prefs.getString(_identityPrivateKey)!);
      final mySignedPreKeyPrivateBytes = base64Decode(prefs.getString(_signedPreKeyPrivate)!);

      final senderEphemeralPublicBytes = base64Decode(payload.ephemeralKeyPublic!);

      // Recover sender's identity key from their recipient key bundle?
      // We don't have it here — we need to have it stored during session setup.
      // For now, read it from local session state (stored when key bundle was fetched)
      final senderIdentityKey = prefs.getString('$_sessionPrefix${senderUserId}_ik');
      if (senderIdentityKey == null) throw Exception('No sender identity key found for $senderUserId');
      final senderIdentityKeyBytes = base64Decode(senderIdentityKey);

      // X3DH (recipient side):
      // DH1 = DH(SPK_B, IK_A) 
      // DH2 = DH(IK_B, EK_A)
      // DH3 = DH(SPK_B, EK_A)
      final dh1 = await _dh(mySignedPreKeyPrivateBytes, senderIdentityKeyBytes);
      final dh2 = await _dh(myIdentityPrivateBytes, senderEphemeralPublicBytes);
      final dh3 = await _dh(mySignedPreKeyPrivateBytes, senderEphemeralPublicBytes);

      final dhMaterial = <int>[...dh1, ...dh2, ...dh3];

      if (payload.oneTimePreKeyId != null) {
        final otpkPrivBytes = prefs.getString('$_otpkPrefix${payload.oneTimePreKeyId}_priv');
        if (otpkPrivBytes != null) {
          final dh4 = await _dh(base64Decode(otpkPrivBytes), senderEphemeralPublicBytes);
          dhMaterial.addAll(dh4);
          // Delete used one-time pre-key
          await prefs.remove('$_otpkPrefix${payload.oneTimePreKeyId}_pub');
          await prefs.remove('$_otpkPrefix${payload.oneTimePreKeyId}_priv');
        }
      }

      sessionKey = await _deriveSessionKey(Uint8List.fromList(dhMaterial));
      await prefs.setString('$_sessionPrefix$senderUserId', _bytesToBase64(sessionKey));
    }

    // Decrypt AES-256-CBC
    final ciphertextBytes = base64Decode(payload.ciphertext);
    final nonceBytes = base64Decode(payload.nonce);
    final tagBytes = base64Decode(payload.tag);

    final secretKey = SecretKey(sessionKey);
    final secretBox = SecretBox(ciphertextBytes, nonce: nonceBytes, mac: Mac(tagBytes));

    final plaintextBytes = await _aesCbc.decrypt(secretBox, secretKey: secretKey);
    return utf8.decode(plaintextBytes);
  }

  /// Stores the sender's identity key so we can perform X3DH on the recipient side.
  Future<void> storeSenderIdentityKey(String senderUserId, String identityKeyPublicB64) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_sessionPrefix${senderUserId}_ik', identityKeyPublicB64);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Client-Side Media Pre-Encryption (Photos, Videos, Files)
  // ─────────────────────────────────────────────────────────────────────────

  /// Encrypts raw [fileBytes] using a randomly generated 256-bit symmetric media key.
  /// Returns a map containing encrypted bytes, nonce, MAC tag, and the base64-encoded media key.
  Future<Map<String, dynamic>> encryptFileBytes(Uint8List fileBytes) async {
    final mediaKeyBytes = _generateNonce(32);
    final nonce = _generateNonce(16);
    final secretKey = SecretKey(mediaKeyBytes);

    final secretBox = await _aesCbc.encrypt(
      fileBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    return {
      'encryptedBytes': Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]),
      'nonceB64': _bytesToBase64(nonce),
      'mediaKeyB64': _bytesToBase64(mediaKeyBytes),
    };
  }

  /// Decrypts raw [encryptedBytes] using [mediaKeyB64] and [nonceB64].
  Future<Uint8List> decryptFileBytes({
    required Uint8List encryptedBytes,
    required String mediaKeyB64,
    required String nonceB64,
  }) async {
    final mediaKeyBytes = base64Decode(mediaKeyB64);
    final nonceBytes = base64Decode(nonceB64);

    // MAC tag is the last 32 bytes (HMAC-SHA256)
    final macLength = 32;
    final cipherText = encryptedBytes.sublist(0, encryptedBytes.length - macLength);
    final macBytes = encryptedBytes.sublist(encryptedBytes.length - macLength);

    final secretKey = SecretKey(mediaKeyBytes);
    final secretBox = SecretBox(cipherText, nonce: nonceBytes, mac: Mac(macBytes));

    final decrypted = await _aesCbc.decrypt(secretBox, secretKey: secretKey);
    return Uint8List.fromList(decrypted);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<int>> _dh(List<int> privateKeyBytes, List<int> publicKeyBytes) async {
    final privateKey = SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519);
    final sharedSecret = await _x25519.sharedSecretKey(keyPair: privateKey, remotePublicKey: publicKey);
    return await sharedSecret.extractBytes();
  }

  Future<Uint8List> _deriveSessionKey(Uint8List inputKeyMaterial) async {
    const info = 'DOLSYX_E2EE_SESSION_V1';
    final salt = Uint8List(32); // zero salt
    final secretKey = SecretKey(inputKeyMaterial);
    final output = await _hkdf.deriveKey(
      secretKey: secretKey,
      nonce: salt,
      info: utf8.encode(info),
    );
    final bytes = await output.extractBytes();
    return Uint8List.fromList(bytes);
  }

  Future<List<int>> _hmacSign(List<int> data, List<int> key) async {
    final hmac = Hmac.sha256();
    final mac = await hmac.calculateMac(data, secretKey: SecretKey(key));
    return mac.bytes;
  }

  Uint8List _generateNonce(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Local Database / Cache AES-256 Encryption
  // ─────────────────────────────────────────────────────────────────────────

  /// Encrypts local cache string [plaintext] using a device-local derived AES-256 key.
  Future<String> encryptLocalString(String plaintext) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var localKeyB64 = prefs.getString('e2ee_local_storage_key');
      if (localKeyB64 == null) {
        final keyBytes = _generateNonce(32);
        localKeyB64 = _bytesToBase64(keyBytes);
        await prefs.setString('e2ee_local_storage_key', localKeyB64);
      }
      final keyBytes = base64Decode(localKeyB64);
      final nonce = _generateNonce(16);
      final secretBox = await _aesCbc.encrypt(
        utf8.encode(plaintext),
        secretKey: SecretKey(keyBytes),
        nonce: nonce,
      );
      final payload = {
        'cipher': _bytesToBase64(secretBox.cipherText),
        'nonce': _bytesToBase64(nonce),
        'tag': _bytesToBase64(secretBox.mac.bytes),
      };
      return jsonEncode(payload);
    } catch (_) {
      return plaintext;
    }
  }

  /// Decrypts local cache payload string [encryptedJson].
  Future<String> decryptLocalString(String encryptedJson) async {
    try {
      if (!encryptedJson.startsWith('{') || !encryptedJson.contains('cipher')) return encryptedJson;
      final prefs = await SharedPreferences.getInstance();
      final localKeyB64 = prefs.getString('e2ee_local_storage_key');
      if (localKeyB64 == null) return encryptedJson;
      final keyBytes = base64Decode(localKeyB64);

      final Map<String, dynamic> data = jsonDecode(encryptedJson);
      final cipherBytes = base64Decode(data['cipher']);
      final nonceBytes = base64Decode(data['nonce']);
      final tagBytes = base64Decode(data['tag']);

      final secretBox = SecretBox(cipherBytes, nonce: nonceBytes, mac: Mac(tagBytes));
      final decryptedBytes = await _aesCbc.decrypt(secretBox, secretKey: SecretKey(keyBytes));
      return utf8.decode(decryptedBytes);
    } catch (_) {
      return encryptedJson;
    }
  }

  String _bytesToBase64(List<int> bytes) => base64Encode(bytes);
}
