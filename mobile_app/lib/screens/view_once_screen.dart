import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../utils/e2ee/e2ee_media_cache.dart';

class ViewOnceScreen extends StatefulWidget {
  final Message message;
  final Function(String) onViewed;

  const ViewOnceScreen({
    super.key,
    required this.message,
    required this.onViewed,
  });

  @override
  State<ViewOnceScreen> createState() => _ViewOnceScreenState();
}

class _ViewOnceScreenState extends State<ViewOnceScreen> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _isInit = false;
  bool _hasTriggeredViewed = false;
  File? _decryptedFile;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initMedia();
  }

  Future<void> _initMedia() async {
    final rawUrl = widget.message.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      if (widget.message.isE2EEMedia && widget.message.mediaKey != null) {
        final file = await E2EEMediaCache.getOrDownloadDecryptedMedia(
          mediaUrl: rawUrl,
          mediaKey: widget.message.mediaKey,
          nonce: widget.message.nonce,
          mediaType: widget.message.mediaType,
        );
        if (mounted) {
          _decryptedFile = file;
        }
      }

      if (widget.message.mediaType == 'VIDEO') {
        if (_decryptedFile != null) {
          File playableFile = _decryptedFile!;
          if (!playableFile.path.toLowerCase().endsWith('.mp4')) {
            final mp4File = File('${playableFile.path}.mp4');
            if (!mp4File.existsSync()) await playableFile.copy(mp4File.path);
            playableFile = mp4File;
          }
          _videoController = VideoPlayerController.file(playableFile);
        } else {
          final fullUrl = ApiService.getMediaUrl(rawUrl);
          _videoController = VideoPlayerController.networkUrl(Uri.parse(fullUrl));
        }

        await _videoController!.initialize();
        if (mounted) {
          setState(() {
            _isInit = true;
            _isLoading = false;
            _isPlaying = true;
          });
          _videoController!.play();
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('ViewOnce media error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _notifyViewed();
    _videoController?.dispose();
    super.dispose();
  }

  void _notifyViewed() {
    if (!_hasTriggeredViewed) {
      _hasTriggeredViewed = true;
      try {
        if (_decryptedFile != null && _decryptedFile!.existsSync()) {
          _decryptedFile!.deleteSync();
        }
      } catch (e) {
        debugPrint('Error wiping view once decrypted file: $e');
      }
      widget.onViewed(widget.message.id);
    }
  }

  void _close() {
    _notifyViewed();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final mediaUrl = widget.message.mediaUrl != null ? ApiService.getMediaUrl(widget.message.mediaUrl!) : '';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _notifyViewed();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _close,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.looks_one, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.message.mediaType == 'VIDEO' ? 'View Once Video' : 'View Once Photo',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
        body: Center(
          child: _isLoading
              ? CircularProgressIndicator(color: AppTheme.primaryColor)
              : _hasError
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: Colors.white70, size: 48),
                        SizedBox(height: 12),
                        Text('Failed to load media', style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : widget.message.mediaType == 'VIDEO'
                      ? (_isInit
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
                                          ? const Icon(Icons.play_circle_fill, size: 64, color: Colors.white70)
                                          : const SizedBox.expand(),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : CircularProgressIndicator(color: AppTheme.primaryColor))
                      : (_decryptedFile != null
                          ? Image.file(_decryptedFile!, fit: BoxFit.contain)
                          : CachedNetworkImage(
                              imageUrl: mediaUrl,
                              fit: BoxFit.contain,
                              placeholder: (context, url) => CircularProgressIndicator(color: AppTheme.primaryColor),
                              errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                            )),
        ),
      ),
    );
  }
}
