import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.message.mediaType == 'VIDEO' && widget.message.mediaUrl != null) {
      final fullUrl = ApiService.getMediaUrl(widget.message.mediaUrl!);
      
      _videoController = VideoPlayerController.networkUrl(Uri.parse(fullUrl))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isInit = true;
            });
            _videoController!.play();
            _isPlaying = true;
          }
        });
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
          child: widget.message.mediaType == 'VIDEO'
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
              : CachedNetworkImage(
                  imageUrl: mediaUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => CircularProgressIndicator(color: AppTheme.primaryColor),
                  errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                ),
        ),
      ),
    );
  }
}
