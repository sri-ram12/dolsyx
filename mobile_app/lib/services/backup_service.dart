import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  final _aesCbc = AesCbc.with256bits(macAlgorithm: Hmac.sha256());

  /// Exports an encrypted local chat backup file (.dolsyx) using [passphrase].
  Future<File?> exportEncryptedBackup({
    required String passphrase,
    required List<dynamic> messages,
  }) async {
    try {
      final jsonStr = jsonEncode(messages);
      final rawBytes = utf8.encode(jsonStr);

      // Derive key from passphrase
      final keyBytes = await _deriveKeyFromPassphrase(passphrase);
      final secretKey = SecretKey(keyBytes);
      final nonce = Uint8List.fromList(List.generate(16, (i) => (i * 7 + 13) % 256));

      final secretBox = await _aesCbc.encrypt(
        rawBytes,
        secretKey: secretKey,
        nonce: nonce,
      );

      final encData = Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);

      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/DOLSYX_Backup_${DateTime.now().millisecondsSinceEpoch}.dolsyx');
      await file.writeAsBytes(encData);
      return file;
    } catch (e) {
      print('Backup export error: $e');
      return null;
    }
  }

  /// Restores chat messages from an encrypted [.dolsyx] file using [passphrase].
  Future<List<dynamic>?> importAndRestoreBackup({
    required File backupFile,
    required String passphrase,
  }) async {
    try {
      final encData = await backupFile.readAsBytes();
      final keyBytes = await _deriveKeyFromPassphrase(passphrase);
      final secretKey = SecretKey(keyBytes);
      final nonce = Uint8List.fromList(List.generate(16, (i) => (i * 7 + 13) % 256));

      const macLength = 32;
      final cipherText = encData.sublist(0, encData.length - macLength);
      final macBytes = encData.sublist(encData.length - macLength);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final decrypted = await _aesCbc.decrypt(secretBox, secretKey: secretKey);
      final jsonStr = utf8.decode(decrypted);

      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded;
    } catch (e) {
      print('Backup restore error: $e');
      return null;
    }
  }

  Future<Uint8List> _deriveKeyFromPassphrase(String passphrase) async {
    final bytes = utf8.encode(passphrase.padRight(32, '0'));
    final hash = await Sha256().hash(bytes);
    return Uint8List.fromList(hash.bytes);
  }
}
