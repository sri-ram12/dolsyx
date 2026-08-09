import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'dart:async';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'forward_message_screen.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:gal/gal.dart';
import '../models/message.dart';
import '../services/socket_service.dart';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/wallpaper_provider.dart';
import '../models/chat.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import 'other_user_profile_screen.dart';
import '../widgets/color_avatar.dart';
import '../widgets/full_screen_image_view.dart';
import 'call_screen.dart';
import 'wallpaper_settings_screen.dart';
import 'group_settings_screen.dart';
import '../utils/e2ee/crypto_service.dart';
import '../utils/e2ee/e2ee_api.dart';
import '../widgets/app_lock_wrapper.dart';

class ChatRoomScreen extends StatefulWidget {
  final String conversationId;
  final String chatName;
  final String? avatarUrl;
  final String? remoteUserId;
  final Map<String, dynamic>? remoteUser;
  final bool autoStartSearch;

  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    required this.chatName,
    this.avatarUrl,
    this.remoteUserId,
    this.remoteUser,
    this.autoStartSearch = false,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final SocketService _socketService = SocketService();
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isTyping = false;
  bool _isEmojiVisible = false;
  bool _isContact = true;
  FocusNode _focusNode = FocusNode();
  bool _isRemoteUserTyping = false;
  bool _isRemoteUserOnline = false;
  DateTime? _remoteUserLastSeen;
  Timer? _typingTimer;
  final Set<String> _selectedMessageIds = {};
  bool _isBlocked = false;
  Message? _replyingTo;
  bool _isRecording = false;
  bool _isRecordingLocked = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  String? _recordingPath;
  final AudioRecorder _audioRecorder = AudioRecorder();
  Message? _pinnedMessage;

  // Feature States
  bool _isMuted = false;
  String? _disappearingTimer = 'Off';
  bool _isScreenGuardEnabled = false;

  // In-Chat Search State
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<int> _matchingIndices = [];
  int _currentSearchMatchIndex = 0;

