import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VideoThumbnailData {
  final Uint8List? bytes;
  final String duration;

  const VideoThumbnailData({this.bytes, required this.duration});
}

class VideoThumbnailService {
  static const MethodChannel _channel = MethodChannel('com.dolsyx/video_thumbnail');
  static final Map<String, VideoThumbnailData> _cache = {};

  static Future<VideoThumbnailData> getThumbnail(String path, {int quality = 65}) async {
    if (_cache.containsKey(path)) {
      return _cache[path]!;
    }
    try {
      final res = await _channel.invokeMethod<Map>('getVideoThumbnail', {
        'path': path,
        'quality': quality,
      });
      if (res != null) {
        final bytes = res['bytes'] as Uint8List?;
        final duration = res['duration'] as String? ?? '0:00';
        final data = VideoThumbnailData(bytes: bytes, duration: duration);
        _cache[path] = data;
        return data;
      }
    } catch (_) {}
    const fallback = VideoThumbnailData(bytes: null, duration: '0:00');
    _cache[path] = fallback;
    return fallback;
  }

  static Future<String> getDuration(String path) async {
    if (_cache.containsKey(path)) {
      return _cache[path]!.duration;
    }
    try {
      final res = await _channel.invokeMethod<String>('getVideoDuration', {'path': path});
      if (res != null && res.isNotEmpty) {
        return res;
      }
    } catch (_) {}
    return '0:00';
  }

  static VideoThumbnailData? getCached(String path) => _cache[path];
}

class VideoThumbnailWidget extends StatefulWidget {
  final String videoPath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;

  const VideoThumbnailWidget({
    super.key,
    required this.videoPath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
  });

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _load();
    }
  }

  void _load() {
    final cached = VideoThumbnailService.getCached(widget.videoPath);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _bytes = cached.bytes;
          _loaded = true;
        });
      }
      return;
    }

    VideoThumbnailService.getThumbnail(widget.videoPath).then((data) {
      if (mounted) {
        setState(() {
          _bytes = data.bytes;
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => widget.placeholder ?? _buildFallback(),
      );
    }
    return widget.placeholder ?? _buildFallback();
  }

  Widget _buildFallback() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF1B2831),
      child: Center(
        child: _loaded
            ? const Icon(Icons.videocam_rounded, color: Colors.white54, size: 28)
            : const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A884)),
                ),
              ),
      ),
    );
  }
}

class VideoDurationWidget extends StatefulWidget {
  final String videoPath;
  final TextStyle? style;

  const VideoDurationWidget({
    super.key,
    required this.videoPath,
    this.style,
  });

  @override
  State<VideoDurationWidget> createState() => _VideoDurationWidgetState();
}

class _VideoDurationWidgetState extends State<VideoDurationWidget> {
  String _duration = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoDurationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _load();
    }
  }

  void _load() {
    final cached = VideoThumbnailService.getCached(widget.videoPath);
    if (cached != null) {
      setState(() => _duration = cached.duration);
      return;
    }
    VideoThumbnailService.getThumbnail(widget.videoPath).then((data) {
      if (mounted) {
        setState(() => _duration = data.duration);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _duration.isNotEmpty ? _duration : '0:00',
      style: widget.style ?? const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
    );
  }
}
