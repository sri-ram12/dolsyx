import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import '../screens/forward_message_screen.dart';
import '../services/api_service.dart';

class FullScreenImageView extends StatefulWidget {
  final String imageUrl;
  final bool isChatMedia;
  final String? senderName;
  final DateTime? timestamp;
  final Message? message;

  const FullScreenImageView({
    super.key,
    required this.imageUrl,
    this.isChatMedia = false,
    this.senderName,
    this.timestamp,
    this.message,
  });

  @override
  State<FullScreenImageView> createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<FullScreenImageView> {
  bool _isDownloading = false;

  Future<void> _saveToGallery(String url) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final ext = url.split('?').first.split('.').last.toLowerCase();
        final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
        final file = File('${tempDir.path}/DOLSYX_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
        await file.writeAsBytes(response.bodyBytes);

        bool hasAccess = await Gal.hasAccess();
        if (!hasAccess) {
          hasAccess = await Gal.requestAccess();
        }

        if (hasAccess) {
          await Gal.putImage(file.path, album: 'DOLSYX');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Image saved to Gallery (DOLSYX album)'),
                backgroundColor: Color(0xFF00A884),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission denied.')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to download image.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving to gallery: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _forwardMedia() {
    final msgToForward = widget.message ??
        Message(
          id: 'fwd_${DateTime.now().millisecondsSinceEpoch}',
          content: '',
          senderId: '',
          conversationId: '',
          mediaUrl: widget.imageUrl,
          mediaType: 'IMAGE',
          createdAt: widget.timestamp ?? DateTime.now(),
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardMessageScreen(messages: [msgToForward]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = ApiService.getMediaUrl(widget.imageUrl);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleSpacing: widget.isChatMedia ? 0 : NavigationToolbar.kMiddleSpacing,
        title: (widget.isChatMedia && (widget.senderName != null || widget.timestamp != null))
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.senderName ?? 'Media',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (widget.timestamp != null)
                    Text(
                      DateFormat('d MMM yyyy, h:mm a').format(widget.timestamp!.toLocal()),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              )
            : null,
        actions: [
          if (widget.isChatMedia) ...[
            IconButton(
              icon: const Icon(Icons.forward_rounded, color: Colors.white, size: 26),
              tooltip: 'Forward',
              onPressed: _forwardMedia,
            ),
            IconButton(
              icon: _isDownloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded, color: Colors.white, size: 26),
              tooltip: 'Save to Gallery',
              onPressed: () => _saveToGallery(resolvedUrl),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 5.0,
          child: CachedNetworkImage(
            imageUrl: resolvedUrl,
            fit: BoxFit.contain,
            progressIndicatorBuilder: (context, url, downloadProgress) => Center(
              child: CircularProgressIndicator(
                value: downloadProgress.progress,
                color: Colors.white,
              ),
            ),
            errorWidget: (context, url, error) => const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: Colors.grey, size: 80),
                SizedBox(height: 12),
                Text('Failed to load image', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