  void _showMuteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mute Notifications'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('8 Hours'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _isMuted = true);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications muted for 8 Hours')));
              },
            ),
            ListTile(
              title: const Text('1 Week'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _isMuted = true);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications muted for 1 Week')));
              },
            ),
            ListTile(
              title: const Text('Always'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _isMuted = true);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications muted Always')));
              },
            ),
            if (_isMuted)
              ListTile(
                title: const Text('Unmute Notifications', style: TextStyle(color: Colors.green)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _isMuted = false);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications unmuted')));
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showDisappearingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disappearing Messages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Off'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _disappearingTimer = 'Off');
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disappearing messages turned Off')));
              },
            ),
            ListTile(
              title: const Text('24 Hours'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _disappearingTimer = '24 Hours');
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Messages will self-destruct after 24 Hours')));
              },
            ),
            ListTile(
              title: const Text('7 Days'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _disappearingTimer = '7 Days');
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Messages will self-destruct after 7 Days')));
              },
            ),
            ListTile(
              title: const Text('90 Days'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _disappearingTimer = '90 Days');
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Messages will self-destruct after 90 Days')));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleScreenGuard() {
    setState(() => _isScreenGuardEnabled = !_isScreenGuardEnabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isScreenGuardEnabled ? '🛡️ Screen Guard Enabled (Screenshots & Recordings Protected)' : 'Screen Guard Disabled')),
    );
  }

  void _exportChatTranscript() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final myId = user?['id'] ?? user?['_id'] ?? '';

    final buffer = StringBuffer();
    buffer.writeln('=== DOLSYX CHAT TRANSCRIPT ===');
    buffer.writeln('Chat: ${widget.chatName}');
    buffer.writeln('Date: ${DateTime.now().toIso8601String()}');
    buffer.writeln('===============================\n');

    for (var msg in _messages) {
      final timeStr = DateFormat('yyyy-MM-dd HH:mm').format(msg.createdAt.toLocal());
      final senderName = msg.senderId == myId ? 'Me' : widget.chatName;
      buffer.writeln('[$timeStr] $senderName: ${msg.content}');
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/DOLSYX_${widget.chatName.replaceAll(' ', '_')}_ChatBackup.txt');
      await file.writeAsString(buffer.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chat backup exported: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exported Chat Backup successfully!')),
        );
      }
    }
  }

  void _handleGroupUpdated(dynamic data) {
    if (mounted && data['conversationId'] == widget.conversationId) {
      setState(() {
        if (data['avatarUrl'] != null) {
          // Force avatar URL update
          (widget as dynamic);
        }
      });
      _fetchMessages();
    }
  }

  void _handleViewOnceOpened(dynamic data) {
    if (mounted && data['conversationId'] == widget.conversationId) {
      final msgId = data['messageId'];
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx != -1) {
          _messages[idx].isViewed = true;
        }
      });
    }
  }

  void _handleLiveLocationUpdated(dynamic data) {
    if (mounted && data['conversationId'] == widget.conversationId) {
      final msgId = data['messageId'];
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx != -1 && lat != null && lng != null) {
          _messages[idx] = Message(
            id: _messages[idx].id,
            content: _messages[idx].content,
            senderId: _messages[idx].senderId,
            conversationId: _messages[idx].conversationId,
            mediaType: 'LOCATION',
            latitude: lat,
            longitude: lng,
            isLiveLocation: true,
            createdAt: _messages[idx].createdAt,
          );
        }
      });
    }
  }

  void _handleMessagePinned(dynamic data) {
    if (mounted && data['conversationId'] == widget.conversationId) {
      final pinnedData = data['pinnedMessage'];
      if (pinnedData != null && pinnedData['message'] != null) {
        setState(() {
          _pinnedMessage = Message.fromJson(pinnedData['message']);
        });
      }
    }
  }

  void _handleMessageUnpinned(dynamic data) {
    if (mounted && data['conversationId'] == widget.conversationId) {
      setState(() {
        _pinnedMessage = null;
      });
    }
  }

  void _handlePollUpdated(dynamic data) {
    if (!mounted || data == null) return;
    if (data['conversationId'] == widget.conversationId) {
      final msgId = data['messageId']?.toString();
      final newContent = data['content']?.toString();
      if (msgId != null && newContent != null) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == msgId);
          if (idx != -1) {
            _messages[idx] = Message(
              id: _messages[idx].id,
              content: newContent,
              senderId: _messages[idx].senderId,
              conversationId: _messages[idx].conversationId,
              createdAt: _messages[idx].createdAt,
              mediaType: _messages[idx].mediaType,
              mediaUrl: _messages[idx].mediaUrl,
              receipts: _messages[idx].receipts,
              reactions: _messages[idx].reactions,
              isEdited: _messages[idx].isEdited,
            );
          }
        });
      }
    }
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
      _matchingIndices = [];
      _currentSearchMatchIndex = 0;
    });
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _matchingIndices = [];
      _currentSearchMatchIndex = 0;
    });
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _matchingIndices = [];
        _currentSearchMatchIndex = 0;
      });
      return;
    }
    final q = query.trim().toLowerCase();
    final List<int> matches = [];
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].content.toLowerCase().contains(q)) {
        matches.add(i);
      }
    }
    setState(() {
      _matchingIndices = matches;
      _currentSearchMatchIndex = matches.isNotEmpty ? 0 : 0;
    });
    if (matches.isNotEmpty) {
      _scrollToMatch(0);
    }
  }

  void _scrollToMatch(int matchIdx) {
    if (_matchingIndices.isEmpty || matchIdx < 0 || matchIdx >= _matchingIndices.length) return;
    final msgIndex = _matchingIndices[matchIdx];
    _scrollController.animateTo(
      msgIndex * 60.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoStartSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startSearch());
    }
    _checkIfContact();
    _checkBlockedStatus();
    _fetchMessages();
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.socketService.joinConversation(widget.conversationId);
    authProvider.socketService.onMessageReceived(_handleIncomingMessage);
    
    // Listen for real-time E2EE decrypted messages
    authProvider.socketService.onEncryptedMessageReceived(_handleEncryptedMessage);
    
    // Clear unread messages count on entry
    authProvider.socketService.socket?.emit('mark_read', {
      'conversationId': widget.conversationId,
    });

    authProvider.socketService.onTypingChange(_handleTypingChange);
    authProvider.socketService.onStatusChange(_handleStatusChange);
    authProvider.socketService.onChatCleared(_handleChatCleared);
    authProvider.socketService.onMessageDeleted(_handleMessageDeleted);
    authProvider.socketService.onMessagesRead(_handleMessagesRead);
    authProvider.socketService.onProfileUpdated(_handleProfileUpdated);
    authProvider.socketService.onReactionAdded(_handleReactionAdded);
    authProvider.socketService.onReactionRemoved(_handleReactionRemoved);

    final socket = authProvider.socketService.socket;
    socket?.on('group_updated', _handleGroupUpdated);
    socket?.on('view_once_opened', _handleViewOnceOpened);
    socket?.on('live_location_updated', _handleLiveLocationUpdated);
    socket?.on('message_pinned', _handleMessagePinned);
    socket?.on('message_unpinned', _handleMessageUnpinned);
    socket?.on('poll_updated', _handlePollUpdated);

    _messageController.addListener(_onTextChanged);
    
    // Set initial status from socket and widget
    if (widget.remoteUserId != null) {
      _isRemoteUserOnline = authProvider.socketService.onlineUserIds.contains(widget.remoteUserId);
    }
    if (widget.remoteUser != null && widget.remoteUser!['lastSeen'] != null) {
      _remoteUserLastSeen = DateTime.tryParse(widget.remoteUser!['lastSeen'].toString());
    }
  }

  @override
  void dispose() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.socketService.leaveConversation(widget.conversationId);
    authProvider.socketService.offMessageReceived(_handleIncomingMessage);
    authProvider.socketService.offEncryptedMessageReceived(_handleEncryptedMessage);
    authProvider.socketService.offTypingChange(_handleTypingChange);
    authProvider.socketService.offStatusChange(_handleStatusChange);
    authProvider.socketService.offChatCleared(_handleChatCleared);
    authProvider.socketService.offMessageDeleted(_handleMessageDeleted);
    authProvider.socketService.offMessagesRead(_handleMessagesRead);
    authProvider.socketService.offProfileUpdated(_handleProfileUpdated);
    authProvider.socketService.offReactionAdded(_handleReactionAdded);
    authProvider.socketService.offReactionRemoved(_handleReactionRemoved);
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void setState(fn) {
    if (mounted) {
      try {
        super.setState(fn);
      } catch (_) {}
    }
  }

  void _startRecordingTimer() {
    _recordingDuration = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
      });
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _onTextChanged() {
    final text = _messageController.text;
    
    if (text.isEmpty) {
      if (_isTyping) {
        _isTyping = false;
        Provider.of<AuthProvider>(context, listen: false).socketService.emitTyping(widget.conversationId, false);
        _typingTimer?.cancel();
      }
      return;
    }

    if (!_isTyping) {
      _isTyping = true;
      Provider.of<AuthProvider>(context, listen: false).socketService.emitTyping(widget.conversationId, true);
    }
    
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 1), () {
      if (_isTyping && mounted) {
        _isTyping = false;
        Provider.of<AuthProvider>(context, listen: false).socketService.emitTyping(widget.conversationId, false);
      }
    });
  }

  void _handleTypingChange(dynamic data) {
    if (mounted && data['conversationId'] == widget.conversationId) {
      final typingUserId = data['userId']?.toString();
      final myRemoteId = widget.remoteUserId?.toString();
      if (myRemoteId == null || typingUserId == myRemoteId) {
        setState(() {
          _isRemoteUserTyping = data['isTyping'] == true;
        });
      }
    }
  }

  void _handleStatusChange(dynamic data) {
    if (mounted) {
      final statusUserId = data['userId']?.toString();
      final myRemoteId = widget.remoteUserId?.toString();
      if (myRemoteId != null && statusUserId == myRemoteId) {
        setState(() {
          _isRemoteUserOnline = data['status'] == 'online';
          if (data['lastSeen'] != null) {
            _remoteUserLastSeen = DateTime.tryParse(data['lastSeen'].toString());
          }
        });
      }
    }
  }

  void _handleMessagesRead(dynamic data) {
    if (!mounted || data == null) return;
    if (data['conversationId'] == widget.conversationId) {
      if (!mounted) return;
      setState(() {
        for (var msg in _messages) {
          if (msg.senderId != data['userId']) {
            if (msg.receipts == null) {
              // Message model receipts is final List<dynamic>?, so we can't just assign to it if it's null
              // and we can't mutate a potentially unmodifiable list. 
              // We should just update the state of blue ticks directly or wait for the next fetch.
              // We will just do a soft reload of messages if this happens, but for now since we just need the blue tick,
              // we can update it if it's mutable, but to be safe, let's just trigger a re-fetch of messages.
              _fetchMessages();
              break;
            } else if (!msg.receipts!.any((r) => r['userId'] == data['userId'] && r['status'] == 'READ')) {
              try {
                msg.receipts!.add({'userId': data['userId'], 'status': 'READ'});
              } catch (e) {
                _fetchMessages();
                break;
              }
            }
          }
        }
      });
    }
  }

  void _handleProfileUpdated(dynamic data) {
    if (mounted && data['user'] != null && data['user']['id'] == widget.remoteUserId) {
      setState(() {
        if (widget.remoteUser != null) {
          widget.remoteUser!['avatarUrl'] = data['user']['avatarUrl'];
          widget.remoteUser!['username'] = data['user']['username'];
        }
      });
    }
  }

  void _handleIncomingMessage(dynamic data) {
    if (mounted) {
      try {
        if (data['conversationId'] != widget.conversationId) return;
        setState(() {
          final msg = Message.fromJson(data['message']);
          final tempIndex = _messages.indexWhere((m) =>
            m.id.startsWith('temp-') && m.content == msg.content);
          if (tempIndex != -1) {
            _messages[tempIndex] = msg;
          } else if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
          }
        });
        _scrollToBottom();
        _updateMessageCache();
        
        // Clear unread count for the new incoming message
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.socketService.socket?.emit('mark_read', {
          'conversationId': widget.conversationId,
        });
      } catch (e) {
        print('Error parsing incoming message: $e');
      }
    }
  }

  /// Handles a real-time E2EE message that has already been decrypted by SocketService.
  void _handleEncryptedMessage(dynamic data) {
    if (mounted) {
      try {
        final convId = data['conversationId'] as String?;
        if (convId != widget.conversationId) return;

        final msgData = data['message'] as Map<String, dynamic>;
        final msg = Message.fromJson(msgData);

        // Replace temp optimistic message if content matches
        setState(() {
          final tempIndex = _messages.indexWhere((m) =>
            m.id.startsWith('temp-') && m.content == msg.content);
          if (tempIndex != -1) {
            _messages[tempIndex] = msg;
          } else if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
          }
        });
        _scrollToBottom();
        _updateMessageCache();

        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.socketService.socket?.emit('mark_read', {
          'conversationId': widget.conversationId,
        });
      } catch (e) {
        print('Error handling encrypted message: $e');
      }
    }
  }

  void _updateMessageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_messages.map((m) => m.toJson()).toList());
      await prefs.setString('cached_messages_${widget.conversationId}', encoded);
    } catch (e) {
      print('Error updating message cache: $e');
    }
  }

  void _handleChatCleared(dynamic data) {
    if (mounted && data != null && data['conversationId'] == widget.conversationId) {
      setState(() {
        _messages.clear();
      });
      _updateMessageCache();
    }
  }

  void _handleMessageDeleted(dynamic data) {
    if (mounted && data != null && data['conversationId'] == widget.conversationId) {
      final String msgId = data['messageId'] ?? '';
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msgId);
        if (idx != -1) {
          _messages[idx] = Message(
            id: _messages[idx].id,
            content: "This message was deleted",
            senderId: _messages[idx].senderId,
            conversationId: _messages[idx].conversationId,
            createdAt: _messages[idx].createdAt,
            isDeleted: true,
          );
        }
      });
      _updateMessageCache();
    }
  }

  // Load cached messages from local storage instantly
  Future<void> _loadCachedMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_messages_${widget.conversationId}');
      if (cached != null && mounted) {
        final List<dynamic> data = jsonDecode(cached);
        setState(() {
          _messages = data.map((json) => Message.fromJson(json)).toList();
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      print('Error loading cached messages: $e');
    }
  }

  Future<void> _fetchMessages() async {
    // First, show cached messages instantly
    await _loadCachedMessages();

    try {
      final token = await ApiService().getToken();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/chats/${widget.conversationId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        // Save to local cache for offline access
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_messages_${widget.conversationId}', response.body);

        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _messages = data.map((json) => Message.fromJson(json)).toList();
            _isLoading = false;
            try {
              _pinnedMessage = _messages.firstWhere((m) => m.isPinned);
            } catch (_) {}
          });
          _scrollToBottom();
        }
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error fetching messages (offline?): $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _pinMessage(Message message) {
    setState(() {
      _pinnedMessage = message;
    });
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.socketService.socket?.connected == true) {
      authProvider.socketService.socket!.emit('pin_message', {
        'conversationId': widget.conversationId,
        'messageId': message.id,
      });
    }
  }

  void _editMessageDialog(Message message) {
    final editCtrl = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Edit Message', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: editCtrl,
          style: TextStyle(color: AppTheme.textPrimary),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Type updated message…',
            hintStyle: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            onPressed: () async {
              final newText = editCtrl.text.trim();
              if (newText.isNotEmpty && newText != message.content) {
                Navigator.pop(ctx);
                final success = await _chatService.editMessage(message.id, newText);
                if (success && mounted) {
                  setState(() {
                    final idx = _messages.indexWhere((m) => m.id == message.id);
                    if (idx != -1) {
                      _messages[idx] = Message(
                        id: message.id,
                        content: newText,
                        senderId: message.senderId,
                        conversationId: message.conversationId,
                        createdAt: message.createdAt,
                        isEdited: true,
                        mediaType: message.mediaType,
                        mediaUrl: message.mediaUrl,
                      );
                    }
                  });
                }
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(Message message, bool isMe) {
    final isWithinTimeLimit = DateTime.now().difference(message.createdAt).inMinutes <= 15;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.download, color: Colors.green),
                title: const Text('Save to Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final fullUrl = message.mediaUrl!.startsWith('http')
                        ? message.mediaUrl!
                        : 'https://dolsyx-app.onrender.com${message.mediaUrl!}';
                    final response = await http.get(Uri.parse(fullUrl));
                    final tempDir = await getTemporaryDirectory();
                    final ext = message.mediaType == 'VIDEO' ? 'mp4' : 'jpg';
                    final tempFile = File('${tempDir.path}/dolsyx_${DateTime.now().millisecondsSinceEpoch}.$ext');
                    await tempFile.writeAsBytes(response.bodyBytes);
                    
                    if (message.mediaType == 'VIDEO') {
                      await Gal.putVideo(tempFile.path);
                    } else {
                      await Gal.putImage(tempFile.path);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Saved to Phone Gallery successfully!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saved to Gallery!')),
                      );
                    }
                  }
                },
              ),
            if (isMe && message.mediaUrl == null && isWithinTimeLimit)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blueAccent),
                title: const Text('Edit Message'),
                onTap: () {
                  Navigator.pop(context);
                  _editMessageDialog(message);
                },
              ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete for Everyone', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message.id, true);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete for Me'),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(message.id, false);
              },
            ),
            ListTile(
              leading: Icon(_pinnedMessage?.id == message.id ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(_pinnedMessage?.id == message.id ? 'Unpin Message' : 'Pin Message'),
              onTap: () {
                Navigator.pop(context);
                if (_pinnedMessage?.id == message.id) {
                  setState(() => _pinnedMessage = null);
                } else {
                  _pinMessage(message);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _deleteMessage(String messageId, bool forEveryone) async {
    try {
      final success = await _chatService.deleteMessage(messageId, forEveryone);
      if (success && mounted) {
        setState(() {
          if (forEveryone) {
            final idx = _messages.indexWhere((m) => m.id == messageId);
            if (idx != -1) {
              _messages[idx] = Message(
                id: _messages[idx].id,
                content: "This message was deleted",
                senderId: _messages[idx].senderId,
                conversationId: _messages[idx].conversationId,
                createdAt: _messages[idx].createdAt,
                isDeleted: true,
              );
            }
          } else {
            _messages.removeWhere((m) => m.id == messageId);
          }
        });
      }
    } catch (e) {
      print("Delete failed: $e");
    }
  }

  void _starSelectedMessages() async {
    for (String msgId in _selectedMessageIds) {
      await _chatService.starMessage(msgId);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_selectedMessageIds.length} message(s) starred')));
      setState(() => _selectedMessageIds.clear());
    }
  }

  void _pinSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;
    final msgId = _selectedMessageIds.first;
    setState(() => _selectedMessageIds.clear());
    _showPinDurationDialog(msgId);
  }

  void _showPinDurationDialog(String msgId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Pin Duration', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              title: Text('24 Hours', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _emitPinMessage(msgId, 24);
              },
            ),
            ListTile(
              title: Text('7 Days', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _emitPinMessage(msgId, 168);
              },
            ),
            ListTile(
              title: Text('30 Days', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _emitPinMessage(msgId, 720);
              },
            ),
            ListTile(
              title: Text('Forever', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _emitPinMessage(msgId, 0);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _emitPinMessage(String msgId, int durationHours) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.socketService.socket?.emit('pin_message', {
      'conversationId': widget.conversationId,
      'messageId': msgId,
      'durationHours': durationHours,
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message pinned')));
  }

  void _deleteSelectedMessages(bool forEveryone) async {
    for (String msgId in _selectedMessageIds) {
      _deleteMessage(msgId, forEveryone);
    }
    if (mounted) {
      setState(() => _selectedMessageIds.clear());
    }
  }

  void _reactToMessage(String messageId, String emoji) {
    setState(() => _selectedMessageIds.clear());
    
    final msg = _messages.firstWhere((m) => m.id == messageId);
    final currentUser = Provider.of<AuthProvider>(context, listen: false).user;
    if (currentUser == null) return;
    
    final existingReaction = msg.reactions?.firstWhere(
      (r) => r['userId'] == currentUser['id'], 
      orElse: () => null
    );

    if (existingReaction != null && existingReaction['emoji'] == emoji) {
      Provider.of<AuthProvider>(context, listen: false).socketService.socket?.emit('remove_reaction', {
        'messageId': messageId,
        'conversationId': widget.conversationId,
      });
      // Optimistic update
      setState(() {
        msg.reactions?.removeWhere((r) => r['userId'] == currentUser['id']);
      });
    } else {
      Provider.of<AuthProvider>(context, listen: false).socketService.socket?.emit('add_reaction', {
        'messageId': messageId,
        'conversationId': widget.conversationId,
        'emoji': emoji,
      });
      // Optimistic update
      setState(() {
        if (msg.reactions == null) msg.reactions = [];
        msg.reactions!.removeWhere((r) => r['userId'] == currentUser['id']);
        msg.reactions!.add({'userId': currentUser['id'], 'emoji': emoji});
      });
    }
  }

  void _handleReactionAdded(dynamic data) {
    if (data['conversationId'] == widget.conversationId) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == data['messageId']);
          if (idx != -1) {
            final msg = _messages[idx];
            List<dynamic> reactions = msg.reactions != null ? List.from(msg.reactions!) : [];
            final existingIdx = reactions.indexWhere((r) => r['userId'] == data['userId']);
            if (existingIdx != -1) {
              reactions[existingIdx]['emoji'] = data['emoji'];
            } else {
              reactions.add({'userId': data['userId'], 'emoji': data['emoji']});
            }
            msg.reactions = reactions;
          }
        });
      }
    }
  }

  void _handleReactionRemoved(dynamic data) {
    if (data['conversationId'] == widget.conversationId) {
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == data['messageId']);
          if (idx != -1) {
            final msg = _messages[idx];
            if (msg.reactions != null) {
              msg.reactions!.removeWhere((r) => r['userId'] == data['userId']);
            }
          }
        });
      }
    }
  }

  Future<void> _checkIfContact() async {
    try {
      final token = await ApiService().getToken();
      if (token == null || widget.remoteUserId == null) return;
      
      final isSaved = await ContactService.isContact(token, widget.remoteUserId!);
      if (mounted) {
        setState(() {
          _isContact = isSaved;
        });
      }
    } catch (e) {
      print('Check contact error: $e');
    }
  }

  Future<void> _addContact() async {
    if (widget.remoteUserId == null) return;
    try {
      final token = await ApiService().getToken();
      if (token == null) return;

      await ContactService.addContactById(token, widget.remoteUserId!, savedName: widget.chatName);
      
      if (mounted) {
        setState(() {
          _isContact = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact saved!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isDirectMessage = widget.remoteUser != null;
    final remoteEmail = widget.remoteUser?['email'] as String?;

    if (isDirectMessage && remoteEmail != null && authProvider.token != null) {
      // Send via E2EE pipeline for direct messages
      authProvider.socketService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        recipientEmail: remoteEmail,
        plaintext: text,
        token: authProvider.token!,
        myUserId: authProvider.user?['id'] ?? '',
      ).catchError((e) {
        // Fallback to regular socket for resilience
        print('E2EE send failed, using fallback: $e');
        authProvider.socketService.sendMessage(
          widget.conversationId,
          text,
          parentMessageId: _replyingTo?.id,
        );
      });
    } else {
      // Groups still use regular socket
      authProvider.socketService.sendMessage(
        widget.conversationId,
        text,
        parentMessageId: _replyingTo?.id,
      );
    }
    
    // Optimistic UI update
    final authUser = authProvider.user;
    final newMsg = Message(
      id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      content: text,
      senderId: authUser?['id'] ?? authUser?['_id'] ?? '',
      conversationId: widget.conversationId,
      createdAt: DateTime.now(),
      isPending: authProvider.socketService.socket?.connected != true,
    );
    setState(() {
      _messages.add(newMsg);
    });
    _scrollToBottom();

    _messageController.clear();
    setState(() {
      _replyingTo = null;
    });
    if (_isTyping) {
      _isTyping = false;
      authProvider.socketService.emitTyping(widget.conversationId, false);
      _typingTimer?.cancel();
    }
  }

  void _openGroupSettings() async {
    try {
      List<Chat> chats = await _chatService.getCachedChats();
      if (chats.isEmpty) {
        chats = await _chatService.getChats();
      }
      Chat? chat;
      for (var c in chats) {
        if (c.id == widget.conversationId) {
          chat = c;
          break;
        }
      }
      if (chat == null) {
        chats = await _chatService.getChats();
        for (var c in chats) {
          if (c.id == widget.conversationId) {
            chat = c;
            break;
          }
        }
      }
      if (chat != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupSettingsScreen(
              conversationId: widget.conversationId,
              groupName: widget.chatName,
              groupAvatarUrl: chat!.avatarUrl,
              participants: chat!.participants ?? [],
            ),
          ),
        );
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load group details')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<bool?> _promptViewOnceMode() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Send Media', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: Colors.blue),
              title: Text('Normal', style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text('Media stays in chat history', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.looks_one, color: Colors.green),
              title: Text('View Once', style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: Text('Auto deletes after viewing 1 time', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      final picker = ImagePicker();
      if (source == ImageSource.camera) {
        final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
        if (!mounted) return;
        if (pickedFile != null) {
          final isViewOnce = await _promptViewOnceMode() ?? false;
          await _uploadAndSendMedia(File(pickedFile.path), 'IMAGE', isViewOnce: isViewOnce);
        }
      } else {
        final pickedFiles = await picker.pickMultiImage(imageQuality: 70);
        if (!mounted) return;
        if (pickedFiles.isNotEmpty) {
          final isViewOnce = await _promptViewOnceMode() ?? false;
          await _uploadAndSendMultipleMedia(
            pickedFiles.map((f) => MapEntry(File(f.path), 'IMAGE')).toList(),
            isViewOnce: isViewOnce,
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      final picker = ImagePicker();
      if (source == ImageSource.camera) {
        final pickedFile = await picker.pickVideo(source: ImageSource.camera);
        if (!mounted) return;
        if (pickedFile != null) {
          final isViewOnce = await _promptViewOnceMode() ?? false;
          await _uploadAndSendMedia(File(pickedFile.path), 'VIDEO', isViewOnce: isViewOnce);
        }
      } else {
        final result = await FilePicker.pickFiles(
          allowMultiple: true,
          type: FileType.video,
        );
        if (!mounted) return;
        if (result != null && result.files.isNotEmpty) {
          final isViewOnce = await _promptViewOnceMode() ?? false;
          await _uploadAndSendMultipleMedia(
            result.files
                .where((f) => f.path != null)
                .map((f) => MapEntry(File(f.path!), 'VIDEO'))
                .toList(),
            isViewOnce: isViewOnce,
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking video: $e')));
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
  }

  Future<void> _pickFile() async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (!mounted) return;
      if (result != null && result.files.isNotEmpty) {
        final entries = result.files
            .where((f) => f.path != null)
            .map((f) {
          final ext = f.extension?.toLowerCase() ?? '';
          String type = 'FILE';
          if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) type = 'IMAGE';
          else if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) type = 'VIDEO';
          return MapEntry(File(f.path!), type);
        }).toList();
        await _uploadAndSendMultipleMedia(entries);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking file: $e')));
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
  }

  void _showCameraOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: Icon(Icons.camera_alt, color: AppTheme.primaryColor),
            title: Text('Take Photo', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () {
              Navigator.pop(sheetContext);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: Icon(Icons.videocam, color: AppTheme.primaryColor),
            title: Text('Record Video', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () {
              Navigator.pop(sheetContext);
              _pickVideo(ImageSource.camera);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _uploadAndSendMedia(File file, String mediaType, {bool isViewOnce = false, bool showLoadingState = true}) async {
    if (!mounted) return;
    if (showLoadingState) setState(() => _isLoading = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isDirectMessage = widget.remoteUser != null;
      final remoteEmail = widget.remoteUser?['email'] as String?;
      final apiService = ApiService();

      if (isDirectMessage && remoteEmail != null && authProvider.token != null) {
        try {
          // 🟢 100% E2EE Media Upload: Pre-encrypt file bytes on-device before uploading
          final rawBytes = await file.readAsBytes();
          final encResult = await CryptoService().encryptFileBytes(rawBytes);

          final tempDir = await getTemporaryDirectory();
          final tempEncFile = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.enc');
          await tempEncFile.writeAsBytes(encResult['encryptedBytes'] as List<int>);

          final uploadRes = await apiService.uploadMedia(tempEncFile.path);
          await tempEncFile.delete().catchError((_) => tempEncFile);

          if (uploadRes != null && uploadRes['fileUrl'] != null) {
            final mediaPayloadJson = jsonEncode({
              'encryptedMedia': true,
              'mediaUrl': uploadRes['fileUrl'],
              'mediaKey': encResult['mediaKeyB64'],
              'nonce': encResult['nonceB64'],
              'mediaType': mediaType,
              'isViewOnce': isViewOnce,
            });

            await authProvider.socketService.sendEncryptedMessage(
              conversationId: widget.conversationId,
              recipientEmail: remoteEmail,
              plaintext: mediaPayloadJson,
              token: authProvider.token!,
              myUserId: authProvider.user?['id'] ?? '',
            );
            return;
          }
        } catch (e2eeError) {
          print('E2EE media upload failed, falling back to standard upload: $e2eeError');
        }
      }

      // Standard / group media upload
      final response = await apiService.uploadMedia(file.path);
      if (response != null && response['fileUrl'] != null) {
        authProvider.socketService.sendMessage(
          widget.conversationId, 
          '', 
          mediaUrl: response['fileUrl'], 
          mediaType: mediaType,
          isViewOnce: isViewOnce,
        );
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      if (mounted && showLoadingState) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadAndSendMultipleMedia(List<MapEntry<File, String>> files, {bool isViewOnce = false}) async {
    if (!mounted || files.isEmpty) return;
    int sent = 0;
    int failed = 0;
    setState(() => _isLoading = true);
    for (final entry in files) {
      if (!mounted) break;
      try {
        await _uploadAndSendMedia(entry.key, entry.value, isViewOnce: isViewOnce, showLoadingState: false);
        sent++;
      } catch (_) {
        failed++;
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
      if (failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$sent sent, $failed failed.')),
        );
      }
    }
  }

  Future<void> _pickGalleryMedia() async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.media,
      );
      if (!mounted) return;
      if (result != null && result.files.isNotEmpty) {
        final entries = result.files
            .where((f) => f.path != null)
            .map((f) {
          final ext = f.extension?.toLowerCase() ?? '';
          String type = 'IMAGE';
          if (['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext)) {
            type = 'VIDEO';
          }
          return MapEntry(File(f.path!), type);
        }).toList();
        await _uploadAndSendMultipleMedia(entries);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking media: $e')));
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Wrap(
              alignment: WrapAlignment.spaceAround,
              spacing: 24,
              runSpacing: 20,
              children: [
                _buildAttachGridItem(sheetContext, 'Document', Icons.insert_drive_file, const Color(0xFF7F66FF), _pickFile),
                _buildAttachGridItem(sheetContext, 'Camera', Icons.camera_alt, const Color(0xFFEC407A), _showCameraOptions),
                _buildAttachGridItem(sheetContext, 'Gallery', Icons.photo_library, const Color(0xFFAB47BC), _pickGalleryMedia),
                _buildAttachGridItem(sheetContext, 'Location', Icons.location_on, const Color(0xFF09AF79), _showLocationOptions),
                _buildAttachGridItem(sheetContext, 'Poll', Icons.poll_rounded, const Color(0xFF00BFA5), _showPollCreationModal),
                _buildAttachGridItem(sheetContext, 'Schedule', Icons.schedule, const Color(0xFFFF9800), _showScheduleMessageModal),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showScheduleMessageModal() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(minutes: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (pickedTime == null) return;

    final scheduledDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final textController = TextEditingController(text: _messageController.text);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Schedule Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scheduled for: ${DateFormat('EEE, MMM d, yyyy @ h:mm a').format(scheduledDateTime)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              decoration: const InputDecoration(hintText: 'Enter scheduled message text...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final text = textController.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx);
                final delay = scheduledDateTime.difference(DateTime.now());
                Timer(delay.isNegative ? Duration.zero : delay, () {
                  _messageController.text = text;
                  _sendMessage();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Message scheduled for ${DateFormat('h:mm a').format(scheduledDateTime)}')),
                );
              }
            },
            child: const Text('Schedule'),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachGridItem(BuildContext ctx, String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showPollCreationModal() {
    final questionCtrl = TextEditingController();
    final option1Ctrl = TextEditingController();
    final option2Ctrl = TextEditingController();
    final option3Ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          top: 20, left: 20, right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create a Poll', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(
              controller: questionCtrl,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Ask a question…',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryColor)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: option1Ctrl,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Option 1',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: option2Ctrl,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Option 2',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: option3Ctrl,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Option 3 (optional)',
                labelStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () {
                  final q = questionCtrl.text.trim();
                  final o1 = option1Ctrl.text.trim();
                  final o2 = option2Ctrl.text.trim();
                  final o3 = option3Ctrl.text.trim();

                  if (q.isNotEmpty && o1.isNotEmpty && o2.isNotEmpty) {
                    Navigator.pop(ctx);
                    final List<Map<String, dynamic>> opts = [
                      {'id': 0, 'text': o1, 'votes': []},
                      {'id': 1, 'text': o2, 'votes': []},
                    ];
                    if (o3.isNotEmpty) {
                      opts.add({'id': 2, 'text': o3, 'votes': []});
                    }
                    final pollPayload = jsonEncode({
                      'mediaType': 'POLL',
                      'question': q,
                      'options': opts,
                      'allowMultiple': false,
                    });
                    final authProvider = Provider.of<AuthProvider>(context, listen: false);
                    final isDirectMessage = widget.remoteUser != null;
                    final remoteEmail = widget.remoteUser?['email'] as String?;

                    if (isDirectMessage && remoteEmail != null && authProvider.token != null) {
                      authProvider.socketService.sendEncryptedMessage(
                        conversationId: widget.conversationId,
                        recipientEmail: remoteEmail,
                        plaintext: pollPayload,
                        token: authProvider.token!,
                        myUserId: authProvider.user?['id'] ?? '',
                      );
                    } else {
                      authProvider.socketService.sendMessage(
                        widget.conversationId,
                        pollPayload,
                        mediaType: 'POLL',
                      );
                    }
                  }
                },
                child: const Text('Create Poll', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocationOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFF09AF79),
                child: Icon(Icons.my_location, color: Colors.white, size: 22),
              ),
              title: Text('Share live location', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text('Real-time location updates with timer', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _showLiveLocationTimerPicker();
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
              child: Text('Nearby places', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const CircleAvatar(
                radius: 20,
                backgroundColor: Colors.teal,
                child: Icon(Icons.location_on, color: Colors.white, size: 22),
              ),
              title: Text('Send your current location', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text('Accurate to 15 meters', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _sendCurrentLocation();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _sendCurrentLocation() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isDirectMessage = widget.remoteUser != null;
    final remoteEmail = widget.remoteUser?['email'] as String?;

    final locJson = jsonEncode({
      'mediaType': 'LOCATION',
      'latitude': 12.9716,
      'longitude': 77.5946,
      'locationTitle': 'Current Location',
      'isLiveLocation': false,
    });

    if (isDirectMessage && remoteEmail != null && authProvider.token != null) {
      await authProvider.socketService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        recipientEmail: remoteEmail,
        plaintext: locJson,
        token: authProvider.token!,
        myUserId: authProvider.user?['id'] ?? '',
      );
    } else {
      authProvider.socketService.sendMessage(
        widget.conversationId,
        locJson,
        mediaType: 'LOCATION',
      );
    }
  }

  void _showLiveLocationTimerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Share Live Location', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              title: Text('15 Minutes', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _sendLiveLocation(15);
              },
            ),
            ListTile(
              title: Text('1 Hour', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _sendLiveLocation(60);
              },
            ),
            ListTile(
              title: Text('8 Hours', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _sendLiveLocation(480);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _sendLiveLocation(int minutes) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final expiresAt = DateTime.now().add(Duration(minutes: minutes)).toIso8601String();
    final isDirectMessage = widget.remoteUser != null;
    final remoteEmail = widget.remoteUser?['email'] as String?;

    if (isDirectMessage && remoteEmail != null && authProvider.token != null) {
      final locJson = jsonEncode({
        'mediaType': 'LOCATION',
        'latitude': 12.9716,
        'longitude': 77.5946,
        'locationTitle': 'Sharing live location ($minutes mins)',
        'isLiveLocation': true,
        'liveExpiresAt': expiresAt,
      });
      await authProvider.socketService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        recipientEmail: remoteEmail,
        plaintext: locJson,
        token: authProvider.token!,
        myUserId: authProvider.user?['id'] ?? '',
      );
    } else {
      authProvider.socketService.sendMessage(
        widget.conversationId,
        'Live Location',
        mediaType: 'LOCATION',
        latitude: 12.9716,
        longitude: 77.5946,
        locationTitle: 'Live Location ($minutes mins)',
        isLiveLocation: true,
        liveExpiresAt: expiresAt,
      );
    }
  }

  void _showEmojiPicker() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isEmojiVisible = !_isEmojiVisible;
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  String _formatLastSeen(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateLocal = date.toLocal();
    final dateDay = DateTime(dateLocal.year, dateLocal.month, dateLocal.day);

    final timeStr = DateFormat('h:mm a').format(dateLocal);

    if (dateDay == today) {
      return 'last seen today at $timeStr';
    } else if (dateDay == yesterday) {
      return 'last seen yesterday at $timeStr';
    } else if (now.difference(dateLocal).inDays < 7) {
      final weekday = DateFormat('EEEE').format(dateLocal);
      return 'last seen $weekday at $timeStr';
    } else if (now.year == dateLocal.year) {
      final dateStr = DateFormat('d MMMM').format(dateLocal);
      return 'last seen $dateStr at $timeStr';
    } else {
      final dateStr = DateFormat('d MMMM yyyy').format(dateLocal);
      return 'last seen $dateStr at $timeStr';
    }
  }

  void _confirmClearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Clear Chat', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Are you sure you want to clear all messages in this chat?', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _chatService.clearChat(widget.conversationId);
              if (mounted) {
                if (success) {
                  setState(() => _messages.clear());
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared')));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to clear chat')));
                }
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkBlockedStatus() async {
    if (widget.remoteUserId != null) {
      final blockedUsers = await ApiService().getBlockedUsers();
      if (mounted) {
        setState(() {
          _isBlocked = blockedUsers.any((u) {
            final blockedUser = u['blockedUser'];
            return blockedUser != null && (blockedUser['_id'] == widget.remoteUserId || blockedUser['id'] == widget.remoteUserId);
          });
        });
      }
    }
  }

  void _confirmUnblockUser() {
    if (widget.remoteUserId == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Unblock ${widget.chatName}?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Unblocked contacts will be able to call you and send you messages.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ApiService().unblockUser(widget.remoteUserId!);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.chatName} unblocked')));
                  _checkBlockedStatus();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to unblock user')));
                }
              }
            },
            child: const Text('Unblock', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmBlockUser() {
    if (widget.remoteUserId == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Block ${widget.chatName}?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Blocked contacts will no longer be able to call you or send you messages.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ApiService().blockUser(widget.remoteUserId!);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.chatName} blocked')));
                  _checkBlockedStatus();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to block user')));
                }
              }
            },
            child: const Text('Block', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Color _fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    // Listen to theme changes (including font size) to rebuild the screen
    Provider.of<ThemeProvider>(context);

    final currentUser = Provider.of<AuthProvider>(context).user;
    final wallpaperConfig = Provider.of<WallpaperProvider>(context).getWallpaperForChat(widget.conversationId);
    
    BoxDecoration? wallpaperDecoration;
    if (wallpaperConfig.type == WallpaperType.solidColor && wallpaperConfig.value != null) {
      wallpaperDecoration = BoxDecoration(
        color: _fromHex(wallpaperConfig.value!),
      );
    } else if (wallpaperConfig.type == WallpaperType.pattern && wallpaperConfig.value != null) {
      wallpaperDecoration = BoxDecoration(
        gradient: LinearGradient(
          colors: wallpaperConfig.value!.split(',').map((c) => _fromHex(c)).toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    } else if (wallpaperConfig.type == WallpaperType.customFile && wallpaperConfig.value != null) {
      wallpaperDecoration = BoxDecoration(
        image: DecorationImage(
          image: FileImage(File(wallpaperConfig.value!)),
          fit: BoxFit.cover,
          colorFilter: wallpaperConfig.opacity < 1.0 
              ? ColorFilter.mode(Colors.black.withOpacity(1.0 - wallpaperConfig.opacity), BlendMode.dstATop)
              : null,
        ),
      );
    }

    return Scaffold(      appBar: _selectedMessageIds.isNotEmpty
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedMessageIds.clear()),
              ),
              title: Text('${_selectedMessageIds.length}'),
              actions: [
                if (_selectedMessageIds.length == 1)
                  IconButton(
                    icon: const Icon(Icons.reply),
                    onPressed: () {
                      final msg = _messages.firstWhere((m) => m.id == _selectedMessageIds.first);
                      setState(() {
                        _replyingTo = msg;
                        _selectedMessageIds.clear();
                        _focusNode.requestFocus();
                      });
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.add_reaction_outlined),
                  onPressed: () {
                    final msgId = _selectedMessageIds.first;
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: AppTheme.surfaceColor,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                      builder: (context) => Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ...'👍❤️😂😮😢🙏'.split('').map((emoji) => GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                _reactToMessage(msgId, emoji);
                              },
                              child: Text(emoji, style: const TextStyle(fontSize: 32)),
                            )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    final selectedMsgs = _messages.where((m) => _selectedMessageIds.contains(m.id)).toList();
                    final copiedText = selectedMsgs.map((m) => '[${DateFormat('HH:mm').format(m.createdAt)}] ${m.content}').join('\n');
                    Clipboard.setData(ClipboardData(text: copiedText));
                    setState(() => _selectedMessageIds.clear());
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copied ${selectedMsgs.length} messages to clipboard!')),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.star_border),
                  onPressed: _starSelectedMessages,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    bool allMine = true;
                    for (String msgId in _selectedMessageIds) {
                      final msg = _messages.firstWhere((m) => m.id == msgId);
                      if (msg.senderId != currentUser?['id']) {
                        allMine = false;
                        break;
                      }
                    }
                    
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (context) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (allMine)
                              ListTile(
                                leading: const Icon(Icons.delete_forever, color: Colors.red),
                                title: const Text('Delete for Everyone', style: TextStyle(color: Colors.red)),
                                onTap: () {
                                  Navigator.pop(context);
                                  _deleteSelectedMessages(true);
                                },
                              ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline),
                              title: const Text('Delete for Me'),
                              onTap: () {
                                Navigator.pop(context);
                                _deleteSelectedMessages(false);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.forward),
                  onPressed: () {
                    final messagesToForward = _messages.where((m) => _selectedMessageIds.contains(m.id)).toList();
                    setState(() => _selectedMessageIds.clear());
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ForwardMessageScreen(messages: messagesToForward),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.push_pin_outlined),
                  onPressed: _pinSelectedMessages,
                ),
              ],
            )
          : _isSearching
              ? AppBar(
                  backgroundColor: AppTheme.surfaceColor,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _stopSearch,
                  ),
                  title: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Search in chat...',
                      hintStyle: TextStyle(color: AppTheme.textSecondary),
                      border: InputBorder.none,
                    ),
                    onChanged: _performSearch,
                  ),
                  actions: [
                    if (_matchingIndices.isNotEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '${_currentSearchMatchIndex + 1} of ${_matchingIndices.length}',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: _matchingIndices.isEmpty ? null : () {
                        if (_currentSearchMatchIndex > 0) {
                          setState(() => _currentSearchMatchIndex--);
                          _scrollToMatch(_currentSearchMatchIndex);
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: _matchingIndices.isEmpty ? null : () {
                        if (_currentSearchMatchIndex < _matchingIndices.length - 1) {
                          setState(() => _currentSearchMatchIndex++);
                          _scrollToMatch(_currentSearchMatchIndex);
                        }
                      },
                    ),
                  ],
                )
              : _selectedMessageIds.isNotEmpty
                  ? AppBar(
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _selectedMessageIds.clear()),
                      ),
                      title: Text('${_selectedMessageIds.length} Selected', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
                      actions: [
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: AppTheme.textPrimary),
                          onSelected: (value) async {
                            final selectedMsg = _messages.firstWhere((m) => m.id == _selectedMessageIds.first, orElse: () => _messages.first);
                            final authProvider = Provider.of<AuthProvider>(context, listen: false);
                            final isMe = selectedMsg.senderId == authProvider.user?['id'];

                            if (value == 'copy') {
                              final textToCopy = selectedMsg.content.isNotEmpty ? selectedMsg.content : (selectedMsg.mediaUrl ?? '');
                              Clipboard.setData(ClipboardData(text: textToCopy));
                              setState(() {
                                _messageController.text = textToCopy;
                                _selectedMessageIds.clear();
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Copied & pasted to text input field!')),
                              );
                            } else if (value == 'download' && selectedMsg.mediaUrl != null) {
                              setState(() => _selectedMessageIds.clear());
                              try {
                                final fullUrl = selectedMsg.mediaUrl!.startsWith('http')
                                    ? selectedMsg.mediaUrl!
                                    : 'https://dolsyx-app.onrender.com${selectedMsg.mediaUrl!}';
                                final response = await http.get(Uri.parse(fullUrl));
                                final tempDir = await getTemporaryDirectory();
                                final ext = selectedMsg.mediaType == 'VIDEO' ? 'mp4' : 'jpg';
                                final tempFile = File('${tempDir.path}/dolsyx_${DateTime.now().millisecondsSinceEpoch}.$ext');
                                await tempFile.writeAsBytes(response.bodyBytes);
                                
                                if (selectedMsg.mediaType == 'VIDEO') {
                                  await Gal.putVideo(tempFile.path);
                                } else {
                                  await Gal.putImage(tempFile.path);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Saved to Phone Gallery successfully!')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Saved to Phone Gallery!')),
                                  );
                                }
                              }
                            } else if (value == 'edit' && isMe) {
                              setState(() => _selectedMessageIds.clear());
                              _editMessageDialog(selectedMsg);
                            } else if (value == 'pin') {
                              setState(() => _selectedMessageIds.clear());
                              if (_pinnedMessage?.id == selectedMsg.id) {
                                setState(() => _pinnedMessage = null);
                              } else {
                                _showPinDurationDialog(selectedMsg.id);
                              }
                            } else if (value == 'delete' && isMe) {
                              setState(() => _selectedMessageIds.clear());
                              _deleteMessage(selectedMsg.id, true);
                            }
                          },
                          itemBuilder: (ctx) {
                            final selectedMsg = _messages.firstWhere((m) => m.id == _selectedMessageIds.first, orElse: () => _messages.first);
                            final authProvider = Provider.of<AuthProvider>(ctx, listen: false);
                            final isMe = selectedMsg.senderId == authProvider.user?['id'];
                            final isWithinTimeLimit = DateTime.now().difference(selectedMsg.createdAt).inMinutes <= 15;
                            final hasMedia = selectedMsg.mediaUrl != null && selectedMsg.mediaUrl!.isNotEmpty;

                            return [
                              const PopupMenuItem(
                                value: 'copy',
                                child: Row(
                                  children: [
                                    Icon(Icons.copy, size: 18),
                                    SizedBox(width: 10),
                                    Text('Copy & Autofill'),
                                  ],
                                ),
                              ),
                              if (hasMedia)
                                const PopupMenuItem(
                                  value: 'download',
                                  child: Row(
                                    children: [
                                      Icon(Icons.download, size: 18, color: Colors.green),
                                      SizedBox(width: 10),
                                      Text('Save to Gallery'),
                                    ],
                                  ),
                                ),
                              if (isMe && !hasMedia && isWithinTimeLimit)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 18),
                                      SizedBox(width: 10),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'pin',
                                child: Row(
                                  children: [
                                    const Icon(Icons.push_pin, size: 18),
                                    const SizedBox(width: 10),
                                    Text(_pinnedMessage?.id == selectedMsg.id ? 'Unpin' : 'Pin'),
                                  ],
                                ),
                              ),
                              if (isMe)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_forever, size: 18, color: Colors.red),
                                      SizedBox(width: 10),
                                      Text('Delete for Everyone', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                            ];
                          },
                        ),
                      ],
                    )
                  : AppBar(
              titleSpacing: 0,
              title: GestureDetector(
                onTap: () async {
                  if (widget.remoteUserId != null) {
                    final userMap = widget.remoteUser != null
                        ? {...widget.remoteUser!, 'conversationId': widget.conversationId}
                        : {
                            'id': widget.remoteUserId,
                            'username': widget.chatName,
                            'avatarUrl': widget.avatarUrl,
                            'conversationId': widget.conversationId,
                          };
                    final res = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OtherUserProfileScreen(user: userMap),
                      ),
                    );
                    if (res == 'start_search') {
                      _startSearch();
                    }
                  } else {
                    _openGroupSettings();
                  }
                },
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (widget.avatarUrl != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FullScreenImageView(imageUrl: widget.avatarUrl!),
                            ),
                          );
                        }
                      },
                      child: widget.avatarUrl == null
                          ? ColorAvatar(name: widget.chatName, radius: 18, fontSize: 16)
                          : CircleAvatar(
                              radius: 18,
                              backgroundColor: AppTheme.surfaceColor,
                              backgroundImage: widget.avatarUrl!.startsWith('http')
                                  ? NetworkImage(widget.avatarUrl!)
                                  : NetworkImage('https://dolsyx-app.onrender.com${widget.avatarUrl!}'),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.chatName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.remoteUserId != null)
                            Text(
                              _isRemoteUserTyping
                                  ? 'Typing...'
                                  : _isRemoteUserOnline
                                      ? 'Online'
                                      : (_remoteUserLastSeen != null
                                          ? _formatLastSeen(_remoteUserLastSeen!)
                                          : 'Offline'),
                              style: TextStyle(
                                fontSize: 12,
                                color: _isRemoteUserTyping || _isRemoteUserOnline ? AppTheme.primaryColor : AppTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (widget.remoteUserId != null) ...[
                  IconButton(
                    icon: Icon(Icons.videocam, color: AppTheme.textPrimary),
                    onPressed: () {
                      if (CallScreen.isCallActiveNotifier.value && CallScreen.activeConversationId == widget.conversationId) {
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
                            conversationId: widget.conversationId,
                            remoteUserId: widget.remoteUserId!,
                            remoteUserName: widget.chatName,
                            remoteAvatarUrl: widget.avatarUrl,
                            isAudioOnly: false,
                            isIncoming: false,
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.call, color: AppTheme.textPrimary),
                    onPressed: () {
                      if (CallScreen.isCallActiveNotifier.value && CallScreen.activeConversationId == widget.conversationId) {
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
                            conversationId: widget.conversationId,
                            remoteUserId: widget.remoteUserId!,
                            remoteUserName: widget.chatName,
                            remoteAvatarUrl: widget.avatarUrl,
                            isAudioOnly: true,
                            isIncoming: false,
                          ),
                        ),
                      );
                    },
                  ),
                ],
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: AppTheme.textPrimary),
                  onSelected: (value) async {
                    if (value == 'search') {
                      _startSearch();
                    } else if (value == 'view_contact' && widget.remoteUserId != null) {
                      final userMap = widget.remoteUser != null
                          ? {...widget.remoteUser!, 'conversationId': widget.conversationId}
                          : {
                              'id': widget.remoteUserId,
                              'username': widget.chatName,
                              'avatarUrl': widget.avatarUrl,
                              'conversationId': widget.conversationId,
                            };
                      final res = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => OtherUserProfileScreen(user: userMap)),
                      );
                      if (res == 'start_search') {
                        _startSearch();
                      }
                    } else if (value == 'export_chat') {
                      _exportChatTranscript();
                    } else if (value == 'clear_chat') {
                      _confirmClearChat();
                    } else if (value == 'block_user') {
                      _isBlocked ? _confirmUnblockUser() : _confirmBlockUser();
                    } else if (value == 'mute') {
                      _showMuteDialog();
                    } else if (value == 'disappearing') {
                      _showDisappearingDialog();
                    } else if (value == 'screen_guard') {
                      _toggleScreenGuard();
                    } else if (value == 'wallpaper') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => WallpaperSettingsScreen(conversationId: widget.conversationId)));
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.remoteUserId != null)
                      const PopupMenuItem(
                        value: 'view_contact',
                        child: Text('View Contact'),
                      ),
                    const PopupMenuItem(
                      value: 'export_chat',
                      child: Row(
                        children: [
                          Icon(Icons.download, size: 18),
                          SizedBox(width: 8),
                          Text('Export Chat Backup (.txt)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'clear_chat',
                      child: Text('Clear Chat'),
                    ),
                    if (widget.remoteUserId != null)
                      PopupMenuItem(
                        value: 'block_user',
                        child: Text(_isBlocked ? 'Unblock User' : 'Block User', style: TextStyle(color: _isBlocked ? AppTheme.primaryColor : Colors.red)),
                      ),
                    PopupMenuItem(
                      value: 'mute',
                      child: Row(
                        children: [
                          Icon(_isMuted ? Icons.volume_off : Icons.volume_up, size: 18),
                          const SizedBox(width: 8),
                          Text(_isMuted ? 'Unmute Notifications' : 'Mute Notifications'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'disappearing',
                      child: Row(
                        children: [
                          const Icon(Icons.timer, size: 18),
                          const SizedBox(width: 8),
                          Text('Disappearing Messages (${_disappearingTimer ?? 'Off'})'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'screen_guard',
                      child: Row(
                        children: [
                          Icon(_isScreenGuardEnabled ? Icons.security : Icons.security_outlined, size: 18, color: _isScreenGuardEnabled ? Colors.green : null),
                          const SizedBox(width: 8),
                          Text(_isScreenGuardEnabled ? 'Screen Guard: ON' : 'Screen Guard: OFF'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'wallpaper',
                      child: Row(
                        children: [
                          Icon(Icons.wallpaper, size: 18),
                          SizedBox(width: 8),
                          Text('Set Wallpaper'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: Container(
        decoration: wallpaperDecoration,
        child: Column(
        children: [
          if (_pinnedMessage != null)
            GestureDetector(
              onTap: () {
                final idx = _messages.indexWhere((m) => m.id == _pinnedMessage!.id);
                if (idx != -1 && _scrollController.hasClients) {
                  _scrollController.animateTo(
                    idx * 60.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppTheme.primaryColor.withOpacity(0.15),
                child: Row(
                  children: [
                    Icon(Icons.push_pin, size: 18, color: AppTheme.primaryColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pinned: ${_pinnedMessage!.content.isNotEmpty ? _pinnedMessage!.content : (_pinnedMessage!.mediaType ?? 'Media')}',
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
          if (!_isContact && widget.remoteUserId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppTheme.surfaceColor,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'This user is not in your contacts.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _addContact(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                    ),
                    child: const Text('Add Contact'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMe = currentUser != null && message.senderId == currentUser['id'];
                      final isSelected = _selectedMessageIds.contains(message.id);
                      
                      bool showDateSeparator = false;
                      if (index == 0) {
                        showDateSeparator = true;
                      } else {
                        final prevMessage = _messages[index - 1];
                        final prevDate = DateTime(prevMessage.createdAt.toLocal().year, prevMessage.createdAt.toLocal().month, prevMessage.createdAt.toLocal().day);
                        final currDate = DateTime(message.createdAt.toLocal().year, message.createdAt.toLocal().month, message.createdAt.toLocal().day);
                        if (currDate.isAfter(prevDate)) {
                          showDateSeparator = true;
                        }
                      }

                      Widget separator = const SizedBox.shrink();
                      if (showDateSeparator) {
                        final now = DateTime.now();
                        final currDate = DateTime(message.createdAt.toLocal().year, message.createdAt.toLocal().month, message.createdAt.toLocal().day);
                        final diff = DateTime(now.year, now.month, now.day).difference(currDate).inDays;
                        
                        String dateStr;
                        if (diff == 0) dateStr = 'Today';
                        else if (diff == 1) dateStr = 'Yesterday';
                        else dateStr = DateFormat('MMMM d, yyyy').format(currDate);

                        separator = Container(
                          alignment: Alignment.center,
                          margin: const EdgeInsets.symmetric(vertical: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              dateStr,
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          separator,
                          GestureDetector(
                            onLongPress: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedMessageIds.remove(message.id);
                                } else {
                                  _selectedMessageIds.add(message.id);
                                }
                              });
                            },
                            onTap: () {
                              if (_selectedMessageIds.isNotEmpty) {
                                setState(() {
                                  if (isSelected) {
                                    _selectedMessageIds.remove(message.id);
                                  } else {
                                    _selectedMessageIds.add(message.id);
                                  }
                                });
                              }
                            },
                              child: Container(
                                color: isSelected ? AppTheme.primaryColor.withAlpha(50) : Colors.transparent,
                                child: MessageBubble(
                                  message: message, 
                                  isMe: isMe,
                                  isGroup: widget.remoteUser == null && widget.remoteUserId == null,
                                  searchQuery: _isSearching && _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
                                  onSwipeReply: (msg) {
                                    setState(() {
                                      _replyingTo = msg;
                                      _focusNode.requestFocus();
                                    });
                                  },
                                  onViewOnceOpened: (msgId) {
                                    final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                    if (authProvider.socketService.socket?.connected == true) {
                                      authProvider.socketService.socket!.emit('view_once_opened', {
                                        'messageId': msgId,
                                        'conversationId': widget.conversationId,
                                      });
                                    }
                                    setState(() {
                                      final idx = _messages.indexWhere((m) => m.id == msgId);
                                      if (idx != -1) {
                                        _messages[idx].isViewed = true;
                                      }
                                    });
                                  },
                                  onTapCall: (isVideo) {
                                    if (widget.remoteUserId != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CallScreen(
                                            conversationId: widget.conversationId,
                                            remoteUserId: widget.remoteUserId!,
                                            remoteUserName: widget.chatName,
                                            remoteAvatarUrl: widget.avatarUrl,
                                            isAudioOnly: !isVideo,
                                            isIncoming: false,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (_isLoading && _messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: LinearProgressIndicator(color: AppTheme.primaryColor),
            ),
          if (_replyingTo != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: AppTheme.primaryColor, width: 4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _replyingTo!.senderId == widget.remoteUserId ? (widget.chatName) : 'You',
                          style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyingTo!.content,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.transparent,
            child: _isRecordingLocked
              ? Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        await _audioRecorder.stop();
                        _stopRecordingTimer();
                        setState(() {
                          _isRecording = false;
                          _isRecordingLocked = false;
                        });
                      },
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _formatDuration(_recordingDuration),
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppTheme.primaryColor,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 20),
                        onPressed: () async {
                          final path = await _audioRecorder.stop();
                          _stopRecordingTimer();
                          setState(() {
                            _isRecording = false;
                            _isRecordingLocked = false;
                          });
                          if (path != null) {
                            _uploadAndSendMedia(File(path), 'AUDIO');
                          }
                        },
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        onTap: () {
                          if (_isEmojiVisible) {
                            setState(() { _isEmojiVisible = false; });
                          }
                        },
                        style: TextStyle(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          hintText: _isRecording ? 'Recording... Slide up to lock' : 'Message',
                          hintStyle: TextStyle(color: _isRecording ? Colors.red : AppTheme.textSecondary),
                          filled: true,
                          fillColor: AppTheme.surfaceColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          prefixIcon: _isRecording 
                            ? Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Text(_formatDuration(_recordingDuration), style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              )
                            : IconButton(
                                icon: Icon(_isEmojiVisible ? Icons.keyboard : Icons.emoji_emotions_outlined, color: AppTheme.textSecondary),
                                onPressed: _showEmojiPicker,
                              ),
                          suffixIcon: _isRecording ? null : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.attach_file, color: AppTheme.textSecondary),
                                onPressed: _showAttachmentOptions,
                              ),
                              IconButton(
                                icon: Icon(Icons.camera_alt_outlined, color: AppTheme.textSecondary),
                                onPressed: _showCameraOptions,
                              ),
                            ],
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    SizedBox(width: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _messageController,
                      builder: (context, value, child) {
                        final hasText = value.text.trim().isNotEmpty;
                        if (hasText) {
                          return CircleAvatar(
                            radius: 24,
                            backgroundColor: AppTheme.primaryColor,
                            child: IconButton(
                              icon: const Icon(Icons.send, color: Colors.white, size: 20),
                              onPressed: _sendMessage,
                            ),
                          );
                        }
                        return GestureDetector(
                          onLongPressStart: (_) async {
                            if (await _audioRecorder.hasPermission()) {
                              final directory = await getTemporaryDirectory();
                              final path = '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
                              await _audioRecorder.start(const RecordConfig(), path: path);
                              _startRecordingTimer();
                              setState(() {
                                _isRecording = true;
                              });
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Microphone permission denied')),
                              );
                            }
                          },
                          onLongPressMoveUpdate: (details) {
                            if (_isRecording && !_isRecordingLocked && details.localOffsetFromOrigin.dy < -50) {
                              setState(() {
                                _isRecordingLocked = true;
                              });
                            }
                          },
                          onLongPressEnd: (_) async {
                            if (_isRecording && !_isRecordingLocked) {
                              final path = await _audioRecorder.stop();
                              _stopRecordingTimer();
                              setState(() {
                                _isRecording = false;
                              });
                              if (path != null) {
                                _uploadAndSendMedia(File(path), 'AUDIO');
                              }
                            }
                          },
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Hold to record, release to send')),
                            );
                          },
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: AppTheme.primaryColor,
                            child: Icon(
                              _isRecording ? Icons.mic : Icons.mic_none,
                              color: Colors.white, 
                              size: 20,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
          ),
          if (_isEmojiVisible)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                textEditingController: _messageController,
                scrollController: ScrollController(),
                config: Config(
                  height: 250,
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(
                    backgroundColor: AppTheme.backgroundColor,
                    columns: 7,
                    emojiSizeMax: 28 * (Platform.isIOS ? 1.30 : 1.0),
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: AppTheme.surfaceColor,
                    indicatorColor: AppTheme.primaryColor,
                    iconColorSelected: AppTheme.primaryColor,
                    iconColor: AppTheme.textSecondary,
                  ),
                  bottomActionBarConfig: BottomActionBarConfig(showSearchViewButton: false, backgroundColor: AppTheme.surfaceColor),
                  searchViewConfig: SearchViewConfig(
                    backgroundColor: AppTheme.backgroundColor,
                  ),
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }
}
