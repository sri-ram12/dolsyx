import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

/// Helper utility for resolving, caching, and formatting media file sizes (KB/MB/GB).
class MediaSizeHelper {
  static final Map<String, int> _sizeCache = {};
  static final Set<String> _pendingResolutions = {};

  /// Formats byte count to clean WhatsApp-style string: e.g. "33 KB", "2.4 MB", "125 B".
  static String formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      final kb = (bytes / 1024).round();
      return '$kb KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return mb >= 10 ? '${mb.toStringAsFixed(0)} MB' : '${mb.toStringAsFixed(1)} MB';
    }
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }

  /// Synchronously gets cached size if available.
  static int? getCachedSize(String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) return null;
    return _sizeCache[mediaUrl];
  }

  /// Sets size in cache.
  static void cacheSize(String mediaUrl, int bytes) {
    if (bytes > 0) {
      _sizeCache[mediaUrl] = bytes;
    }
  }

  /// Asynchronously resolves the file size if not known.
  /// Checks local file length first, then performs a lightweight HTTP HEAD request.
  static Future<int?> resolveFileSize(String? mediaUrl, {VoidCallback? onResolved}) async {
    if (mediaUrl == null || mediaUrl.isEmpty) return null;

    if (_sizeCache.containsKey(mediaUrl)) {
      return _sizeCache[mediaUrl];
    }

    // 1. Check if it's a local file
    if (!mediaUrl.startsWith('http') && !mediaUrl.startsWith('/uploads')) {
      try {
        final f = File(mediaUrl);
        if (await f.exists()) {
          final len = await f.length();
          _sizeCache[mediaUrl] = len;
          onResolved?.call();
          return len;
        }
      } catch (_) {}
    }

    // 2. Perform lightweight HTTP HEAD check for Content-Length
    if (_pendingResolutions.contains(mediaUrl)) return null;
    _pendingResolutions.add(mediaUrl);

    try {
      final fullUrl = ApiService.getMediaUrl(mediaUrl);
      final uri = Uri.parse(fullUrl);
      final res = await http.head(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && res.contentLength != null && res.contentLength! > 0) {
        _sizeCache[mediaUrl] = res.contentLength!;
        onResolved?.call();
        return res.contentLength;
      }
    } catch (_) {
      // Ignore network errors on size probe
    } finally {
      _pendingResolutions.remove(mediaUrl);
    }

    return null;
  }
}
