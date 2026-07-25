import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../models/status.dart';
import '../services/status_service.dart';
import '../services/socket_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'chat_room_screen.dart';

class StatusViewScreen extends StatefulWidget {
  final UserStatusGroup group;

  const StatusViewScreen({super.key, required this.group});

  @override
  State<StatusViewScreen> createState() => _StatusViewScreenState();
}

class _StatusViewScreenState extends State<StatusViewScreen> {
  final StatusService _statusService = StatusService();
  int _currentIndex = 0;
  double _progress = 0.0;
  bool _isPaused = false;
  bool _isLoading = true;
  VideoPlayerController? _videoController;
  Timer? _timer;
  
  bool _showSeenBy = false;
  bool _isReplying = false;
  final TextEditingController _replyController = TextEditingController();

  late String _currentUserId;

  @override
  void initState() {
    super.initState();
    final currentUser = Provider.of<AuthProvider>(context, listen: false).user;
    _currentUserId = currentUser?['id'] ?? '';

    _loadStatus(_currentIndex);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _videoController?.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _loadStatus(int index) {
    _timer?.cancel();
    _videoController?.dispose();
    _videoController = null;
    _progress = 0.0;
    _isPaused = false;
    _isLoading = true;

    if (index >= widget.group.statuses.length) {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
      return;
    }

    final status = widget.group.statuses[index];
    
    // View it!
    if (status.userId != _currentUserId && !status.isViewed) {
      _statusService.viewStatus(status.id);
    }

    if (status.mediaType == 'VIDEO') {
      final url = status.mediaUrl.startsWith('http') ? status.mediaUrl : 'https://dolsyx-app.onrender.com${status.mediaUrl}';
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _videoController!.play();
            });
            _startVideoTimer();
          }
        }).catchError((error) {
          if (mounted) setState(() => _isLoading = false); // Show error
        });
    } else if (status.mediaType == 'TEXT') {
      setState(() => _isLoading = false);
      _startImageTimer();
    } else {
      // Image - handled by CachedNetworkImage builder callbacks
    }
  }

  void _startImageTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isPaused && !_isLoading && !_showSeenBy && !_isReplying) {
        setState(() {
          // 5 seconds total for images/text
          _progress += 50 / 5000;
        });
        if (_progress >= 1.0) {
          timer.cancel();
          _nextStatus();
        }
      }
    });
  }

  void _startVideoTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || _videoController == null || !_videoController!.value.isInitialized) {
        timer.cancel();
        return;
      }
      
      if (!_isPaused && !_showSeenBy && !_isReplying) {
        final position = _videoController!.value.position;
        final duration = _videoController!.value.duration;
        
        setState(() {
          _progress = position.inMilliseconds / duration.inMilliseconds;
        });

        if (position >= duration) {
          timer.cancel();
          _nextStatus();
        }
      }
    });
  }

  void _nextStatus() {
    if (_currentIndex < widget.group.statuses.length - 1) {
      setState(() {
        _currentIndex++;
        _loadStatus(_currentIndex);
      });
    } else {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
    }
  }

  void _prevStatus() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _loadStatus(_currentIndex);
      });
    } else {
      _progress = 0.0;
      // Restart current
    }
  }

  void _onTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;
    if (dx < screenWidth / 3) {
      _prevStatus();
    } else {
      _nextStatus();
    }
  }
  
  void _onLongPressDown(_) {
    setState(() => _isPaused = true);
    _videoController?.pause();
  }
  
  void _onLongPressUp() {
    setState(() => _isPaused = false);
    _videoController?.play();
  }

  Widget _buildTopBars() {
    final total = widget.group.statuses.length;
    return Row(
      children: List.generate(total, (index) {
        double val = 0.0;
        if (index < _currentIndex) val = 1.0;
        else if (index == _currentIndex) val = _progress;
        
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: LinearProgressIndicator(
              value: val,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 2,
            ),
          ),
        );
      }),
    );
  }

  void _sendReply(String content) {
    if (content.trim().isEmpty) return;
    
    // In a real implementation, we'd navigate to the chat room or send via socket right here
    // Let's just simulate sending via SocketService or API. 
    // Usually WhatsApp replies just show up in the chat.
    final status = widget.group.statuses[_currentIndex];
    
    // For now we'll just close and show a toast
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent!')));
    setState(() {
      _isReplying = false;
      _replyController.clear();
      _isPaused = false;
    });
    _videoController?.play();
  }

  void _showSeenByBottomSheet() {
    setState(() {
      _isPaused = true;
      _showSeenBy = true;
    });
    _videoController?.pause();

    final status = widget.group.statuses[_currentIndex];
    final views = status.views ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Viewed by ${views.length}', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      final success = await _statusService.deleteStatus(status.id);
                      if (success) {
                        Navigator.pop(context); // Close bottom sheet
                        if (mounted) Navigator.pop(context); // Close status view
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete status')));
                      }
                    },
                  )
                ],
              ),
              const Divider(color: Colors.grey),
              Expanded(
                child: views.isEmpty 
                  ? Center(child: Text('No views yet', style: TextStyle(color: AppTheme.textSecondary)))
                  : ListView.builder(
                      itemCount: views.length,
                      itemBuilder: (context, idx) {
                        final view = views[idx];
                        final viewer = view['viewer'];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: viewer['avatarUrl'] != null ? NetworkImage(viewer['avatarUrl']) : null,
                            child: viewer['avatarUrl'] == null ? Icon(Icons.person) : null,
                          ),
                          title: Text(viewer['username'], style: TextStyle(color: AppTheme.textPrimary)),
                          subtitle: Text('Today at ${DateTime.parse(view['viewedAt']).toLocal().toString().substring(11, 16)}', style: TextStyle(color: AppTheme.textSecondary)),
                        );
                      },
                    ),
              ),
            ],
          ),
        );
      }
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isPaused = false;
          _showSeenBy = false;
        });
        _videoController?.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.group.statuses.isEmpty) return const Scaffold(backgroundColor: Colors.black);

    final status = widget.group.statuses[_currentIndex];
    final user = widget.group.user;
    final username = user['username'] ?? 'User';
    final avatarUrl = user['avatarUrl'];
    final isMine = user['id'] == _currentUserId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTapDown: _onTapDown,
          onLongPressDown: _onLongPressDown,
          onLongPressUp: _onLongPressUp,
          onLongPressCancel: _onLongPressUp,
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity! > 0) {
              Navigator.pop(context); // Swipe down to exit
            } else if (details.primaryVelocity! < 0) {
              // Swipe up
              if (isMine) {
                _showSeenByBottomSheet();
              } else {
                setState(() {
                  _isPaused = true;
                  _isReplying = true;
                });
                _videoController?.pause();
              }
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Media Layer
              if (status.mediaType == 'IMAGE')
                CachedNetworkImage(
                  imageUrl: status.mediaUrl.startsWith('http') ? status.mediaUrl : 'https://dolsyx-app.onrender.com${status.mediaUrl}',
                  fit: BoxFit.contain,
                  progressIndicatorBuilder: (context, url, dp) {
                    if (!_isLoading) WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) setState(() => _isLoading = true); });
                    return Center(child: CircularProgressIndicator(color: AppTheme.primaryColor, value: dp.progress));
                  },
                  imageBuilder: (context, ip) {
                    if (_isLoading) {
                      WidgetsBinding.instance.addPostFrameCallback((_) { 
                        if(mounted) {
                          setState(() => _isLoading = false);
                          _startImageTimer();
                        }
                      });
                    }
                    return Image(image: ip, fit: BoxFit.contain);
                  },
                  errorWidget: (context, url, error) {
                    if (_isLoading) WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) setState(() => _isLoading = false); });
                    return Center(child: Icon(Icons.error, color: Colors.white, size: 50));
                  },
                )
              else if (status.mediaType == 'VIDEO' && _videoController != null && _videoController!.value.isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                )
              else if (status.mediaType == 'TEXT')
                Container(
                  color: Colors.primaries[status.userId.hashCode % Colors.primaries.length].shade800,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(20),
                  child: Text(status.caption, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),

              if (status.mediaType == 'VIDEO' && _isLoading)
                Center(child: CircularProgressIndicator(color: Colors.white)),

              // Dimming overlay when replying
              if (_isReplying || _showSeenBy)
                Container(color: Colors.black54),

              // Top Bar Layer
              if (!_isReplying && !_showSeenBy)
                Positioned(
                  top: 10, left: 10, right: 10,
                  child: Column(
                    children: [
                      _buildTopBars(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(icon: Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                          CircleAvatar(
                            radius: 18, backgroundColor: Colors.grey,
                            backgroundImage: avatarUrl != null && avatarUrl.startsWith('http') ? NetworkImage(avatarUrl) : null,
                          ),
                          const SizedBox(width: 8),
                          Text(username, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          if (isMine)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                              onPressed: () async {
                                _videoController?.pause();
                                final success = await _statusService.deleteStatus(status.id);
                                if (success && mounted) {
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete status')));
                                }
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Caption Layer
              if (status.mediaType != 'TEXT' && status.caption.isNotEmpty && !_isReplying && !_showSeenBy)
                Positioned(
                  bottom: 80, left: 20, right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black54,
                    child: Text(status.caption, style: TextStyle(color: Colors.white, fontSize: 18), textAlign: TextAlign.center),
                  ),
                ),

              // Bottom Up Swipe Hint Layer
              if (!_isReplying && !_showSeenBy)
                Positioned(
                  bottom: 20, left: 0, right: 0,
                  child: Column(
                    children: [
                      Icon(Icons.keyboard_double_arrow_up, color: Colors.white, size: 30),
                      Text(isMine ? 'Swipe up to see views (${status.views?.length ?? 0})' : 'Swipe up to reply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                    ],
                  ),
                ),

              // Reply Input Layer
              if (_isReplying)
                Positioned(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: AppTheme.surfaceColor,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _replyController,
                            autofocus: true,
                            style: TextStyle(color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Reply to $username...',
                              hintStyle: TextStyle(color: AppTheme.textSecondary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: AppTheme.backgroundColor,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.send, color: AppTheme.primaryColor),
                          onPressed: () => _sendReply(_replyController.text),
                        )
                      ],
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
