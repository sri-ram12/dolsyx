import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import 'api_service.dart';
import '../utils/e2ee/e2ee_media_cache.dart';

class AutoDownloadService {
  static final Set<String> _processedMessageIds = {};
  static Set<String>? _persistedSavedMediaKeys;

  static Future<void> checkAndAutoDownload(Message message, {String? currentUserId}) async {
    try {
      if (message.mediaUrl == null || message.mediaUrl!.isEmpty) return;
      if (message.isViewOnce) return; // Never auto-download View-Once media

      final prefs = await SharedPreferences.getInstance();

      // 1. Never auto-download media sent by the current user
      final myId = currentUserId ?? prefs.getString('current_user_id') ?? prefs.getString('user_id');
      if (myId != null && myId.isNotEmpty && message.senderId == myId) {
        return;
      }

      // 2. In-memory check for quick skip
      if (_processedMessageIds.contains(message.id)) return;
      _processedMessageIds.add(message.id);

      // 3. Persistent gallery check to completely prevent duplicates across restarts and re-fetching
      if (_persistedSavedMediaKeys == null) {
        final savedList = prefs.getStringList('saved_gallery_media_keys') ?? [];
        _persistedSavedMediaKeys = savedList.toSet();
      }

      final mediaKey = message.mediaUrl!.trim();
      if (_persistedSavedMediaKeys!.contains(message.id) || _persistedSavedMediaKeys!.contains(mediaKey)) {
        return; // Already downloaded into gallery, strictly avoid duplication
      }

      final bool autoPhotosWifi = prefs.getBool('auto_download_photos_wifi') ?? true;
      final bool autoVideosWifi = prefs.getBool('auto_download_videos_wifi') ?? true;
      final bool autoDocsWifi = prefs.getBool('auto_download_docs_wifi') ?? true;
      final bool autoCellular = prefs.getBool('auto_download_cellular') ?? false;

      // Check if auto-download is enabled for this media type
      bool shouldDownload = false;
      final mediaType = (message.mediaType ?? 'TEXT').toUpperCase();

      if (mediaType == 'IMAGE' && (autoPhotosWifi || autoCellular)) {
        shouldDownload = true;
      } else if (mediaType == 'VIDEO' && (autoVideosWifi || autoCellular)) {
        shouldDownload = true;
      } else if ((mediaType == 'DOCUMENT' || mediaType == 'AUDIO') && (autoDocsWifi || autoCellular)) {
        shouldDownload = true;
      }

      if (!shouldDownload) return;

      // WhatsApp-grade pre-caching & decryption pipeline
      File? mediaFile;
      if (message.isE2EEMedia && message.mediaKey != null && message.nonce != null) {
        mediaFile = await E2EEMediaCache.getOrDownloadDecryptedMedia(
          mediaUrl: message.mediaUrl!,
          mediaKey: message.mediaKey,
          nonce: message.nonce,
          mediaType: message.mediaType,
        );
      } else {
        final resolvedUrl = ApiService.getMediaUrl(message.mediaUrl!);
        final response = await http.get(Uri.parse(resolvedUrl)).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          mediaFile = await E2EEMediaCache.saveDecryptedMedia(
            message.mediaUrl!,
            response.bodyBytes,
            mediaType: message.mediaType,
          );
        }
      }

      if (mediaFile == null || !mediaFile.existsSync()) return;

      if (mediaType == 'IMAGE') {
        bool hasAccess = await Gal.hasAccess();
        if (!hasAccess) {
          hasAccess = await Gal.requestAccess();
        }
        if (hasAccess) {
          await Gal.putImage(mediaFile.path, album: 'DOLSYX');
          _persistedSavedMediaKeys!.add(message.id);
          _persistedSavedMediaKeys!.add(mediaKey);
          await prefs.setStringList('saved_gallery_media_keys', _persistedSavedMediaKeys!.toList());
          debugPrint('✅ Auto-downloaded decrypted image to Gallery: ${mediaFile.path}');
        }
      } else if (mediaType == 'VIDEO') {
        bool hasAccess = await Gal.hasAccess();
        if (!hasAccess) {
          hasAccess = await Gal.requestAccess();
        }
        if (hasAccess) {
          await Gal.putVideo(mediaFile.path, album: 'DOLSYX');
          _persistedSavedMediaKeys!.add(message.id);
          _persistedSavedMediaKeys!.add(mediaKey);
          await prefs.setStringList('saved_gallery_media_keys', _persistedSavedMediaKeys!.toList());
          debugPrint('✅ Auto-downloaded decrypted video to Gallery: ${mediaFile.path}');
        }
      } else if (mediaType == 'DOCUMENT' || mediaType == 'AUDIO') {
        _persistedSavedMediaKeys!.add(message.id);
        _persistedSavedMediaKeys!.add(mediaKey);
        await prefs.setStringList('saved_gallery_media_keys', _persistedSavedMediaKeys!.toList());
        debugPrint('✅ Auto-downloaded document: ${mediaFile.path}');
      }
    } catch (e) {
      debugPrint('AutoDownloadService error: $e');
    }
  }
}
