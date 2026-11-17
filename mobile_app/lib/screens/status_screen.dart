import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/status.dart';
import '../services/status_service.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/chat_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../utils/e2ee/crypto_service.dart';
import '../utils/e2ee/e2ee_media_cache.dart';
import 'package:path_provider/path_provider.dart';
import 'status_view_screen.dart';
import 'status_privacy_screen.dart';
import 'video_trimmer_screen.dart';
import '../services/event_bus.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final StatusService _statusService = StatusService();
  List<UserStatusGroup> _groups = [];
  bool _isLoading = true;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _eventBusStatusSub;
  bool _showMuted = false;
  bool _isPaused_emoji = false;
  // Emoji reactions shortcut bar
  static const List<String> _quickEmoji = ['❤️', '😂', '😮', '😢', '🙏', '👍'];

  @override
  void initState() {
    super.initState();
    _fetchStatuses();

    // 0ms instant optimistic cross-screen bus subscription
    _eventBusStatusSub = AppEventBus().onStatusUpdated.listen((statusId) {
      if (!mounted) return;
      if (statusId != null && statusId.isNotEmpty) {
        _handleStatusDeleted({'statusId': statusId});
      } else {
        _fetchStatuses();
      }
    });

    final socketService = Provider.of<AuthProvider>(context, listen: false).socketService;
    _statusSubscription = socketService.onStatusStream.listen((event) {
      if (!mounted) return;
      final type = event['type'] as String?;
      final data = event['data'];
      switch (type) {
        case 'new_status':
          _handleNewStatus(data);
          break;
        case 'status_viewed':
          _handleStatusViewed(data);
          break;
        case 'status_deleted':
          _handleStatusDeleted(data);
          break;
        default:
          _fetchStatuses();
      }
    });
  }

  // ─── Granular in-memory socket handlers ────────────────────────────────────

  void _handleNewStatus(dynamic data) {
    // A contact posted a new status — refresh fully to get proper ordering
    _fetchStatuses();
  }

  void _handleStatusViewed(dynamic data) {
    if (data == null || data is! Map) return;
    final statusId = data['statusId']?.toString();
    final viewerId = data['viewerId']?.toString();
    if (statusId == null || viewerId == null) return;

    setState(() {
      _groups = _groups.map((group) {
        final updatedStatuses = group.statuses.map((s) {
          if (s.id != statusId) return s;
          final currentViews = List<dynamic>.from(s.views ?? []);
          final alreadyRecorded = currentViews.any((v) => v['viewerId'] == viewerId);
          if (!alreadyRecorded) {
            currentViews.add({'viewerId': viewerId, 'viewedAt': DateTime.now().toIso8601String(), 'viewer': {'id': viewerId, 'username': '...', 'avatarUrl': null, 'readReceipts': true}});
          }
          return s.copyWith(views: currentViews);
        }).toList();
        return group.copyWith(statuses: updatedStatuses);
      }).toList();
    });
  }

  void _handleStatusDeleted(dynamic data) {
    if (data == null || data is! Map) return;
    final statusId = data['statusId']?.toString();
    if (statusId == null) return;

    setState(() {
      _groups = _groups.map((group) {
        final updatedStatuses = group.statuses.where((s) => s.id != statusId).toList();
        if (updatedStatuses.isEmpty) return null;
        final stillHasUnread = updatedStatuses.any((s) => !s.isViewed && s.userId != (Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? ''));
        return group.copyWith(statuses: updatedStatuses, hasUnread: stillHasUnread);
      }).whereType<UserStatusGroup>().toList();
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _eventBusStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchStatuses() async {
    final groups = await _statusService.getStatuses();
    if (mounted) {
      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    }
  }

  Future<void> _addStatus(String type) async {
    if (type == 'TEXT') {
      // Show dialog to add text status
      _showTextStatusDialog();
      return;
    }

    try {
      final picker = ImagePicker();
      final pickedFile = type == 'IMAGE' 
          ? await picker.pickImage(source: ImageSource.gallery, imageQuality: 70)
          : await picker.pickVideo(source: ImageSource.gallery);
      
      if (pickedFile != null) {
        String mediaPath = pickedFile.path;
        
        if (type == 'VIDEO') {
          final trimmedPath = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoTrimmerScreen(file: File(pickedFile.path)),
            ),
          );
          if (trimmedPath == null) return; // User cancelled trimming
          mediaPath = trimmedPath;
        }

        setState(() => _isLoading = true);
        
        // 100% E2EE Media Pre-encryption
        final file = File(mediaPath);
        final rawBytes = await file.readAsBytes();
        final encResult = await CryptoService.instance.encryptFileBytes(rawBytes);
        final tempDir = await getTemporaryDirectory();
        final encFile = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_status.enc');
        await encFile.writeAsBytes(encResult['encryptedBytes'] as Uint8List);

        final uploadResponse = await _statusService.uploadStatusMedia(encFile.path);
        encFile.delete().catchError((_) => encFile);
        
        if (uploadResponse != null && uploadResponse['fileUrl'] != null) {
          final serverFileUrl = uploadResponse['fileUrl'] as String;
          // Cache decrypted media locally for 0ms instant playback for creator
          await E2EEMediaCache.saveDecryptedMedia(serverFileUrl, rawBytes, mediaType: type);

          final payload = jsonEncode({
            'e2ee': true,
            'encryptedMedia': true,
            'mediaUrl': serverFileUrl,
            'mediaKey': encResult['mediaKeyB64'],
            'nonce': encResult['nonceB64'],
            'mediaType': type,
            'caption': '',
          });

          final success = await _statusService.createStatus(
            serverFileUrl, 
            type, 
            payload
          );
          if (success) {
            _fetchStatuses();
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to post status')));
              setState(() => _isLoading = false);
            }
          }
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      print('Error adding status: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showTextStatusDialog() {
    final TextEditingController controller = TextEditingController();
    String selectedBgColor = '#075E54';
    final List<String> bgColors = [
      '#075E54',
      '#6200EE',
      '#1A237E',
      '#880E4F',
      '#004D40',
      '#212121',
      '#4A148C',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colorValue = Color(int.parse(selectedBgColor.replaceFirst('#', '0xFF')));
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: colorValue,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Type Status',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.palette_outlined, color: Colors.white, size: 28),
                        onPressed: () {
                          setModalState(() {
                            final currentIndex = bgColors.indexOf(selectedBgColor);
                            selectedBgColor = bgColors[(currentIndex + 1) % bgColors.length];
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: bgColors.map((hex) {
                        final c = Color(int.parse(hex.replaceFirst('#', '0xFF')));
                        final isSelected = hex == selectedBgColor;
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedBgColor = hex),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: isSelected ? 3 : 0,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 5,
                    minLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      hintText: 'Type a status...',
                      hintStyle: TextStyle(color: Colors.white60, fontSize: 24),
                      border: InputBorder.none,
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: FloatingActionButton(
                      backgroundColor: Colors.white,
                      child: Icon(Icons.send, color: colorValue),
                      onPressed: () async {
                        final text = controller.text.trim();
                        if (text.isNotEmpty) {
                          Navigator.pop(context);
                          setState(() => _isLoading = true);
                          // 100% E2EE Text Status Encryption
                          final encResult = await CryptoService.instance.encryptStatusText(text);
                          final payload = jsonEncode(encResult);

                          final success = await _statusService.createStatus(
                            '',
                            'TEXT',
                            payload,
                            bgColor: selectedBgColor,
                          );
                          if (success) {
                            _fetchStatuses();
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Failed to post status')),
                              );
                              setState(() => _isLoading = false);
                            }
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isUserMatch(Map<String, dynamic>? userMap, String? targetId) {
    if (userMap == null || targetId == null || targetId.isEmpty) return false;
    final uid = (userMap['id'] ?? userMap['_id'])?.toString();
    return uid != null && uid == targetId;
  }

  void _viewStatus(UserStatusGroup group) {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).user;
    final currentUserId = (currentUser?['id'] ?? currentUser?['_id'])?.toString();
    
    UserStatusGroup? myGroup;
    List<UserStatusGroup> recentUpdates = [];
    List<UserStatusGroup> viewedUpdates = [];
    List<UserStatusGroup> mutedUpdates = [];

    for (var g in _groups) {
      if (_isUserMatch(g.user, currentUserId)) {
        myGroup = g;
      } else if (g.isMuted) {
        mutedUpdates.add(g);
      } else if (g.hasUnread) {
        recentUpdates.add(g);
      } else {
        viewedUpdates.add(g);
      }
    }
    
    List<UserStatusGroup> allViewableGroups = [];
    if (myGroup != null && myGroup.statuses.isNotEmpty) allViewableGroups.add(myGroup);
    allViewableGroups.addAll(recentUpdates);
    allViewableGroups.addAll(viewedUpdates);
    allViewableGroups.addAll(mutedUpdates);
    
    final targetGroupId = (group.user['id'] ?? group.user['_id'])?.toString();
    int initialIndex = allViewableGroups.indexWhere((g) => (g.user['id'] ?? g.user['_id'])?.toString() == targetGroupId);
    if (initialIndex == -1) {
      allViewableGroups = [group];
      initialIndex = 0;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatusViewScreen(
          groups: allViewableGroups,
          initialGroupIndex: initialIndex,
        ),
      ),
    ).then((_) => _fetchStatuses());
  }

  void _toggleMute(UserStatusGroup group) async {
    final isMuted = group.isMuted;
    final contactId = (group.user['id'] ?? group.user['_id'])?.toString() ?? '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(isMuted ? 'Unmute ${group.user['username']}?' : 'Mute ${group.user['username']}?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          isMuted ? 'New status updates from ${group.user['username']} will appear under recent updates.' 
                  : 'New status updates from ${group.user['username']} won\'t appear under recent updates anymore.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              bool success = isMuted ? await _statusService.unmuteStatus(contactId) : await _statusService.muteStatus(contactId);
              if (success) _fetchStatuses();
              else setState(() => _isLoading = false);
            },
            child: Text(isMuted ? 'Unmute' : 'Mute'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<AuthProvider>(context).user;
    final currentUserId = (currentUser?['id'] ?? currentUser?['_id'])?.toString();

    UserStatusGroup? myGroup;
    List<UserStatusGroup> recentUpdates = [];
    List<UserStatusGroup> viewedUpdates = [];
    List<UserStatusGroup> mutedUpdates = [];

    for (var group in _groups) {
      if (_isUserMatch(group.user, currentUserId)) {
        myGroup = group;
      } else if (group.isMuted) {
        mutedUpdates.add(group);
      } else if (group.hasUnread) {
        recentUpdates.add(group);
      } else {
        viewedUpdates.add(group);
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "textFAB",
            mini: true,
            backgroundColor: AppTheme.surfaceColor,
            child: Icon(Icons.edit, color: AppTheme.primaryColor),
            onPressed: () => _addStatus('TEXT'),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "cameraFAB",
            backgroundColor: AppTheme.primaryColor,
            child: Icon(Icons.camera_alt, color: Colors.white),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: AppTheme.surfaceColor,
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(Icons.image, color: AppTheme.primaryColor),
                      title: Text('Photo', style: TextStyle(color: AppTheme.textPrimary)),
                      onTap: () { Navigator.pop(context); _addStatus('IMAGE'); },
                    ),
                    ListTile(
                      leading: Icon(Icons.videocam, color: AppTheme.primaryColor),
                      title: Text('Video', style: TextStyle(color: AppTheme.textPrimary)),
                      onTap: () { Navigator.pop(context); _addStatus('VIDEO'); },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading && _groups.isEmpty && myGroup == null
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                  ListTile(
                    onTap: () {
                      if (myGroup != null && myGroup!.statuses.isNotEmpty) {
                        _viewStatus(myGroup!);
                      } else {
                        // Let user pick a status if none exists
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: AppTheme.surfaceColor,
                          builder: (context) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: Icon(Icons.image, color: AppTheme.primaryColor),
                                title: Text('Photo', style: TextStyle(color: AppTheme.textPrimary)),
                                onTap: () { Navigator.pop(context); _addStatus('IMAGE'); },
                              ),
                              ListTile(
                                leading: Icon(Icons.videocam, color: AppTheme.primaryColor),
                                title: Text('Video', style: TextStyle(color: AppTheme.textPrimary)),
                                onTap: () { Navigator.pop(context); _addStatus('VIDEO'); },
                              ),
                              ListTile(
                                leading: Icon(Icons.text_fields, color: AppTheme.primaryColor),
                                title: Text('Text', style: TextStyle(color: AppTheme.textPrimary)),
                                onTap: () { Navigator.pop(context); _addStatus('TEXT'); },
                              ),
                            ],
                          ),
                        );
                      }
                    },
                    leading: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: (myGroup != null && myGroup!.statuses.isNotEmpty) ? Colors.green : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 26,
                            backgroundColor: AppTheme.surfaceColor,
                            backgroundImage: (currentUser != null && currentUser['avatarUrl'] != null && currentUser['avatarUrl'].toString().isNotEmpty)
                                ? CachedNetworkImageProvider(ApiService.getMediaUrl(currentUser['avatarUrl']))
                                : null,
                            child: (currentUser == null || currentUser['avatarUrl'] == null || currentUser['avatarUrl'].toString().isEmpty)
                                ? Icon(Icons.person, color: AppTheme.textSecondary)
                                : null,
                          ),
                        ),
                        if (myGroup == null || myGroup!.statuses.isEmpty)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
                              child: Icon(Icons.add, size: 14, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    title: Text('My Status', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      (myGroup == null || myGroup.statuses.isEmpty) ? 'Tap to add status update' : _formatTime(myGroup.statuses.last.createdAt),
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    trailing: (myGroup != null && myGroup.statuses.isNotEmpty) ? IconButton(
                      icon: Icon(Icons.add, color: AppTheme.primaryColor),
                      onPressed: () {
                        // Show bottom sheet to pick type
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: AppTheme.surfaceColor,
                          builder: (context) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: Icon(Icons.text_fields, color: AppTheme.primaryColor),
                                title: Text('Text', style: TextStyle(color: AppTheme.textPrimary)),
                                onTap: () { Navigator.pop(context); _addStatus('TEXT'); },
                              ),
                              ListTile(
                                leading: Icon(Icons.image, color: AppTheme.primaryColor),
                                title: Text('Photo', style: TextStyle(color: AppTheme.textPrimary)),
                                onTap: () { Navigator.pop(context); _addStatus('IMAGE'); },
                              ),
                              ListTile(
                                leading: Icon(Icons.videocam, color: AppTheme.primaryColor),
                                title: Text('Video', style: TextStyle(color: AppTheme.textPrimary)),
                                onTap: () { Navigator.pop(context); _addStatus('VIDEO'); },
                              ),
                            ],
                          ),
                        );
                      },
                    ) : null,
                  ),
                  
                  if (recentUpdates.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text('Recent updates', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                    ),
                  ...recentUpdates.map((group) => _buildStatusTile(group)),
                  
                  if (viewedUpdates.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text('Viewed updates', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                    ),
                  ...viewedUpdates.map((group) => _buildStatusTile(group)),

                  if (mutedUpdates.isNotEmpty) ...[
                    InkWell(
                      onTap: () => setState(() => _showMuted = !_showMuted),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Muted updates', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                            Icon(_showMuted ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppTheme.textSecondary),
                          ],
                        ),
                      ),
                    ),
                    if (_showMuted)
                      ...mutedUpdates.map((group) => _buildStatusTile(group)),
                  ],
                  
                  const SizedBox(height: 80), // Padding for FAB
                ],
              ),
    );
  }

  Widget _buildStatusTile(UserStatusGroup group) {
    final latest = group.statuses.last;
    final user = group.user;
    final avatarUrl = user['avatarUrl'];

    // Elapsed fraction for countdown arc ring (oldest status drives the ring)
    final oldest = group.statuses.first;
    final arcFraction = oldest.timeElapsedFraction;
    final ringColor = group.isMuted
        ? Colors.grey
        : (group.hasUnread ? AppTheme.primaryColor : Colors.grey.shade600);

    return ListTile(
      leading: SizedBox(
        width: 56,
        height: 56,
        child: CustomPaint(
          painter: _StatusArcPainter(
            elapsed: arcFraction,
            color: ringColor,
            hasUnread: group.hasUnread && !group.isMuted,
          ),
          child: Center(
            child: CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.surfaceColor,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(ApiService.getMediaUrl(avatarUrl))
                  : null,
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? Icon(Icons.person, color: AppTheme.textSecondary)
                  : null,
            ),
          ),
        ),
      ),
      title: Text(
        user['username'] ?? 'User',
        style: TextStyle(
          color: group.isMuted ? AppTheme.textSecondary : AppTheme.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Row(
        children: [
          Text(_formatTime(latest.createdAt), style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(width: 6),
          Text('· ${oldest.timeRemainingLabel}', style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 11)),
        ],
      ),
      trailing: IconButton(
        icon: Icon(Icons.emoji_emotions_outlined, color: AppTheme.textSecondary, size: 20),
        tooltip: 'React',
        onPressed: () => _showEmojiReactBar(group),
      ),
      onTap: () => _viewStatus(group),
      onLongPress: () => _toggleMute(group),
    );
  }

  void _showEmojiReactBar(UserStatusGroup group) {
    setState(() => _isPaused_emoji = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: 90,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _quickEmoji.map((emoji) {
            return GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                setState(() => _isPaused_emoji = false);
                final contactId = (group.user['id'] ?? group.user['_id'])?.toString();
                if (contactId == null) return;
                final chat = await ChatService().createDirectChat(contactId);
                if (chat != null && mounted) {
                  final latestStatusId = group.statuses.last.id;
                  final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
                  socket?.emit('send_message', {
                    'conversationId': chat.id,
                    'content': emoji,
                    'replyToStatusId': latestStatusId,
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('$emoji sent as reaction!'),
                    duration: const Duration(seconds: 1),
                  ));
                }
              },
              child: Text(emoji, style: const TextStyle(fontSize: 32)),
            );
          }).toList(),
        ),
      ),
    ).whenComplete(() => setState(() => _isPaused_emoji = false));
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return 'Yesterday';
    }
  }
}

/// Countdown arc ring painter for status list tiles.
/// Draws a full-circle grey track and a coloured arc showing time elapsed (clockwise).
/// When [hasUnread] is true the arc glows with extra strokeWidth.
class _StatusArcPainter extends CustomPainter {
  final double elapsed;   // 0.0 – 1.0
  final Color color;
  final bool hasUnread;

  const _StatusArcPainter({
    required this.elapsed,
    required this.color,
    required this.hasUnread,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width / 2) - 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    const startAngle = -math.pi / 2; // 12 o’clock

    // Track (grey)
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hasUnread ? 2.5 : 2.0
      ..color = Colors.grey.shade700;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    // Elapsed arc (coloured)
    final elapsedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hasUnread ? 3.0 : 2.0
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, startAngle, math.pi * 2 * elapsed, false, elapsedPaint);
  }

  @override
  bool shouldRepaint(_StatusArcPainter oldDelegate) =>
      oldDelegate.elapsed != elapsed ||
      oldDelegate.color != color ||
      oldDelegate.hasUnread != hasUnread;
}
