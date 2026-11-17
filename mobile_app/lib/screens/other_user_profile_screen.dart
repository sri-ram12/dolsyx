import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'verify_safety_number_screen.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../providers/auth_provider.dart';
import 'package:intl/intl.dart';
import '../widgets/color_avatar.dart';
import '../widgets/full_screen_image_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/call_screen.dart';
import '../screens/chat_room_screen.dart';
import '../services/local_database_service.dart';
import '../services/event_bus.dart';
import '../models/message.dart';
import '../utils/e2ee/e2ee_media_cache.dart';
import '../utils/e2ee/background_crypto_worker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'media_gallery_screen.dart';

class OtherUserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const OtherUserProfileScreen({super.key, required this.user});

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  final ApiService _apiService = ApiService();
  String? _localNickname;
  bool _isBlocked = false;
  bool _isOnline = false;
  bool _isTyping = false;
  DateTime? _lastSeen;
  int _selectedMediaTab = 0; // 0: Media, 1: Docs, 2: Links
  List<dynamic> _mediaItems = [];
  List<dynamic> _docItems = [];
  List<dynamic> _linkItems = [];
  bool _isLoadingMedia = true;
  bool _isChatLocked = false;
  String? _resolvedConvId;

  @override
  void initState() {
    super.initState();
    _checkBlockedStatus();
    _checkChatLockStatus();
    _fetchMediaMessages();
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (widget.user['lastSeen'] != null) {
      _lastSeen = DateTime.tryParse(widget.user['lastSeen'].toString());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _isOnline = authProvider.socketService.onlineUserIds.contains(userId?.toString());
      if (mounted) setState(() {});
      authProvider.socketService.onStatusChange(_handleStatusChange);
      authProvider.socketService.onTypingChange(_handleTypingChange);
    });
  }

  Future<void> _checkChatLockStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockedIds = (prefs.getStringList('locked_chat_ids') ?? []).toSet();
      String? convId = widget.user['conversationId']?.toString();
      final userId = (widget.user['id'] ?? widget.user['_id'])?.toString();

      if ((convId == null || convId.isEmpty) && userId != null && userId.isNotEmpty) {
        final cachedChats = await ChatService().getCachedChats();
        final matches = cachedChats.where(
          (c) => !c.isGroup && (c.participants?.any((p) => (p['user']?['id'] ?? p['user']?['_id'])?.toString() == userId) ?? false),
        );
        if (matches.isNotEmpty) {
          convId = matches.first.id;
        }
      }

      _resolvedConvId = convId;
      bool isLocked = false;
      if (convId != null && convId.isNotEmpty && lockedIds.contains(convId)) {
        isLocked = true;
      }
      if (mounted) {
        setState(() => _isChatLocked = isLocked);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.socketService.offStatusChange(_handleStatusChange);
    authProvider.socketService.offTypingChange(_handleTypingChange);
    super.dispose();
  }

  void _handleStatusChange(dynamic data) {
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (mounted && data['userId']?.toString() == userId?.toString()) {
      setState(() {
        _isOnline = data['status'] == 'online';
        if (data['lastSeen'] != null) {
          _lastSeen = DateTime.tryParse(data['lastSeen'].toString());
        }
      });
    }
  }

  void _handleTypingChange(dynamic data) {
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (mounted && data['userId']?.toString() == userId?.toString()) {
      setState(() {
        _isTyping = data['isTyping'] == true;
      });
    }
  }

  Future<void> _checkBlockedStatus() async {
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (userId != null) {
      final blockedUsers = await _apiService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _isBlocked = blockedUsers.any((u) {
            final blockedUser = u['blockedUser'];
            return blockedUser != null && (blockedUser['_id'] == userId || blockedUser['id'] == userId);
          });
        });
      }
    }
  }

  void _unblockUser() async {
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (userId != null) {
      // 0ms instant optimistic update
      setState(() => _isBlocked = false);
      AppEventBus().emitUserBlockUpdated(userId.toString(), false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User unblocked')),
      );
      _apiService.unblockUser(userId).catchError((e) {
        debugPrint('[OtherUserProfile] Background unblock error: $e');
        return false;
      });
    }
  }

  void _blockUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Block user?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Blocked contacts will no longer be able to call you or send you messages.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Block', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      final userId = widget.user['id'] ?? widget.user['_id'];
      if (userId != null) {
        // 0ms instant optimistic update
        setState(() => _isBlocked = true);
        AppEventBus().emitUserBlockUpdated(userId.toString(), true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked')),
        );
        _apiService.blockUser(userId).catchError((e) {
          debugPrint('[OtherUserProfile] Background block error: $e');
          return false;
        });
      }
    }
  }

  void _deleteContact() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Delete contact?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Are you sure you want to remove this person from your contacts list?', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      final userId = (widget.user['id'] ?? widget.user['_id'] ?? widget.user['email'] ?? widget.user['username'] ?? '').toString();
      if (userId.isNotEmpty) {
        // 0ms instant optimistic event dispatch & pop without waiting for network latency
        AppEventBus().emitContactUpdated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Contact deleted successfully'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
        Navigator.pop(context, true);

        if (token != null) {
          ContactService.deleteContact(token, userId).catchError((e) {
            debugPrint('[OtherUserProfile] Background delete contact error: $e');
            return false;
          });
        }
      }
    }
  }

  void _editName() {
    final controller = TextEditingController(text: _localNickname ?? widget.user['username']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Edit Contact Name', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _localNickname = controller.text.trim();
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _startAudioCall() {
    final userId = widget.user['id'] ?? widget.user['_id'];
    final conversationId = widget.user['conversationId'] ?? '';
    final name = _localNickname ?? widget.user['username'] ?? 'User';
    final avatar = widget.user['avatarUrl'];

    if (userId == null || conversationId.isEmpty) return;

    if (CallScreen.isCallActiveNotifier.value && CallScreen.activeConversationId == conversationId) {
      final state = CallScreen.activeCallState;
      if (state != null && state.mounted) {
        Navigator.popUntil(context, (route) => route.isFirst || route.settings.name == 'CallScreen');
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'CallScreen'),
        builder: (_) => CallScreen(
          conversationId: conversationId,
          remoteUserId: userId,
          remoteUserName: name,
          remoteAvatarUrl: avatar,
          isAudioOnly: true,
          isIncoming: false,
        ),
      ),
    );
  }

  void _startVideoCall() {
    final userId = widget.user['id'] ?? widget.user['_id'];
    final conversationId = widget.user['conversationId'] ?? '';
    final name = _localNickname ?? widget.user['username'] ?? 'User';
    final avatar = widget.user['avatarUrl'];

    if (userId == null || conversationId.isEmpty) return;

    if (CallScreen.isCallActiveNotifier.value && CallScreen.activeConversationId == conversationId) {
      final state = CallScreen.activeCallState;
      if (state != null && state.mounted) {
        Navigator.popUntil(context, (route) => route.isFirst || route.settings.name == 'CallScreen');
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'CallScreen'),
        builder: (_) => CallScreen(
          conversationId: conversationId,
          remoteUserId: userId,
          remoteUserName: name,
          remoteAvatarUrl: avatar,
          isAudioOnly: false,
          isIncoming: false,
        ),
      ),
    );
  }

  void _triggerDirectChatSearch() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context, 'start_search');
    } else {
      final userId = widget.user['id'] ?? widget.user['_id'];
      final conversationId = widget.user['conversationId'] ?? '';
      final name = _localNickname ?? widget.user['username'] ?? 'Chat';
      final avatar = widget.user['avatarUrl'];
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            conversationId: conversationId,
            chatName: name,
            avatarUrl: avatar,
            remoteUserId: userId,
            remoteUser: widget.user,
            autoStartSearch: true,
          ),
        ),
      );
    }
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Clear this chat?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Messages will be removed for you on this device.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear chat', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final token = authProvider.token;
        final conversationId = widget.user['conversationId'] ?? '';
        if (conversationId.isEmpty) return;

        final response = await http.delete(
          Uri.parse('${ApiService.baseUrl}/chats/$conversationId/messages'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (mounted && response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared')));
          Navigator.pop(context);
        }
      } catch (_) {}
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return DateFormat('h:mm a').format(dt);
    }
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  Widget _buildHeaderAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 24),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _categorizeAndSetMedia(List<dynamic> mediaMessages) {
    final List<dynamic> media = [];
    final List<dynamic> docs = [];
    final List<dynamic> links = [];
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+|www\.[^\s]+)', caseSensitive: false);

    for (final raw in mediaMessages) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (m['isDeleted'] == true || m['isDeleted'] == 1) continue;

      final rawUrl = (m['_resolvedUrl'] ?? m['mediaUrl'] ?? m['fileUrl'] ?? m['url'] ?? '').toString().trim();
      final mediaType = (m['mediaType'] ?? '').toString().toUpperCase();
      final content = (m['content'] ?? '').toString().trim();

      final isInvalidUrl = rawUrl.isEmpty ||
          rawUrl == 'audio' ||
          rawUrl == 'video' ||
          rawUrl == 'null' ||
          rawUrl == 'undefined';

      // 1. Check for Documents
      final isDoc = mediaType == 'FILE' ||
          mediaType == 'DOCUMENT' ||
          mediaType == 'PDF' ||
          mediaType == 'DOC' ||
          RegExp(r'\.(pdf|docx?|xlsx?|pptx?|txt|zip|rar|apk|csv|json|xml|tar|gz)($|\?)', caseSensitive: false).hasMatch(rawUrl) ||
          RegExp(r'\.(pdf|docx?|xlsx?|pptx?|txt|zip|rar|apk|csv|json|xml|tar|gz)($|\?)', caseSensitive: false).hasMatch(content);

      if (isDoc && (!isInvalidUrl || content.isNotEmpty)) {
        docs.add({...m, '_resolvedUrl': !isInvalidUrl ? rawUrl : content});
      } else if (!isInvalidUrl) {
        // 2. Check for Photos and Videos (Media)
        final isVideo = mediaType == 'VIDEO' ||
            RegExp(r'\.(mp4|mov|avi|mkv|webm|3gp)($|\?)', caseSensitive: false).hasMatch(rawUrl);
        final isAudio = mediaType == 'AUDIO' || mediaType == 'VOICE' ||
            RegExp(r'\.(mp3|m4a|aac|wav|ogg|opus)($|\?)', caseSensitive: false).hasMatch(rawUrl);

        if (!isAudio && mediaType != 'CALL_LOG' && mediaType != 'LOCATION' && mediaType != 'SYSTEM') {
          media.add({...m, '_resolvedUrl': rawUrl, '_isVideo': isVideo});
        }
      }

      // 3. Check for Links in content or rawUrl
      if (content.isNotEmpty && urlRegex.hasMatch(content)) {
        final matches = urlRegex.allMatches(content);
        for (final match in matches) {
          final linkUrl = match.group(0);
          if (linkUrl != null && linkUrl.isNotEmpty) {
            links.add({
              ...m,
              '_linkUrl': linkUrl.startsWith('http') ? linkUrl : 'https://$linkUrl',
              '_displayTitle': content,
            });
          }
        }
      } else if (rawUrl.startsWith('http') && (mediaType == 'TEXT' || mediaType.isEmpty)) {
        links.add({
          ...m,
          '_linkUrl': rawUrl,
          '_displayTitle': rawUrl,
        });
      }
    }

    if (mounted) {
      setState(() {
        _mediaItems = media;
        _docItems = docs;
        _linkItems = links;
        _isLoadingMedia = false;
      });
    }
  }

  Future<void> _fetchMediaMessages() async {
    String conversationId = widget.user['conversationId'] ?? '';
    final userId = widget.user['id'] ?? widget.user['_id'];

    if (conversationId.isEmpty && userId != null) {
      try {
        final chat = await ChatService().createDirectChat(userId);
        if (chat != null) {
          conversationId = chat.id;
          _resolvedConvId = chat.id;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    if (conversationId.isEmpty) {
      setState(() => _isLoadingMedia = false);
      return;
    }

    // 1. Instant 0ms local SQLite loading: Decrypt all candidate messages so E2EE links & docs resolve
    try {
      final localMsgs = await LocalDatabaseService().getMessages(conversationId);
      final localMedia = localMsgs.where((msg) {
        if (msg.isDeleted) return false;
        final type = (msg.mediaType ?? '').toUpperCase();
        return type != 'CALL_LOG' && type != 'SYSTEM' && type != 'LOCATION';
      }).map((msg) => msg.toJson()).toList();

      if (localMedia.isNotEmpty && mounted) {
        final decryptedLocal = await BackgroundCryptoWorker().decryptMessageListInBackground(
          rawMessages: localMedia,
          conversationId: conversationId,
        );
        _categorizeAndSetMedia(decryptedLocal);
      }
    } catch (_) {}

    // 2. Fetch server media messages
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token ?? '';
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/chats/$conversationId/media'),
        headers: ApiService.authHeaders(token),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final List<dynamic> rawMediaMessages = jsonDecode(res.body);
        final listToDecrypt = rawMediaMessages.map((e) => Map<String, dynamic>.from(e)).toList();
        final decryptedList = await BackgroundCryptoWorker().decryptMessageListInBackground(
          rawMessages: listToDecrypt,
          conversationId: conversationId,
        );
        _categorizeAndSetMedia(decryptedList);
      } else {
        if (mounted && _mediaItems.isEmpty) setState(() => _isLoadingMedia = false);
      }
    } catch (e) {
      if (mounted && _mediaItems.isEmpty) setState(() => _isLoadingMedia = false);
    }
  }

  Widget _buildCategorizedMediaSection() {
    return Container(
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MediaGalleryScreen(
                    title: widget.user['username'] ?? widget.user['name'] ?? 'Media, Docs & Links',
                    messages: const [],
                    conversationId: widget.user['conversationId'] ?? '',
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Media, Docs & Links', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTabChip(0, '🖼️ Media'),
              const SizedBox(width: 8),
              _buildTabChip(1, '📄 Docs'),
              const SizedBox(width: 8),
              _buildTabChip(2, '🔗 Links'),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _isLoadingMedia && _mediaItems.isEmpty && _docItems.isEmpty && _linkItems.isEmpty
                ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor, strokeWidth: 2))
                : _selectedMediaTab == 0
                    ? (_mediaItems.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                Icon(Icons.photo_library, color: AppTheme.primaryColor, size: 24),
                                const SizedBox(width: 12),
                                Text('No photos or videos shared yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                              ],
                            ),
                          )
                        : SizedBox(
                            height: 85,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _mediaItems.length,
                              itemBuilder: (ctx, idx) {
                                final item = _mediaItems[idx];
                                final rawUrl = (item['_resolvedUrl'] ?? item['mediaUrl'] ?? item['fileUrl'] ?? item['url'] ?? item['content'] ?? '').toString().trim();
                                final isVideo = item['_isVideo'] == true;
                                final fullUrl = ApiService.getMediaUrl(rawUrl);
                                final mediaKey = item['mediaKey']?.toString();
                                final nonce = item['nonce']?.toString();
                                final mediaType = (item['mediaType'] ?? (isVideo ? 'VIDEO' : 'IMAGE')).toString();

                                Message? msgObj;
                                try {
                                  msgObj = Message.fromJson(Map<String, dynamic>.from(item));
                                } catch (_) {}

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      ctx,
                                      MaterialPageRoute(
                                        builder: (_) => FullScreenImageView(
                                          imageUrl: fullUrl,
                                          isChatMedia: true,
                                          message: msgObj,
                                          rawMediaList: _mediaItems.map((e) => Map<String, dynamic>.from(e)).toList(),
                                          initialIndex: idx,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    width: 85,
                                    height: 85,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: AppTheme.surfaceColor,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: isVideo
                                          ? Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                Container(color: Colors.black),
                                                const Center(
                                                  child: Icon(Icons.videocam, color: Colors.white70, size: 30),
                                                ),
                                                Positioned(
                                                  bottom: 4,
                                                  right: 4,
                                                  child: Container(
                                                    padding: const EdgeInsets.all(2),
                                                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 14),
                                                  ),
                                                ),
                                              ],
                                            )
                                          : FutureBuilder<File?>(
                                              future: E2EEMediaCache.getOrDownloadDecryptedMedia(
                                                mediaUrl: fullUrl,
                                                mediaKey: mediaKey,
                                                nonce: nonce,
                                                mediaType: mediaType,
                                              ),
                                              builder: (context, snapshot) {
                                                if (snapshot.hasData && snapshot.data != null && snapshot.data!.existsSync()) {
                                                  return Image.file(
                                                    snapshot.data!,
                                                    width: 85,
                                                    height: 85,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => _buildFallbackThumbnail(fullUrl),
                                                  );
                                                }
                                                return _buildFallbackThumbnail(fullUrl);
                                              },
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ))
                    : _selectedMediaTab == 1
                        ? (_docItems.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.insert_drive_file, color: AppTheme.primaryColor, size: 24),
                                    const SizedBox(width: 12),
                                    Text('No documents shared yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                                  ],
                                ),
                              )
                            : Column(
                                children: _docItems.map((doc) {
                                  final name = (doc['content'] != null && doc['content'].toString().trim().isNotEmpty)
                                      ? doc['content'].toString().trim()
                                      : (doc['_resolvedUrl'] != null ? doc['_resolvedUrl'].toString().split('/').last : 'Document');
                                  final docUrl = doc['_resolvedUrl'] ?? doc['mediaUrl'] ?? '';
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(Icons.description, color: AppTheme.primaryColor),
                                    title: Text(name, style: TextStyle(color: AppTheme.textPrimary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text('Tap to view document', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                    onTap: () async {
                                      if (docUrl.isNotEmpty) {
                                        final fullUrl = ApiService.getMediaUrl(docUrl);
                                        final uri = Uri.tryParse(fullUrl);
                                        if (uri != null && await canLaunchUrl(uri)) {
                                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                                        }
                                      }
                                    },
                                  );
                                }).toList(),
                              ))
                        : (_linkItems.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.link, color: AppTheme.primaryColor, size: 24),
                                    const SizedBox(width: 12),
                                    Text('No links shared yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                                  ],
                                ),
                              )
                            : Column(
                                children: _linkItems.map((link) {
                                  final urlStr = link['_linkUrl'] ?? link['content'] ?? '';
                                  final title = (link['_displayTitle'] ?? urlStr).toString().trim();
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(Icons.link, color: AppTheme.primaryColor),
                                    title: Text(title, style: TextStyle(color: AppTheme.primaryColor, fontSize: 13, decoration: TextDecoration.underline), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    onTap: () async {
                                      final uri = Uri.tryParse(urlStr);
                                      if (uri != null && await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                  );
                                }).toList(),
                              )),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackThumbnail(String fullUrl) {
    if (fullUrl.isEmpty || !fullUrl.startsWith('http')) {
      return Container(
        color: AppTheme.backgroundColor,
        child: Icon(Icons.photo, color: AppTheme.textSecondary, size: 28),
      );
    }
    return CachedNetworkImage(
      imageUrl: fullUrl,
      width: 85,
      height: 85,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: AppTheme.backgroundColor,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: AppTheme.backgroundColor,
        child: Icon(Icons.photo, color: AppTheme.textSecondary, size: 28),
      ),
    );
  }

  Widget _buildTabChip(int index, String label) {
    final isSelected = _selectedMediaTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMediaTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  void _toggleChatLock() async {
    final userId = (widget.user['id'] ?? widget.user['_id'])?.toString();
    if (userId == null) return;

    String? convId = widget.user['conversationId']?.toString() ?? _resolvedConvId;
    if (convId == null || convId.isEmpty) {
      try {
        final cachedChats = await ChatService().getCachedChats();
        final matches = cachedChats.where(
          (c) => !c.isGroup && (c.participants?.any((p) => (p['user']?['id'] ?? p['user']?['_id'])?.toString() == userId) ?? false),
        );
        if (matches.isNotEmpty) {
          convId = matches.first.id;
        }
      } catch (_) {}
    }

    if (convId == null || convId.isEmpty) {
      try {
        final chat = await ChatService().createDirectChat(userId);
        if (chat != null) convId = chat.id;
      } catch (_) {}
    }

    if (convId == null || convId.isEmpty) return;
    _resolvedConvId = convId;


    try {
      final prefs = await SharedPreferences.getInstance();
      final lockedIds = (prefs.getStringList('locked_chat_ids') ?? []).toSet();
      final newLockedState = !_isChatLocked;

      if (newLockedState) {
        lockedIds.add(convId);
        await prefs.setStringList('locked_chat_ids', lockedIds.toList());
        LocalDatabaseService().setChatLocked(convId, true);
        ChatService().updateChatSettings(convId, {'isLocked': true}).catchError((_) => false);
        if (mounted) {
          setState(() => _isChatLocked = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat locked. It will appear in Locked chats.')),
          );
        }
      } else {
        lockedIds.remove(convId);
        await prefs.setStringList('locked_chat_ids', lockedIds.toList());
        LocalDatabaseService().setChatLocked(convId, false);
        ChatService().updateChatSettings(convId, {'isLocked': false}).catchError((_) => false);
        if (mounted) {
          setState(() => _isChatLocked = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat unlocked.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling chat lock: $e');
    }
  }

  Widget _buildActionItem(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? Colors.red : AppTheme.textSecondary),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : AppTheme.textPrimary,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.user['avatarUrl'];
    final username = _localNickname ?? widget.user['username'] ?? 'User';
    final email = widget.user['email'] ?? '';
    final bio = widget.user['bio'] ?? 'Hey there, I am using DOLSYX';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Info'),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _triggerDirectChatSearch,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'edit_name') _editName();
              if (value == 'delete_contact') _deleteContact();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit_name', child: Text('Edit Name')),
              const PopupMenuItem(
                value: 'delete_contact',
                child: Row(
                  children: [
                    Icon(Icons.person_remove_outlined, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('Delete Contact', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              color: AppTheme.surfaceColor,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (avatarUrl != null) {
                        String fullUrl = avatarUrl.startsWith('http')
                            ? avatarUrl
                            : 'https://dolsyx-app.onrender.com$avatarUrl';
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FullScreenImageView(imageUrl: fullUrl)),
                        );
                      }
                    },
                    child: avatarUrl == null
                        ? ColorAvatar(name: username, radius: 50, fontSize: 36)
                        : CircleAvatar(
                            radius: 50,
                            backgroundColor: AppTheme.backgroundColor,
                            backgroundImage: avatarUrl.startsWith('http')
                                ? NetworkImage(avatarUrl)
                                : NetworkImage('https://dolsyx-app.onrender.com$avatarUrl'),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Text(username, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary), textAlign: TextAlign.center),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(email, style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _isTyping
                        ? '✏️ Typing...'
                        : _isOnline
                            ? '🟢 Online'
                            : (_lastSeen != null
                                ? '🕐 Last seen ${_formatTime(_lastSeen!)}'
                                : (widget.user['lastSeen'] != null
                                    ? '🕐 Last seen ${_formatTime(DateTime.tryParse(widget.user['lastSeen'].toString())!)}'
                                    : '⚫ Offline')),
                    style: TextStyle(
                      color: _isTyping || _isOnline ? AppTheme.primaryColor : AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildHeaderAction(Icons.call, 'Audio', _startAudioCall),
                      _buildHeaderAction(Icons.videocam, 'Video', _startVideoCall),
                      _buildHeaderAction(Icons.search, 'Search', _triggerDirectChatSearch),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Container(
              color: AppTheme.surfaceColor,
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(bio, style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 8),

            _buildCategorizedMediaSection(),
            const SizedBox(height: 8),

            Container(
              color: AppTheme.surfaceColor,
              child: Column(
                children: [
                  _buildActionItem(Icons.verified_user, 'Verify Safety Number', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VerifySafetyNumberScreen(
                          contactName: username,
                          contactEmail: email,
                          contactUserId: (widget.user['id'] ?? widget.user['_id'] ?? '').toString(),
                        ),
                      ),
                    );
                  }),
                  _buildActionItem(Icons.notifications, 'Notifications', () {}),
                  SwitchListTile(
                    secondary: Icon(Icons.lock, color: _isChatLocked ? AppTheme.primaryColor : AppTheme.textSecondary),
                    title: Text('Chat Lock', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
                    subtitle: Text(
                      'Lock and hide this chat on this device',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    value: _isChatLocked,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (_) => _toggleChatLock(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Container(
              color: AppTheme.surfaceColor,
              child: Column(
                children: [
                  _buildActionItem(Icons.group_add, 'Create group with user', () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select other participants in the New Group screen.')));
                  }),
                  _buildActionItem(Icons.group, 'Add to group', () {}),
                  _buildActionItem(Icons.star, 'Add to favourite', () {}),
                  _buildActionItem(Icons.person_remove_outlined, 'Delete contact', _deleteContact, isDestructive: true),
                  _buildActionItem(Icons.delete_outline, 'Clear chat', _clearChat, isDestructive: true),
                  _isBlocked 
                      ? _buildActionItem(Icons.block, 'Unblock user', _unblockUser, isDestructive: false)
                      : _buildActionItem(Icons.block, 'Block user', _blockUser, isDestructive: true),
                  _buildActionItem(Icons.thumb_down_alt_outlined, 'Report user', () {}, isDestructive: true),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
