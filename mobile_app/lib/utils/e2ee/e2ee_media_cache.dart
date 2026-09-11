import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../services/api_service.dart';
import 'crypto_service.dart';

/// Manages client-side decryption and disk caching for E2EE media blobs.
class E2EEMediaCache {
  static final Map<String, Future<File?>> _inFlight = {};

  /// Retrieves a decrypted local media file from cache, or downloads and decrypts it on-the-fly.
  static Future<File?> getOrDownloadDecryptedMedia({
    required String mediaUrl,
    required String? mediaKey,
    required String? nonce,
  }) async {
    try {
      if (mediaUrl.isEmpty) return null;

      // If already a local file path
      if (!mediaUrl.startsWith('http') && !mediaUrl.startsWith('/uploads')) {
        final localFile = File(mediaUrl);
        if (await localFile.exists()) return localFile;
      }

      final tempDir = await getTemporaryDirectory();
      final cacheKey = mediaUrl.hashCode.abs().toString();
      final ext = mediaUrl.split('?').first.split('.').last.toLowerCase();
      final safeExt = (ext.isNotEmpty && ext.length <= 4) ? ext : 'bin';
      final cachedFile = File('${tempDir.path}/e2ee_dec_$cacheKey.$safeExt');

      if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
        return cachedFile;
      }

      // If keys are not provided, return null to fallback to standard network fetch
      if (mediaKey == null || nonce == null) {
        return null;
      }

      if (_inFlight.containsKey(mediaUrl)) {
        return await _inFlight[mediaUrl];
      }

      final future = () async {
        try {
          final resolvedUrl = ApiService.getMediaUrl(mediaUrl);
          final response = await http.get(Uri.parse(resolvedUrl)).timeout(const Duration(seconds: 20));
          if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
            return null;
          }

          final decryptedBytes = await CryptoService.instance.decryptFileBytes(
            encryptedBytes: response.bodyBytes,
            mediaKeyB64: mediaKey,
            nonceB64: nonce,
          );

          await cachedFile.writeAsBytes(decryptedBytes, flush: true);
          return cachedFile;
        } catch (e) {
          debugPrint('⚠️ Failed to download/decrypt E2EE media: $e');
          return null;
        } finally {
          _inFlight.remove(mediaUrl);
        }
      }();

      _inFlight[mediaUrl] = future;
      return await future;
    } catch (e) {
      debugPrint('E2EEMediaCache error: $e');
      return null;
    }
  }

  /// Pre-populates the cache with locally generated or decrypted media bytes.
  static Future<File?> saveDecryptedMedia(String mediaUrl, List<int> bytes) async {
    try {
      if (mediaUrl.isEmpty) return null;
      final tempDir = await getTemporaryDirectory();
      final cacheKey = mediaUrl.hashCode.abs().toString();
      final ext = mediaUrl.split('?').first.split('.').last.toLowerCase();
      final safeExt = (ext.isNotEmpty && ext.length <= 4) ? ext : 'bin';
      final cachedFile = File('${tempDir.path}/e2ee_dec_$cacheKey.$safeExt');
      await cachedFile.writeAsBytes(bytes, flush: true);
      return cachedFile;
    } catch (e) {
      debugPrint('E2EEMediaCache save error: $e');
      return null;
    }
  }
}
