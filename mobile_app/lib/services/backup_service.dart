import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_database_service.dart';
import 'api_service.dart';
import '../models/chat.dart';
import '../models/message.dart';

/// WhatsApp-grade End-to-End Encrypted Cloud & Local Chat Backup Engine (Phase 11)
/// Features AES-256-GCM authenticated cipher, PBKDF2-HMAC-SHA256 (100,000 iterations),
/// 64-digit encryption keys, and zero-knowledge cloud synchronization.
class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  final _aesGcm = AesGcm.with256bits();
  final _localDb = LocalDatabaseService();

  /// Generates a WhatsApp standard 64-digit encryption key
  /// Formatted into 16 groups of 4 hexadecimal characters: 'xxxx-xxxx-xxxx-...'
  String generate64DigitKey() {
    final random = Random.secure();
    const chars = '0123456789abcdef';
    final groups = <String>[];
    for (int i = 0; i < 16; i++) {
      String group = '';
      for (int j = 0; j < 4; j++) {
        group += chars[random.nextInt(chars.length)];
      }
      groups.add(group);
    }
    return groups.join('-');
  }

  /// Cleans and normalizes 64-digit keys or passwords for key derivation
  String _normalizeKey(String keyOrPass) {
    return keyOrPass.replaceAll('-', '').replaceAll(' ', '').trim();
  }

  /// Derives a 256-bit AES key using PBKDF2-HMAC-SHA256 with 100,000 iterations
  Future<SecretKey> _deriveKey({
    required String keyOrPass,
    required List<int> salt,
  }) async {
    final cleanInput = _normalizeKey(keyOrPass);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );

    return await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(cleanInput)),
      nonce: salt,
    );
  }

  /// Exports an end-to-end encrypted backup file and synchronizes with cloud
  Future<Map<String, dynamic>> createEncryptedBackup({
    required String keyOrPassword,
    bool is64DigitKey = false,
  }) async {
    try {
      debugPrint('[BackupEngine] Starting E2EE backup process...');
      final db = await _localDb.database;

      // 1. Export SQLite conversations and messages
      final convRows = await db.query('local_conversations');
      final msgRows = await db.query('local_messages');

      final backupPayload = {
        'version': 1,
        'app': 'DOLSYX',
        'createdAt': DateTime.now().toIso8601String(),
        'conversationsCount': convRows.length,
        'messagesCount': msgRows.length,
        'conversations': convRows,
        'messages': msgRows,
      };

      final rawBytes = utf8.encode(jsonEncode(backupPayload));

      // 2. Generate cryptographically secure 16-byte random salt and 12-byte nonce
      final random = Random.secure();
      final salt = List<int>.generate(16, (_) => random.nextInt(256));
      final nonce = List<int>.generate(12, (_) => random.nextInt(256));

      // 3. PBKDF2 Key Derivation
      final secretKey = await _deriveKey(keyOrPass: keyOrPassword, salt: salt);

      // 4. AES-256-GCM Authenticated Encryption
      final secretBox = await _aesGcm.encrypt(
        rawBytes,
        secretKey: secretKey,
        nonce: nonce,
      );

      final cipherTextWithMac = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);

      // 5. Save local backup file: DOLSYX_Backup_<timestamp>.dolsyx
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final localBackupFile = File('${appDir.path}/DOLSYX_Backup_$timestamp.dolsyx');

      // File format: [MAGIC(16B)][SALT(16B)][NONCE(12B)][CIPHERTEXT+MAC]
      final fileData = BytesBuilder();
      fileData.add(utf8.encode('DOLSYX_BACKUP_V1')); // 16 bytes
      fileData.add(salt); // 16 bytes
      fileData.add(nonce); // 12 bytes
      fileData.add(cipherTextWithMac);

      await localBackupFile.writeAsBytes(fileData.toBytes(), flush: true);
      final backupSizeBytes = await localBackupFile.length();

      // 6. Zero-Knowledge Cloud Backup Sync via Backend API
      bool cloudSynced = false;
      try {
        final token = await ApiService().getToken();
        if (token != null && token.isNotEmpty) {
          final res = await ApiService.client.post(
            Uri.parse('${ApiService.baseUrl}/backups/save'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'encryptedData': base64Encode(cipherTextWithMac),
              'salt': base64Encode(salt),
              'nonce': base64Encode(nonce),
            }),
          );
          if (res.statusCode >= 200 && res.statusCode < 300) {
            cloudSynced = true;
            debugPrint('[BackupEngine] Cloud backup synced successfully.');
          }
        }
      } catch (e) {
        debugPrint('[BackupEngine] Cloud sync skipped/failed: $e');
      }

      // 7. Store metadata in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_backup_time', DateTime.now().toIso8601String());
      await prefs.setInt('last_backup_size', backupSizeBytes);
      await prefs.setInt('last_backup_messages', msgRows.length);
      await prefs.setBool('backup_e2ee_enabled', true);
      await prefs.setBool('backup_is_64_digit', is64DigitKey);
      await prefs.setString('last_backup_path', localBackupFile.path);

      debugPrint('[BackupEngine] Backup completed: $backupSizeBytes bytes, ${msgRows.length} messages.');

      return {
        'success': true,
        'sizeBytes': backupSizeBytes,
        'messagesCount': msgRows.length,
        'conversationsCount': convRows.length,
        'filePath': localBackupFile.path,
        'cloudSynced': cloudSynced,
      };
    } catch (e) {
      debugPrint('[BackupEngine] Backup error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Decrypts and restores chats from a local file or cloud backup
  Future<Map<String, dynamic>> restoreEncryptedBackup({
    required String keyOrPassword,
    File? backupFile,
  }) async {
    try {
      debugPrint('[BackupEngine] Starting E2EE restore process...');
      List<int> salt;
      List<int> nonce;
      List<int> cipherTextWithMac;

      if (backupFile != null && await backupFile.exists()) {
        // Read from local file
        final bytes = await backupFile.readAsBytes();
        if (bytes.length < 44) {
          return {'success': false, 'error': 'Invalid backup file format.'};
        }

        // Parse header
        // bytes 0..15: 'DOLSYX_BACKUP_V1'
        salt = bytes.sublist(16, 32);
        nonce = bytes.sublist(32, 44);
        cipherTextWithMac = bytes.sublist(44);
      } else {
        // Fetch from Cloud Backend
        final token = await ApiService().getToken();
        if (token == null || token.isEmpty) {
          return {'success': false, 'error': 'Not logged in to download cloud backup.'};
        }

        final res = await ApiService.client.get(
          Uri.parse('${ApiService.baseUrl}/backups/load'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (res.statusCode != 200) {
          return {'success': false, 'error': 'No cloud backup found on server.'};
        }

        final body = jsonDecode(res.body);
        final data = body['data'];
        if (data == null) {
          return {'success': false, 'error': 'Cloud backup data is empty.'};
        }

        cipherTextWithMac = base64Decode(data['encryptedData']);
        salt = base64Decode(data['salt']);
        nonce = base64Decode(data['nonce']);
      }

      // Extract AES-GCM MAC (last 16 bytes)
      const macLength = 16;
      if (cipherTextWithMac.length <= macLength) {
        return {'success': false, 'error': 'Corrupt backup ciphertext payload.'};
      }

      final cipherText = cipherTextWithMac.sublist(0, cipherTextWithMac.length - macLength);
      final macBytes = cipherTextWithMac.sublist(cipherTextWithMac.length - macLength);

      // Derive key
      final secretKey = await _deriveKey(keyOrPass: keyOrPassword, salt: salt);

      // Decrypt and Authenticate via AES-256-GCM
      List<int> decryptedBytes;
      try {
        decryptedBytes = await _aesGcm.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
          secretKey: secretKey,
        );
      } catch (authError) {
        debugPrint('[BackupEngine] AES-GCM Auth verification failed: $authError');
        return {
          'success': false,
          'error': 'Incorrect password or 64-digit key. Decryption failed.',
          'isAuthFailure': true,
        };
      }

      final jsonStr = utf8.decode(decryptedBytes);
      final Map<String, dynamic> payload = jsonDecode(jsonStr);

      final List<dynamic> conversations = payload['conversations'] ?? [];
      final List<dynamic> messages = payload['messages'] ?? [];

      debugPrint('[BackupEngine] Ingesting ${conversations.length} chats and ${messages.length} messages into SQLite...');

      // Save into Local SQLite Database
      final chatList = conversations.map((c) => Chat.fromJson(Map<String, dynamic>.from(c))).toList();
      final msgList = messages.map((m) => Message.fromJson(Map<String, dynamic>.from(m))).toList();

      if (chatList.isNotEmpty) {
        await _localDb.saveConversations(chatList);
      }
      if (msgList.isNotEmpty) {
        await _localDb.saveMessages(msgList);
      }

      // Vacuum SQLite database and update indices
      await _localDb.reclaimStorageVacuum();

      return {
        'success': true,
        'conversationsRestored': chatList.length,
        'messagesRestored': msgList.length,
      };
    } catch (e) {
      debugPrint('[BackupEngine] Restore error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Returns current backup status and metadata
  Future<Map<String, dynamic>> getBackupStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastTimeStr = prefs.getString('last_backup_time');
    final lastSize = prefs.getInt('last_backup_size') ?? 0;
    final lastMessages = prefs.getInt('last_backup_messages') ?? 0;
    final isE2EE = prefs.getBool('backup_e2ee_enabled') ?? false;
    final is64Digit = prefs.getBool('backup_is_64_digit') ?? false;
    final lastPath = prefs.getString('last_backup_path');

    bool hasLocalFile = false;
    if (lastPath != null && lastPath.isNotEmpty) {
      hasLocalFile = File(lastPath).existsSync();
    }

    return {
      'lastBackupTime': lastTimeStr != null ? DateTime.tryParse(lastTimeStr) : null,
      'lastSizeBytes': lastSize,
      'lastMessagesCount': lastMessages,
      'isE2EEEnabled': isE2EE,
      'is64DigitKey': is64Digit,
      'hasLocalBackup': hasLocalFile,
      'localBackupPath': lastPath,
    };
  }

  /// Backward-compatible alias for local export
  Future<File?> exportEncryptedBackup({
    required String passphrase,
    required List<dynamic> messages,
  }) async {
    final res = await createEncryptedBackup(keyOrPassword: passphrase);
    if (res['success'] == true && res['filePath'] != null) {
      return File(res['filePath']);
    }
    return null;
  }

  /// Backward-compatible alias for local restore
  Future<List<dynamic>?> importAndRestoreBackup({
    required File backupFile,
    required String passphrase,
  }) async {
    final res = await restoreEncryptedBackup(keyOrPassword: passphrase, backupFile: backupFile);
    if (res['success'] == true) {
      return [];
    }
    return null;
  }
}

