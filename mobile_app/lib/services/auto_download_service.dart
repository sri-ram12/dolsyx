import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import 'api_service.dart';

class AutoDownloadService {
  static final Set<String> _processedMessageIds = {};

  static Future<void> checkAndAutoDownload(Message message) async {
    try {
      if (message.mediaUrl == null || message.mediaUrl!.isEmpty) return;
      if (message.isViewOnce) return; // Never auto-download View-Once media
      if (_processedMessageIds.contains(message.id)) return;

      _processedMessageIds.add(message.id);

      final prefs = await SharedPreferences.getInstance();
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

      final resolvedUrl = ApiService.getMediaUrl(message.mediaUrl!);
      final response = await http.get(Uri.parse(resolvedUrl));
      if (response.statusCode != 200) return;

      final tempDir = await getTemporaryDirectory();
      final ext = resolvedUrl.split('?').first.split('.').last.toLowerCase();

      if (mediaType == 'IMAGE') {
        final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
        final file = File('${tempDir.path}/DOLSYX_${message.id}_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
        await file.writeAsBytes(response.bodyBytes);

        bool hasAccess = await Gal.hasAccess();
        if (!hasAccess) {
          hasAccess = await Gal.requestAccess();
        }
        if (hasAccess) {
          await Gal.putImage(file.path, album: 'DOLSYX');
          debugPrint('✅ Auto-downloaded image to Gallery: ${file.path}');
        }
      } else if (mediaType == 'VIDEO') {
        final safeExt = ['mp4', 'mov', 'mkv', 'webm', '3gp'].contains(ext) ? ext : 'mp4';
        final file = File('${tempDir.path}/DOLSYX_${message.id}_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
        await file.writeAsBytes(response.bodyBytes);

        bool hasAccess = await Gal.hasAccess();
        if (!hasAccess) {
          hasAccess = await Gal.requestAccess();
        }
        if (hasAccess) {
          await Gal.putVideo(file.path, album: 'DOLSYX');
          debugPrint('✅ Auto-downloaded video to Gallery: ${file.path}');
        }
      } else if (mediaType == 'DOCUMENT' || mediaType == 'AUDIO') {
        final docsDir = await getApplicationDocumentsDirectory();
        final file = File('${docsDir.path}/DOLSYX_${message.id}.$ext');
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('✅ Auto-downloaded document: ${file.path}');
      }
    } catch (e) {
      debugPrint('AutoDownloadService error: $e');
    }
  }
}
