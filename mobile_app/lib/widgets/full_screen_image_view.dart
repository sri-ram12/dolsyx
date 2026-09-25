import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../screens/forward_message_screen.dart';
import '../services/api_service.dart';
import '../utils/e2ee/e2ee_media_cache.dart';

class FullScreenImageView extends StatefulWidget {
  final String imageUrl;
  final bool isChatMedia;
  final String? senderName;
  final DateTime? timestamp;
  final Message? message;
  final Function(String messageId, bool forEveryone)? onDelete;

  const FullScreenImageView({
    super.key,
    required this.imageUrl,
    this.isChatMedia = false,
    this.senderName,
    this.timestamp,
    this.message,
    this.onDelete,
  });

  @override
  State<FullScreenImageView> createState() => _FullScreenImageViewState();
}

class _FullScreenImageViewState extends State<FullScreenImageView> {
  bool _isDownloading = false;
  bool _isSharing = false;
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  bool _isVideoInit = false;
  bool _isPlaying = false;
  bool _videoError = false;
  File? _decryptedFile;
  bool _isDecrypting = false;

  @override
  void initState() {
    super.initState();
    _initMedia();
  }

  Future<void> _initMedia() async {
    final rawUrl = widget.imageUrl;

    _isVideo = widget.message?.mediaType == 'VIDEO' ||
        rawUrl.toLowerCase().endsWith('.mp4') ||
        rawUrl.toLowerCase().endsWith('.mov') ||
        rawUrl.toLowerCase().endsWith('.mkv') ||
        rawUrl.toLowerCase().endsWith('.webm') ||
        rawUrl.contains('/video/');

    // 1. Direct local file playback (e.g. freshly captured camera / gallery video / pending send)
    final isLocal = (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://') && !rawUrl.startsWith('/uploads')) &&
        (rawUrl.startsWith('/data/') || rawUrl.startsWith('/storage/') || rawUrl.startsWith('file://'));

    if (isLocal) {
      try {
        final localPath = rawUrl.startsWith('file://') ? rawUrl.replaceFirst('file://', '') : rawUrl;
        final file = File(localPath);
        if (file.existsSync()) {
          if (_isVideo) {
            await _initVideoFromFile(file);
          } else {
            if (mounted) setState(() => _decryptedFile = file);
          }
          return;
        }
      } catch (_) {}
    }

    final resolvedUrl = ApiService.getMediaUrl(rawUrl);

    // 2. Client-side E2EE Decryption
    if (widget.message?.isE2EEMedia == true && widget.message?.mediaKey != null) {
      if (mounted) setState(() => _isDecrypting = true);
      try {
        final file = await E2EEMediaCache.getOrDownloadDecryptedMedia(
          mediaUrl: widget.imageUrl,
          mediaKey: widget.message!.mediaKey,
          nonce: widget.message!.nonce,
          mediaType: widget.message?.mediaType ?? (_isVideo ? 'VIDEO' : 'IMAGE'),
        );
        if (mounted) {
          setState(() {
            _decryptedFile = file;
            _isDecrypting = false;
          });
          if (file != null && _isVideo) {
            await _initVideoFromFile(file);
          } else if (file == null && _isVideo) {
            // Decryption failed or timed out — do not pass raw encrypted ciphertext to player
            setState(() {
              _isVideoInit = false;
              _videoError = true;
            });
          }
        }
      } catch (e) {
        debugPrint('Error decrypting media: $e');
        if (mounted) {
          setState(() {
            _isDecrypting = false;
            if (_isVideo) {
              _isVideoInit = false;
              _videoError = true;
            }
          });
        }
      }
    } else if (_isVideo) {
      await _initVideoFromUrl(resolvedUrl);
    }
  }

  Future<void> _initVideoFromFile(File file) async {
    try {
      File playableFile = file;
      final pathLower = file.path.toLowerCase();
      if (!pathLower.endsWith('.mp4') && 
          !pathLower.endsWith('.mov') && 
          !pathLower.endsWith('.mkv') &&
          !pathLower.endsWith('.webm')) {
        final mp4File = File('${file.path}.mp4');
        if (!mp4File.existsSync()) {
          await file.copy(mp4File.path);
        }
        playableFile = mp4File;
      }

      await _videoController?.dispose();
      _videoController = VideoPlayerController.file(playableFile);
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      if (mounted) {
        setState(() {
          _isVideoInit = true;
          _isPlaying = true;
          _videoError = false;
        });
        _videoController!.play();
      }
    } catch (e) {
      debugPrint('Video file playback error: $e');
      if (mounted) {
        setState(() {
          _isVideoInit = false;
          _videoError = true;
        });
      }
    }
  }

  Future<void> _initVideoFromUrl(String url) async {
    try {
      await _videoController?.dispose();
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      if (mounted) {
        setState(() {
          _isVideoInit = true;
          _isPlaying = true;
          _videoError = false;
        });
        _videoController!.play();
      }
    } catch (e) {
      debugPrint('Video network playback error: $e, downloading fallback...');
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final tempDir = await getTemporaryDirectory();
          final tempVideo = File('${tempDir.path}/stream_cache_${url.hashCode.abs()}.mp4');
          await tempVideo.writeAsBytes(response.bodyBytes, flush: true);
          await _initVideoFromFile(tempVideo);
          return;
        }
      } catch (dlErr) {
        debugPrint('Video fallback download error: $dlErr');
      }

      if (mounted) {
        setState(() {
          _isVideoInit = false;
          _videoError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _saveToGallery(String url) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final tempDir = await getTemporaryDirectory();
      final ext = url.split('?').first.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov'].contains(ext) ? ext : (_isVideo ? 'mp4' : 'jpg');
      final file = File('${tempDir.path}/DOLSYX_${DateTime.now().millisecondsSinceEpoch}.$safeExt');

      if (_decryptedFile != null && await _decryptedFile!.exists()) {
        await file.writeAsBytes(await _decryptedFile!.readAsBytes());
      } else {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to download media.')),
            );
          }
          return;
        }
      }

      bool hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
      }

