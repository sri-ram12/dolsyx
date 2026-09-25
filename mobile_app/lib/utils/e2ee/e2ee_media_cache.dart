import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../services/api_service.dart';
import 'crypto_service.dart';

/// Manages client-side decryption and disk caching for E2EE media blobs.
class E2EEMediaCache {
  static final Map<String, Future<File?>> _inFlight = {};

  /// Detects the correct container extension to prevent ExoPlayer format failures on Android.
  static String detectSafeExtension({
    required String mediaUrl,
    String? mediaType,
    List<int>? bytes,
  }) {
    final cleanUrl = mediaUrl.split('?').first.toLowerCase();
    
    // 1. Explicit message mediaType
    final normType = mediaType?.trim().toUpperCase() ?? '';
    if (normType == 'VIDEO') return 'mp4';
    if (normType == 'IMAGE') {
      if (cleanUrl.endsWith('.png')) return 'png';
      if (cleanUrl.endsWith('.webp')) return 'webp';
      if (cleanUrl.endsWith('.gif')) return 'gif';
      return 'jpg';
    }
    if (normType == 'AUDIO' || normType == 'VOICE') return 'm4a';

    // 2. Binary magic headers inspection
    if (bytes != null && bytes.length >= 12) {
      // MP4 / MOV: 'ftyp' at bytes 4..7
      if (bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
        return 'mp4';
      }
      // JPEG: 0xFF, 0xD8, 0xFF
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return 'jpg';
      }
      // PNG: 0x89, 0x50, 0x4E, 0x47
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return 'png';
      }
      // GIF: 'GIF8'
      if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
        return 'gif';
      }
      // WebP: 'RIFF' + 'WEBP'
      if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
          bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
        return 'webp';
      }
    }

    // 3. Known extension in media URL
    final urlExt = cleanUrl.contains('.') ? cleanUrl.split('.').last : '';
    if (['mp4', 'mov', 'mkv', 'webm', '3gp', 'm4v'].contains(urlExt)) return 'mp4';
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(urlExt)) return urlExt == 'jpeg' ? 'jpg' : urlExt;
    if (['mp3', 'm4a', 'aac', 'wav', 'ogg'].contains(urlExt)) return urlExt;
    if (['pdf', 'zip', 'doc', 'docx'].contains(urlExt)) return urlExt;

    // 4. Default fallback: if URL indicates video/image
    if (cleanUrl.contains('video') || cleanUrl.contains('.mp4')) return 'mp4';
    if (cleanUrl.contains('image') || cleanUrl.contains('.jpg')) return 'jpg';

    return (urlExt.isNotEmpty && urlExt.length <= 4 && urlExt != 'bin' && urlExt != 'enc') ? urlExt : 'bin';
  }

  /// Retrieves a decrypted local media file from cache, or downloads and decrypts it on-the-fly.
  static Future<File?> getOrDownloadDecryptedMedia({
    required String mediaUrl,
    required String? mediaKey,
    required String? nonce,
    String? mediaType,
  }) async {
    try {
      if (mediaUrl.isEmpty) return null;

      // If already an existing local file path (never instantiate File on remote URLs)
      if (!mediaUrl.startsWith('http://') &&
          !mediaUrl.startsWith('https://') &&
          !mediaUrl.startsWith('blob:') &&
          !mediaUrl.startsWith('/uploads/')) {
        try {
          final localFile = File(mediaUrl);
          if (localFile.existsSync()) {
            return localFile;
          }
        } catch (_) {}
      }

      final tempDir = await getTemporaryDirectory();
      final cacheKey = mediaUrl.hashCode.abs().toString();
      final safeExt = detectSafeExtension(mediaUrl: mediaUrl, mediaType: mediaType);
      final cachedFile = File('${tempDir.path}/e2ee_dec_$cacheKey.$safeExt');

      if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
        return cachedFile;
      }

      // Also check if previously cached under alternative extensions
      for (final altExt in ['mp4', 'jpg', 'png', 'bin', 'm4a', 'webm']) {
        final altFile = File('${tempDir.path}/e2ee_dec_$cacheKey.$altExt');
        if (await altFile.exists() && (await altFile.length()) > 0) {
          if (safeExt == 'mp4' && altExt != 'mp4') {
            // Re-alias to .mp4 so ExoPlayer can open it without error
            await altFile.copy(cachedFile.path);
            return cachedFile;
          }
          return altFile;
        }
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
          final response = await http.get(Uri.parse(resolvedUrl)).timeout(const Duration(seconds: 60));
          if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
            return null;
          }

          final decryptedBytes = await CryptoService.instance.decryptFileBytes(
            encryptedBytes: response.bodyBytes,
            mediaKeyB64: mediaKey,
            nonceB64: nonce,
          );

          // Verify extension with actual decrypted bytes
          final verifiedExt = detectSafeExtension(
            mediaUrl: mediaUrl, 
            mediaType: mediaType, 
            bytes: decryptedBytes,
          );
          final targetFile = (verifiedExt == safeExt) 
              ? cachedFile 
              : File('${tempDir.path}/e2ee_dec_$cacheKey.$verifiedExt');

          await targetFile.writeAsBytes(decryptedBytes, flush: true);
          return targetFile;
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
  static Future<File?> saveDecryptedMedia(
    String mediaUrl, 
    List<int> bytes, {
    String? mediaType,
  }) async {
    try {
      if (mediaUrl.isEmpty) return null;
      final tempDir = await getTemporaryDirectory();
      final cacheKey = mediaUrl.hashCode.abs().toString();
      final safeExt = detectSafeExtension(
        mediaUrl: mediaUrl, 
        mediaType: mediaType, 
        bytes: bytes,
      );
      final cachedFile = File('${tempDir.path}/e2ee_dec_$cacheKey.$safeExt');
      await cachedFile.writeAsBytes(bytes, flush: true);
      return cachedFile;
    } catch (e) {
      debugPrint('E2EEMediaCache save error: $e');
      return null;
    }
  }
}

