import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../models/status.dart';
import '../services/status_service.dart';
import '../services/socket_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../utils/e2ee/e2ee_media_cache.dart';
import '../utils/e2ee/crypto_service.dart';

class StatusViewScreen extends StatefulWidget {
  final List<UserStatusGroup> groups;
  final int initialGroupIndex;

  const StatusViewScreen({super.key, required this.groups, required this.initialGroupIndex});

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

  File? _decryptedImageFile;
  String _currentDisplayCaption = '';

  late String _currentUserId;
  late int _currentGroupIndex;

  UserStatusGroup get currentGroup => widget.groups[_currentGroupIndex];

  @override
  void initState() {
    super.initState();
    final currentUser = Provider.of<AuthProvider>(context, listen: false).user;
    _currentUserId = currentUser?['id'] ?? '';
    _currentGroupIndex = widget.initialGroupIndex;

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
    _decryptedImageFile = null;

    if (index >= currentGroup.statuses.length) {
      if (_currentGroupIndex < widget.groups.length - 1) {
        // Move to next group
        if (mounted) {
          setState(() {
            _currentGroupIndex++;
            _currentIndex = 0;
            _loadStatus(0);
          });
        }
      } else {
        if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
      }
      return;
    }

    final status = currentGroup.statuses[index];
    _currentDisplayCaption = status.caption;

    // Inspect if status.caption holds an E2EE envelope
    Map<String, dynamic>? e2eePayload;
    if (status.caption.startsWith('{') && status.caption.endsWith('}')) {
      try {
        final decoded = jsonDecode(status.caption);
        if (decoded is Map<String, dynamic> && (decoded['encryptedMedia'] == true || decoded['e2ee'] == true)) {
          e2eePayload = decoded;
          _currentDisplayCaption = decoded['caption']?.toString() ?? '';
        }
      } catch (_) {}
    }
    
    // View it!
    if (status.userId != _currentUserId && !status.isViewed) {
      _statusService.viewStatus(status.id);
    }

    if (status.mediaType == 'VIDEO') {
      if (e2eePayload != null && e2eePayload['encryptedMedia'] == true) {
        final mediaKey = e2eePayload['mediaKey']?.toString() ?? '';
        final nonce = e2eePayload['nonce']?.toString() ?? '';
        E2EEMediaCache.getOrDownloadDecryptedMedia(
          mediaUrl: status.mediaUrl,
          mediaKey: mediaKey,
          nonce: nonce,
          mediaType: 'VIDEO',
        ).then((file) {
          if (!mounted) return;
          if (file != null) {
            _videoController = VideoPlayerController.file(file)
              ..initialize().then((_) {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                    _videoController!.setLooping(false);
                    _videoController!.play();
                  });
                  _startVideoTimer();
                }
              }).catchError((error) {
                debugPrint('E2EE Status video error: $error');
                if (mounted) {
                  setState(() => _isLoading = false);
                  _startImageTimer();
                }
              });
          } else {
            final url = ApiService.getMediaUrl(status.mediaUrl);
            _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
              ..initialize().then((_) {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                    _videoController!.setLooping(false);
                    _videoController!.play();
                  });
                  _startVideoTimer();
                }
              }).catchError((_) {
                if (mounted) {
                  setState(() => _isLoading = false);
                  _startImageTimer();
                }
              });
          }
        });
      } else {
        final url = ApiService.getMediaUrl(status.mediaUrl);
        _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
          ..initialize().then((_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _videoController!.setLooping(false);
                _videoController!.play();
              });
              _startVideoTimer();
            }
          }).catchError((error) {
            debugPrint('Status video load error: $error');
            if (mounted) {
              setState(() => _isLoading = false);
              _startImageTimer();
            }
          });
      }
    } else if (status.mediaType == 'TEXT') {
      if (e2eePayload != null && e2eePayload['isTextStatus'] == true) {
        CryptoService.instance.decryptStatusText(status.caption).then((decrypted) {
          if (!mounted) return;
          setState(() {
            _currentDisplayCaption = decrypted;
            _isLoading = false;
          });
          _startImageTimer();
        }).catchError((_) {
          if (mounted) {
            setState(() => _isLoading = false);
            _startImageTimer();
          }
        });
      } else {
        setState(() => _isLoading = false);
        _startImageTimer();
      }
    } else {
      // IMAGE
      if (e2eePayload != null && e2eePayload['encryptedMedia'] == true) {
        final mediaKey = e2eePayload['mediaKey']?.toString() ?? '';
        final nonce = e2eePayload['nonce']?.toString() ?? '';
        E2EEMediaCache.getOrDownloadDecryptedMedia(
          mediaUrl: status.mediaUrl,
          mediaKey: mediaKey,
          nonce: nonce,
          mediaType: 'IMAGE',
        ).then((file) {
          if (!mounted) return;
          setState(() {
            _decryptedImageFile = file;
            _isLoading = false;
          });
          _startImageTimer();
        }).catchError((_) {
          if (mounted) {
            setState(() => _isLoading = false);
            _startImageTimer();
          }
        });
      } else {
        // Handled by CachedNetworkImage builder callbacks
      }
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
    if (_currentIndex < currentGroup.statuses.length - 1) {
      setState(() {
        _currentIndex++;
        _loadStatus(_currentIndex);
      });
    } else {
      _nextGroup();
    }
  }

  void _prevStatus() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _loadStatus(_currentIndex);
      });
    } else {
      _prevGroup();
    }
  }

  void _nextGroup() {
    if (_currentGroupIndex < widget.groups.length - 1) {
      setState(() {
        _currentGroupIndex++;
        _currentIndex = 0;
        _loadStatus(0);
      });
    } else {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
    }
  }

  void _prevGroup() {
    if (_currentGroupIndex > 0) {
      setState(() {
        _currentGroupIndex--;
        _currentIndex = 0;
        _loadStatus(0);
      });
    } else {
      setState(() {
        _currentIndex = 0;
        _loadStatus(0);
      });
    }
  }

  void _onTapDown(TapDownDetails details) {
    if (_showSeenBy || _isReplying) return;
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
    final total = currentGroup.statuses.length;
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

  Future<void> _sendReply(String content) async {
    if (content.trim().isEmpty) return;
    
    final status = currentGroup.statuses[_currentIndex];
    final recipientId = (currentGroup.user['id'] ?? currentGroup.user['_id'])?.toString();
    if (recipientId == null || recipientId.isEmpty) return;

    final replyText = content.trim();
    final captionText = _currentDisplayCaption;
    final statusSnippet = captionText.isNotEmpty 
        ? captionText 
        : (status.mediaType == 'IMAGE' ? '📷 Photo' : (status.mediaType == 'VIDEO' ? '🎥 Video' : 'Status'));
    
    final formattedMessage = 'Replying to status: "$statusSnippet"\n\n$replyText';

    setState(() {
      _isReplying = false;
      _replyController.clear();
      _isPaused = false;
    });
    _videoController?.play();

    final chat = await ChatService().createDirectChat(recipientId);
    if (chat != null && mounted) {
      final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
      socket?.emit('send_message', {
        'conversationId': chat.id,
        'content': formattedMessage,
        'replyToStatusId': status.id,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status reply sent!')));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send status reply')));
    }
  }

  void _showSeenByBottomSheet() {
    setState(() {
      _isPaused = true;
      _showSeenBy = true;
    });
    _videoController?.pause();

    final status = currentGroup.statuses[_currentIndex];
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
    if (currentGroup.statuses.isEmpty) return const Scaffold(backgroundColor: Colors.black);

    final status = currentGroup.statuses[_currentIndex];
    final user = currentGroup.user;
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
          onHorizontalDragEnd: (details) {
            if (_showSeenBy || _isReplying) return;
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity! > 0) {
                // Swipe right -> Previous user group
                _prevGroup();
              } else if (details.primaryVelocity! < 0) {
                // Swipe left -> Next user group
                _nextGroup();
              }
            }
          },
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
                _decryptedImageFile != null
                    ? Image.file(_decryptedImageFile!, fit: BoxFit.contain)
                    : CachedNetworkImage(
                        imageUrl: ApiService.getMediaUrl(status.mediaUrl),
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
                          return const Center(child: Icon(Icons.error, color: Colors.white, size: 50));
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
                  child: Text(_currentDisplayCaption, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
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
                            radius: 18,
                            backgroundColor: Colors.grey.shade800,
                            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                ? CachedNetworkImageProvider(ApiService.getMediaUrl(avatarUrl))
                                : null,
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? const Icon(Icons.person, color: Colors.white70, size: 20)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(
                                _formatStatusTime(status.createdAt),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (isMine)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                              onPressed: () async {
                                _videoController?.pause();
                                final success = await _statusService.deleteStatus(status.id);
                                if (success && mounted) {
                                  Navigator.pop(context);
                                } else if (mounted) {
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
              if (status.mediaType != 'TEXT' && _currentDisplayCaption.isNotEmpty && !_isReplying && !_showSeenBy)
                Positioned(
                  bottom: 80, left: 20, right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black54,
                    child: Text(_currentDisplayCaption, style: const TextStyle(color: Colors.white, fontSize: 18), textAlign: TextAlign.center),
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

  String _formatStatusTime(DateTime dt) {
    final now = DateTime.now();
    final localDt = dt.toLocal();
    final difference = now.difference(localDt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else {
      final isToday = localDt.year == now.year && localDt.month == now.month && localDt.day == now.day;
      final yesterday = now.subtract(const Duration(days: 1));
      final isYesterday = localDt.year == yesterday.year && localDt.month == yesterday.month && localDt.day == yesterday.day;

      final timeStr = DateFormat('h:mm a').format(localDt);
      if (isToday) {
        return 'Today, $timeStr';
      } else if (isYesterday) {
        return 'Yesterday, $timeStr';
      } else {
        return DateFormat('MMM d, h:mm a').format(localDt);
      }
    }
  }
}