      if (hasAccess) {
        if (_isVideo) {
          await Gal.putVideo(file.path, album: 'DOLSYX');
        } else {
          await Gal.putImage(file.path, album: 'DOLSYX');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isVideo ? '✅ Video saved to Gallery (DOLSYX)' : '✅ Image saved to Gallery (DOLSYX)'),
              backgroundColor: const Color(0xFF00A884),
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

  Future<void> _shareMedia(String url) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      if (_decryptedFile != null && await _decryptedFile!.exists()) {
        await Share.shareXFiles(
          [XFile(_decryptedFile!.path)],
          text: widget.message?.content.isNotEmpty == true ? widget.message!.content : 'Shared via DOLSYX',
        );
      } else {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final ext = url.split('?').first.split('.').last.toLowerCase();
          final safeExt = ['jpg', 'jpeg', 'png', 'webp', 'mp4'].contains(ext) ? ext : (_isVideo ? 'mp4' : 'jpg');
          final file = File('${tempDir.path}/DOLSYX_share_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
          await file.writeAsBytes(response.bodyBytes);

          await Share.shareXFiles(
            [XFile(file.path)],
            text: widget.message?.content.isNotEmpty == true ? widget.message!.content : 'Shared via DOLSYX',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share media: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
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
          mediaType: _isVideo ? 'VIDEO' : 'IMAGE',
          createdAt: widget.timestamp ?? DateTime.now(),
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardMessageScreen(messages: [msgToForward]),
      ),
    );
  }

  Future<void> _deleteMedia() async {
    final msg = widget.message;
    final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ??
        Provider.of<AuthProvider>(context, listen: false).user?['_id'];
    final isMe = msg != null && (msg.senderId == currentUserId || msg.sender?['id'] == currentUserId);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete media?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to delete this media item?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'for_me'),
            child: const Text('Delete for me', style: TextStyle(color: Colors.white)),
          ),
          if (isMe)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, 'for_everyone'),
              child: const Text('Delete for everyone', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );

    if (result != null) {
      final forEveryone = result == 'for_everyone';
      if (widget.onDelete != null && msg != null) {
        widget.onDelete!(msg.id, forEveryone);
      } else if (msg != null) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        auth.socketService.socket?.emit('delete_message', {
          'messageId': msg.id,
          'conversationId': msg.conversationId,
          'forEveryone': forEveryone,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑 Media deleted'),
            backgroundColor: Color(0xFF6366F1),
          ),
        );
        Navigator.pop(context, true);
      }
    }
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
            // 🗑️ Delete Bin Button (Top of media beside share/forward)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
              tooltip: 'Delete Media',
              onPressed: _deleteMedia,
            ),
            // 📤 Share Button
            IconButton(
              icon: _isSharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.share_rounded, color: Colors.white, size: 23),
              tooltip: 'Share',
              onPressed: () => _shareMedia(resolvedUrl),
            ),
            // ➡️ Forward Button
            IconButton(
              icon: const Icon(Icons.forward_rounded, color: Colors.white, size: 25),
              tooltip: 'Forward',
              onPressed: _forwardMedia,
            ),
            // ⬇️ Download / Save to Gallery Button
            IconButton(
              icon: _isDownloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded, color: Colors.white, size: 25),
              tooltip: 'Save to Gallery',
              onPressed: () => _saveToGallery(resolvedUrl),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: _isVideo
            ? (_isVideoInit
                ? AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(_videoController!),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_videoController!.value.isPlaying) {
                                _videoController!.pause();
                                _isPlaying = false;
                              } else {
                                _videoController!.play();
                                _isPlaying = true;
                              }
                            });
                          },
                          child: Container(
                            color: Colors.transparent,
                            child: !_isPlaying
                                ? Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.play_arrow_rounded, size: 56, color: Colors.white),
                                  )
                                : const SizedBox.expand(),
                          ),
                        ),
                      ],
                    ),
                  )
                : (_videoError
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.amber, size: 52),
                          const SizedBox(height: 12),
                          const Text('Unable to play video', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              setState(() {
                                _videoError = false;
                                _isVideoInit = false;
                              });
                              _initMedia();
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(color: Color(0xFF6366F1))))
            : InteractiveViewer(
                minScale: 1.0,
                maxScale: 5.0,
                child: _decryptedFile != null
                    ? Image.file(_decryptedFile!, fit: BoxFit.contain)
                    : (_isDecrypting
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : CachedNetworkImage(
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
                          )),
              ),
      ),
    );
  }
}
