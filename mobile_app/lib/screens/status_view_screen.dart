import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/status.dart';
import '../services/status_service.dart';
import '../theme/app_theme.dart';

class StatusViewScreen extends StatefulWidget {
  final StatusModel status;

  const StatusViewScreen({super.key, required this.status});

  @override
  State<StatusViewScreen> createState() => _StatusViewScreenState();
}

class _StatusViewScreenState extends State<StatusViewScreen> {
  final StatusService _statusService = StatusService();
  double _progress = 0.0;
  bool _isPaused = false;
  bool _isLoading = true; // Add loading state

  @override
  void initState() {
    super.initState();
    _statusService.viewStatus(widget.status.id);
    _startTimer();
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return false;
      if (!_isPaused && !_isLoading) { // Pause while loading
        setState(() {
          _progress += 0.01;
        });
        if (_progress >= 1.0) {
          Navigator.pop(context);
          return false;
        }
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.status.user ?? {};
    final username = user['username'] ?? 'User';
    final avatarUrl = user['avatarUrl'];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPaused = true),
          onTapUp: (_) => setState(() => _isPaused = false),
          onTapCancel: () => setState(() => _isPaused = false),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media
              if (widget.status.mediaType == 'IMAGE')
                CachedNetworkImage(
                  imageUrl: widget.status.mediaUrl.startsWith('http')
                      ? widget.status.mediaUrl
                      : 'https://dolsyx-app.onrender.com${widget.status.mediaUrl}',
                  fit: BoxFit.contain,
                  progressIndicatorBuilder: (context, url, downloadProgress) {
                    // It's still loading
                    if (!_isLoading) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isLoading = true);
                      });
                    }
                    return Center(child: CircularProgressIndicator(color: AppTheme.primaryColor, value: downloadProgress.progress));
                  },
                  imageBuilder: (context, imageProvider) {
                    // Finished loading
                    if (_isLoading) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isLoading = false);
                      });
                    }
                    return Image(image: imageProvider, fit: BoxFit.contain);
                  },
                  errorWidget: (context, url, error) {
                    if (_isLoading) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isLoading = false);
                      });
                    }
                    return const Center(child: Icon(Icons.error, color: Colors.white, size: 50));
                  },
                )
              else
                const Center(child: Text('Video statuses not fully supported yet', style: TextStyle(color: Colors.white))),

              // Top Bar
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.grey,
                          backgroundImage: avatarUrl != null && avatarUrl.startsWith('http')
                              ? NetworkImage(avatarUrl)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          username,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Content text if any
              if (widget.status.content.isNotEmpty)
                Positioned(
                  bottom: 50,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black54,
                    child: Text(
                      widget.status.content,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
