import 'dart:convert';
import 'dart:ui';
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
import 'whatsapp_media_picker_screen.dart';
import '../utils/e2ee/crypto_service.dart';
import '../utils/e2ee/e2ee_api.dart';
import '../services/auto_download_service.dart';
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
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isTyping = false;
  bool _isEmojiVisible = false;
  bool _isContact = true;
  FocusNode _focusNode = FocusNode();
  DateTime? _activeScheduledTime;
  Message? _editingMessage;
  bool _isRemoteUserTyping = false;
  bool _isRemoteUserOnline = false;
  DateTime? _remoteUserLastSeen;
  Timer? _typingTimer;
  final Set<String> _selectedMessageIds = {};
  static List<String> _quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  void _loadQuickEmojis() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('custom_quick_emojis');
      if (saved != null && saved.isNotEmpty) {
        if (mounted) {
          setState(() {
            _quickEmojis = List<String>.from(saved);
          });
        } else {
          _quickEmojis = List<String>.from(saved);
        }
      }
    } catch (_) {}
  }

  void _saveQuickEmoji(String emoji) async {
    if (!_quickEmojis.contains(emoji)) {
      _quickEmojis.insert(0, emoji);
      if (_quickEmojis.length > 6) {
        _quickEmojis = _quickEmojis.sublist(0, 6);
      }
    } else {
      _quickEmojis.remove(emoji);
      _quickEmojis.insert(0, emoji);
    }
    if (mounted) setState(() {});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('custom_quick_emojis', _quickEmojis);
    } catch (_) {}
  }

  bool _isBlocked = false;
  Message? _replyingTo;
  String? _highlightedMessageId;
  bool _isRecording = false;
  bool _isRecordingLocked = false;
  bool _isRecordingPaused = false;
  bool _isVoiceViewOnce = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  String? _recordingPath;
  Offset? _micDragStartOffset;
  DateTime? _micPressStartTime;
  final AudioRecorder _audioRecorder = AudioRecorder();
  Message? _pinnedMessage;

  final List<Map<String, dynamic>> _pendingMediaUploadQueue = [];
  Timer? _mediaUploadRetryTimer;

  void _startMediaRetryTimer() {
    _mediaUploadRetryTimer?.cancel();
    _mediaUploadRetryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_pendingMediaUploadQueue.isNotEmpty && mounted) {
        _processPendingMediaQueue();
      }
    });
  }

  Future<void> _processPendingMediaQueue() async {
    if (_pendingMediaUploadQueue.isEmpty) return;
    final itemsToProcess = List<Map<String, dynamic>>.from(_pendingMediaUploadQueue);
    for (final item in itemsToProcess) {
      if (!mounted) break;
      if (item['isUploading'] == true) continue; // Skip in-flight uploads to prevent duplicate sends
      item['isUploading'] = true;
      try {
        final apiService = ApiService();
        final file = item['file'] as File;
        final tempId = item['tempId'] as String;
        final caption = item['caption'] as String;
        final mediaType = item['mediaType'] as String;
        final isViewOnce = item['isViewOnce'] as bool;

        if (!file.existsSync()) {
          _pendingMediaUploadQueue.removeWhere((q) => q['tempId'] == tempId);
          continue;
        }

        final response = await apiService.uploadMedia(file.path);
        if (response != null && response['fileUrl'] != null && mounted) {
          _pendingMediaUploadQueue.removeWhere((q) => q['tempId'] == tempId);
          setState(() {
            _messages.removeWhere((m) => m.id == tempId);
          });
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          authProvider.socketService.sendMessage(
            widget.conversationId,
            caption,
            mediaUrl: response['fileUrl'],
            mediaType: mediaType,
            isViewOnce: isViewOnce,
          );
        } else {
          item['isUploading'] = false;
        }
      } catch (_) {
        item['isUploading'] = false;
      }
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingDuration = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted && !_isRecordingPaused) {
        setState(() {
          _recordingDuration++;
        });
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(1, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> _startVoiceRecording({bool locked = false}) async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        _recordingPath = path;
        await _audioRecorder.start(const RecordConfig(), path: path);
        _startRecordingTimer();
        if (mounted) {
          setState(() {
            _isRecording = true;
            _isRecordingLocked = locked;
            _isRecordingPaused = false;
            _isVoiceViewOnce = false;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
      }
    } catch (e) {
      debugPrint('Voice recording start error: $e');
    }
  }

  Future<void> _pauseOrResumeVoiceRecording() async {
    try {
      if (_isRecordingPaused) {
        await _audioRecorder.resume();
        if (mounted) setState(() => _isRecordingPaused = false);
      } else {
        await _audioRecorder.pause();
        if (mounted) setState(() => _isRecordingPaused = true);
      }
    } catch (e) {
      debugPrint('Voice pause/resume error: $e');
    }
  }

  Future<void> _cancelVoiceRecording() async {
    try {
      await _audioRecorder.stop();
      _stopRecordingTimer();
      if (_recordingPath != null) {
        try {
          final f = File(_recordingPath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Voice cancel error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isRecordingLocked = false;
          _isRecordingPaused = false;
          _recordingDuration = 0;
          _recordingPath = null;
        });
      }
    }
  }

  Future<void> _sendVoiceRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _stopRecordingTimer();
      final bool isViewOnce = _isVoiceViewOnce;
      final filePath = path ?? _recordingPath;

      if (mounted) {
        setState(() {
          _isRecording = false;
          _isRecordingLocked = false;
          _isRecordingPaused = false;
          _recordingDuration = 0;
          _recordingPath = null;
        });
      }

      if (filePath != null) {
        final audioFile = File(filePath);
        if (await audioFile.exists()) {
          await _uploadAndSendMedia(audioFile, 'AUDIO', isViewOnce: isViewOnce);
        }
      }
    } catch (e) {
      debugPrint('Voice send error: $e');
    }
  }

  void _scrollToMessage(String targetId) {
    final idx = _messages.indexWhere((m) => m.id == targetId || (m.parentMessage != null && (m.parentMessage!['id'] == targetId || m.parentMessage!['_id'] == targetId)));
    if (idx != -1) {
      _scrollController.animateTo(
        idx * 75.0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
      setState(() {
        _highlightedMessageId = targetId;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _highlightedMessageId == targetId) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Original message is no longer available')),
        );
      }
    }
  }

  String _getReplySenderName(Message msg) {
    final currentUserId = (Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? Provider.of<AuthProvider>(context, listen: false).user?['_id'])?.toString();
    final senderMap = msg.sender;
    final senderId = (msg.senderId.isNotEmpty ? msg.senderId : (senderMap != null ? (senderMap['id'] ?? senderMap['_id']) : null))?.toString();
    if (senderId == currentUserId) {
      return 'You';
    }
    if (senderMap != null && senderMap['username'] != null && senderMap['username'].toString().isNotEmpty) {
      return senderMap['username'].toString();
    }
    return widget.chatName;
  }

  String _getReplyPreviewText(Message msg) {
    if (msg.isDeleted || msg.content == 'This message was deleted') {
      return 'This message was deleted';
    }
    if (msg.mediaType == 'CALL_LOG') {
      final text = msg.content;
      if (text.toLowerCase().contains('missed')) {
        return '📞 Missed call';
      } else if (text.toLowerCase().contains('declined')) {
        return '📞 Declined call';
      } else if (msg.mediaUrl == 'VIDEO_CALL' || text.toLowerCase().contains('video')) {
        return '🎥 Video call';
      } else {
        return '📞 Voice call';
      }
    }
    if (msg.mediaType == 'IMAGE') return '📷 Photo';
    if (msg.mediaType == 'VIDEO') return '🎥 Video';
    if (msg.mediaType == 'AUDIO') return '🎵 Voice message';
    if (msg.mediaType == 'LOCATION' || msg.latitude != null) return '📍 Location';
    if (msg.mediaType == 'POLL') return '📊 Poll';
    if (msg.mediaType == 'DOCUMENT' || msg.mediaType == 'FILE') return '📄 Document';
    if (msg.mediaType == 'STICKER') return '😊 Sticker';

    return msg.content.isNotEmpty ? msg.content : 'Message';
  }

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

  void _showAskAiChatContextModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        String answer = "Analyzing chat context...";
        final queryCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF3B82F6)]),
                        ),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text('Ask AI About "${widget.chatName}"', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      answer == "Analyzing chat context..."
                          ? "🤖 AI is reading conversation transcript & summarizing..."
                          : answer,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: queryCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'e.g. What did we decide? What tasks are pending?',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: Color(0xFFEC4899)),
                        onPressed: () async {
                          final text = queryCtrl.text.trim();
                          if (text.isEmpty) return;
                          queryCtrl.clear();
                          setModalState(() => answer = "AI is thinking...");
                          try {
                            final authProvider = Provider.of<AuthProvider>(context, listen: false);
                            final response = await http.post(
                              Uri.parse('${ApiService.baseUrl}/ai/chat-context'),
                              headers: {
                                'Content-Type': 'application/json',
                                if (authProvider.token != null) 'Authorization': 'Bearer ${authProvider.token}',
                              },
                              body: jsonEncode({'conversationId': widget.conversationId, 'query': text}),
                            );
                            if (response.statusCode == 200) {
                              final data = jsonDecode(response.body);
                              setModalState(() => answer = data['reply'] ?? 'Summary ready.');
                            } else {
                              setModalState(() => answer = 'Failed to analyze chat context.');
                            }
                          } catch (_) {
                            setModalState(() => answer = 'Error connecting to AI service.');
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            );
          },
        );
      },
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
    _loadQuickEmojis();
    
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
    authProvider.socketService.onMessageEdited(_handleMessageEdited);
    authProvider.socketService.onMessagesRead(_handleMessagesRead);
    authProvider.socketService.onMessagesDelivered(_handleMessagesDelivered);
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

    // Scheduled Messages real-time sync
    _loadScheduledMessages();
    socket?.on('scheduled_messages_updated', (data) {
      if (mounted && data != null && data['conversationId'] == widget.conversationId) {
        setState(() {
          _scheduledMessages = List<Map<String, dynamic>>.from(data['scheduledMessages'] ?? []);
          _scheduledMessages.sort((a, b) => (a['scheduledFor'] as int).compareTo(b['scheduledFor'] as int));
        });
      }
    });
    socket?.on('scheduled_message_executed', (data) {
      if (mounted && data != null && data['conversationId'] == widget.conversationId) {
        setState(() {
          _scheduledMessages.removeWhere((m) => m['id'] == data['id']);
        });
      }
    });

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
    final socket = authProvider.socketService.socket;
    socket?.off('scheduled_messages_updated');
    socket?.off('scheduled_message_executed');
    authProvider.socketService.leaveConversation(widget.conversationId);
    authProvider.socketService.offMessageReceived(_handleIncomingMessage);
    authProvider.socketService.offEncryptedMessageReceived(_handleEncryptedMessage);
    authProvider.socketService.offTypingChange(_handleTypingChange);
    authProvider.socketService.offStatusChange(_handleStatusChange);
    authProvider.socketService.offChatCleared(_handleChatCleared);
    authProvider.socketService.offMessageDeleted(_handleMessageDeleted);
    authProvider.socketService.offMessageEdited(_handleMessageEdited);
    authProvider.socketService.offMessagesRead(_handleMessagesRead);
    authProvider.socketService.offMessagesDelivered(_handleMessagesDelivered);
    authProvider.socketService.offProfileUpdated(_handleProfileUpdated);
    authProvider.socketService.offReactionAdded(_handleReactionAdded);
    authProvider.socketService.offReactionRemoved(_handleReactionRemoved);
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _mediaUploadRetryTimer?.cancel();
    _cacheDebounceTimer?.cancel();
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
      final readUserId = data['userId'];
      if (readUserId == null) return;
      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          final msg = _messages[i];
          if (msg.senderId != readUserId) {
            final receiptsList = List<dynamic>.from(msg.receipts ?? []);
            if (!receiptsList.any((r) => r['userId'] == readUserId && r['status'] == 'READ')) {
              receiptsList.add({'userId': readUserId, 'status': 'READ'});
              _messages[i] = Message(
                id: msg.id,
                content: msg.content,
                senderId: msg.senderId,
                conversationId: msg.conversationId,
                parentMessageId: msg.parentMessageId,
                isEdited: msg.isEdited,
                isDeleted: msg.isDeleted,
                isForwarded: msg.isForwarded,
                mediaUrl: msg.mediaUrl,
                mediaType: msg.mediaType,
                isViewOnce: msg.isViewOnce,
                isViewed: msg.isViewed,
                latitude: msg.latitude,
                longitude: msg.longitude,
                locationTitle: msg.locationTitle,
                isLiveLocation: msg.isLiveLocation,
                liveExpiresAt: msg.liveExpiresAt,
                isLiveEnded: msg.isLiveEnded,
                receipts: receiptsList,
                reactions: msg.reactions,
                createdAt: msg.createdAt,
                parentMessage: msg.parentMessage,
                sender: msg.sender,
                isPending: msg.isPending,
                isPinned: msg.isPinned,
              );
            }
          }
        }
      });
    }
  }

  void _handleMessagesDelivered(dynamic data) {
    if (!mounted || data == null) return;
    if (data['conversationId'] == widget.conversationId) {
      final deliveredUserId = data['userId'];
      final List<dynamic> messageIds = data['messageIds'] != null ? List<dynamic>.from(data['messageIds']) : [];
      if (deliveredUserId == null) return;
      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          final msg = _messages[i];
          if (messageIds.isEmpty || messageIds.contains(msg.id)) {
            if (msg.senderId != deliveredUserId) {
              final receiptsList = List<dynamic>.from(msg.receipts ?? []);
              final existingIdx = receiptsList.indexWhere((r) => r['userId'] == deliveredUserId);
              if (existingIdx != -1) {
                if (receiptsList[existingIdx]['status'] != 'READ') {
                  receiptsList[existingIdx] = {'userId': deliveredUserId, 'status': 'DELIVERED'};
                }
              } else {
                receiptsList.add({'userId': deliveredUserId, 'status': 'DELIVERED'});
              }
              _messages[i] = Message(
                id: msg.id,
                content: msg.content,
                senderId: msg.senderId,
                conversationId: msg.conversationId,
                parentMessageId: msg.parentMessageId,
                isEdited: msg.isEdited,
                isDeleted: msg.isDeleted,
                isForwarded: msg.isForwarded,
                mediaUrl: msg.mediaUrl,
                mediaType: msg.mediaType,
                isViewOnce: msg.isViewOnce,
                isViewed: msg.isViewed,
                latitude: msg.latitude,
                longitude: msg.longitude,
                locationTitle: msg.locationTitle,
                isLiveLocation: msg.isLiveLocation,
                liveExpiresAt: msg.liveExpiresAt,
                isLiveEnded: msg.isLiveEnded,
                receipts: receiptsList,
                reactions: msg.reactions,
                createdAt: msg.createdAt,
                parentMessage: msg.parentMessage,
                sender: msg.sender,
                isPending: false,
                isPinned: msg.isPinned,
              );
            }
          }
        }
      });
      _updateMessageCache();
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
        final msg = Message.fromJson(data['message']);
        setState(() {
          // Deduplicate: replace optimistic temp message (text or media)
          final tempIndex = _messages.indexWhere((m) {
            if (m.id == msg.id) return true;
            if (m.id.startsWith('temp')) {
              // Media message match by URL or filename
              if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
                final filename = msg.mediaUrl!.split('/').last;
                if (m.mediaUrl == msg.mediaUrl || (m.mediaUrl != null && m.mediaUrl!.contains(filename))) {
                  return true;
                }
              }
              // Text message match by content and sender
              if (msg.content.isNotEmpty && m.content == msg.content && m.senderId == msg.senderId) {
                return true;
              }
            }
            return false;
          });

          if (tempIndex != -1) {
            _messages[tempIndex] = msg;
          } else if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
          }
        });
        _scrollToBottom();
        _updateMessageCache();
        
        // Auto-download media according to storage settings
        AutoDownloadService.checkAndAutoDownload(msg);

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

        // Replace temp optimistic message if content or media matches
        setState(() {
          final tempIndex = _messages.indexWhere((m) {
            if (m.id == msg.id) return true;
            if (m.id.startsWith('temp')) {
              if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
                final filename = msg.mediaUrl!.split('/').last;
                if (m.mediaUrl == msg.mediaUrl || (m.mediaUrl != null && m.mediaUrl!.contains(filename))) {
                  return true;
                }
              }
              if (msg.content.isNotEmpty && m.content == msg.content && m.senderId == msg.senderId) {
                return true;
              }
            }
            return false;
          });

          if (tempIndex != -1) {
            _messages[tempIndex] = msg;
          } else if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
          }
        });
        _scrollToBottom();
        _updateMessageCache();

        // Auto-download media according to storage settings
        AutoDownloadService.checkAndAutoDownload(msg);

        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.socketService.socket?.emit('mark_read', {
          'conversationId': widget.conversationId,
        });
      } catch (e) {
        print('Error handling encrypted message: $e');
      }
    }
  }

  Timer? _cacheDebounceTimer;

  void _updateMessageCache() {
    _cacheDebounceTimer?.cancel();
    _cacheDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final encoded = jsonEncode(_messages.map((m) => m.toJson()).toList());
        await prefs.setString('cached_messages_${widget.conversationId}', encoded);
      } catch (e) {
        print('Error updating message cache: $e');
      }
    });
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
    if (mounted && data != null) {
      final String convId = (data['conversationId'] ?? '').toString();
      if (convId.isNotEmpty && convId != widget.conversationId) return;

      final String msgId = (data['messageId'] ?? '').toString();
      if (msgId.isEmpty) return;

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

  void _handleMessageEdited(dynamic data) {
    if (mounted && data != null) {
      try {
        final Map<String, dynamic> rawMsg = data['message'] != null ? Map<String, dynamic>.from(data['message']) : Map<String, dynamic>.from(data);
        final String convId = (data['conversationId'] ?? rawMsg['conversationId'] ?? '').toString();
        if (convId.isNotEmpty && convId != widget.conversationId) return;

        final editedMsg = Message.fromJson(rawMsg);
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == editedMsg.id);
          if (idx != -1) {
            _messages[idx] = Message(
              id: editedMsg.id,
              content: editedMsg.content,
              senderId: editedMsg.senderId,
              conversationId: editedMsg.conversationId,
              createdAt: _messages[idx].createdAt,
              mediaUrl: editedMsg.mediaUrl ?? _messages[idx].mediaUrl,
              mediaType: editedMsg.mediaType ?? _messages[idx].mediaType,
              isEdited: true,
              sender: editedMsg.sender ?? _messages[idx].sender,
              parentMessage: editedMsg.parentMessage ?? _messages[idx].parentMessage,
              receipts: _messages[idx].receipts,
              reactions: _messages[idx].reactions,
            );
          }
        });
        _updateMessageCache();
      } catch (e) {
        debugPrint('Error handling message edited: $e');
      }
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

        final bool wasEmpty = _messages.isEmpty;
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
            // Check auto-downloads for recent media
            for (final msg in _messages.reversed.take(10)) {
              if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
                AutoDownloadService.checkAndAutoDownload(msg);
              }
            }
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
    final diffInMinutes = DateTime.now().toUtc().difference(message.createdAt.toUtc()).inMinutes.abs();
    if (diffInMinutes > 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Messages can only be edited within 15 minutes of sending.')),
      );
      return;
    }

    setState(() {
      _editingMessage = message;
      _activeScheduledTime = null;
      _replyingTo = null;
      _selectedMessageIds.clear();
      _messageController.text = message.content;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    });
    _focusNode.requestFocus();
  }

  void _showMessageOptions(Message message, bool isMe) {
    final isWithinTimeLimit = DateTime.now().toUtc().difference(message.createdAt.toUtc()).inMinutes.abs() <= 15;
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
                    final fullUrl = ApiService.getMediaUrl(message.mediaUrl!);
                    final response = await http.get(Uri.parse(fullUrl));
                    final tempDir = await getTemporaryDirectory();
                    final ext = message.mediaType == 'VIDEO' ? 'mp4' : 'jpg';
                    final tempFile = File('${tempDir.path}/dolsyx_${DateTime.now().millisecondsSinceEpoch}.$ext');
                    await tempFile.writeAsBytes(response.bodyBytes);
                    
                    bool hasAccess = await Gal.hasAccess();
                    if (!hasAccess) {
                      hasAccess = await Gal.requestAccess();
                    }

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
                    debugPrint('Gallery save error: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Saved to Gallery!')),
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
              leading: const Icon(Icons.reply, color: Colors.blueAccent),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _replyingTo = message;
                });
                _focusNode.requestFocus();
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
    setState(() {
      _selectedMessageIds.clear();
      if (!_quickEmojis.contains(emoji)) {
        _quickEmojis.insert(0, emoji);
        if (_quickEmojis.length > 6) {
          _quickEmojis = _quickEmojis.sublist(0, 6);
        }
      }
    });
    
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

  Widget _buildQuickReactionPicker(Message message, bool isMe) {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).user;
    String? userReaction;
    if (message.reactions != null && currentUser != null) {
      final myUserId = currentUser['id'] ?? currentUser['_id'];
      for (final r in message.reactions!) {
        if (r is Map && r['userId'] == myUserId) {
          userReaction = r['emoji']?.toString();
          break;
        }
      }
    }

    final List<String> quickEmojis = List<String>.from(_quickEmojis);
    if (userReaction != null && userReaction.isNotEmpty && !quickEmojis.contains(userReaction)) {
      if (quickEmojis.length >= 6) {
        quickEmojis[5] = userReaction;
      } else {
        quickEmojis.add(userReaction);
      }
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            left: isMe ? 40 : 16,
            right: isMe ? 16 : 40,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 1,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...quickEmojis.map((emoji) {
                final bool isSelectedEmoji = userReaction == emoji;
                return GestureDetector(
                  onTap: () {
                    _reactToMessage(message.id, emoji);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelectedEmoji
                          ? AppTheme.primaryColor.withOpacity(0.25)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      emoji,
                      style: TextStyle(
                        fontSize: isSelectedEmoji ? 26 : 22,
                      ),
                    ),
                  ),
                );
              }),
              Container(
                height: 18,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              GestureDetector(
                onTap: () {
                  final msgId = message.id;
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: AppTheme.surfaceColor,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (context) => SizedBox(
                      height: 350,
                      child: Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            height: 4,
                            width: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.textSecondary.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'React with Any Emoji',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Expanded(
                            child: EmojiPicker(
                              onEmojiSelected: (category, emoji) {
                                Navigator.pop(context);
                                _reactToMessage(msgId, emoji.emoji);
                              },
                              config: Config(
                                checkPlatformCompatibility: true,
                                emojiViewConfig: EmojiViewConfig(
                                  backgroundColor: AppTheme.surfaceColor,
                                  columns: 7,
                                  emojiSizeMax: 28 * (Platform.isIOS ? 1.30 : 1.0),
                                ),
                                categoryViewConfig: CategoryViewConfig(
                                  backgroundColor: AppTheme.surfaceColor,
                                  indicatorColor: AppTheme.primaryColor,
                                  iconColorSelected: AppTheme.primaryColor,
                                  iconColor: AppTheme.textSecondary,
                                ),
                                bottomActionBarConfig: BottomActionBarConfig(
                                  showSearchViewButton: true,
                                  backgroundColor: AppTheme.surfaceColor,
                                ),
                                searchViewConfig: SearchViewConfig(
                                  backgroundColor: AppTheme.surfaceColor,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

    if (_editingMessage != null) {
      final msgToEdit = _editingMessage!;
      _messageController.clear();
      setState(() {
        _editingMessage = null;
      });

      if (text != msgToEdit.content) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.socketService.socket?.emit('edit_message', {
          'messageId': msgToEdit.id,
          'content': text,
        });
        _chatService.editMessage(msgToEdit.id, text);
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == msgToEdit.id);
            if (idx != -1) {
              _messages[idx] = Message(
                id: msgToEdit.id,
                content: text,
                senderId: msgToEdit.senderId,
                conversationId: msgToEdit.conversationId,
                createdAt: msgToEdit.createdAt,
                isEdited: true,
                mediaType: msgToEdit.mediaType,
                mediaUrl: msgToEdit.mediaUrl,
                reactions: _messages[idx].reactions,
              );
            }
          });
        }
      }
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final replying = _replyingTo;

    // 1. Immediately clear input field and dismiss reply preview
    _messageController.clear();
    setState(() {
      _replyingTo = null;
    });

    if (_isTyping) {
      _isTyping = false;
      authProvider.socketService.emitTyping(widget.conversationId, false);
      _typingTimer?.cancel();
    }

    // 2. Instant Optimistic UI render (0ms on-screen feedback)
    final authUser = authProvider.user;
    final newMsg = Message(
      id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      content: text,
      senderId: authUser?['id'] ?? authUser?['_id'] ?? '',
      conversationId: widget.conversationId,
      createdAt: DateTime.now(),
      isPending: authProvider.socketService.socket?.connected != true,
      parentMessage: replying != null ? {
        'id': replying.id,
        'content': replying.content,
        'sender': replying.sender ?? {'username': _getReplySenderName(replying)},
        'mediaType': replying.mediaType,
        'isDeleted': replying.isDeleted,
      } : null,
    );
    setState(() {
      _messages.add(newMsg);
    });
    _scrollToBottom(animate: true);

    // 3. Instant Socket Transmission (sub-0.2ms zero-lag single pipeline)
    final isDirectMessage = widget.remoteUser != null;
    final remoteEmail = widget.remoteUser?['email'] as String?;
    if (isDirectMessage && remoteEmail != null && authProvider.token != null) {
      authProvider.socketService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        recipientEmail: remoteEmail,
        plaintext: text,
        token: authProvider.token!,
        myUserId: authProvider.user?['id'] ?? '',
        parentMessageId: replying?.id,
      ).catchError((err) {
        authProvider.socketService.sendMessage(
          widget.conversationId,
          text,
          parentMessageId: replying?.id,
        );
      });
    } else {
      authProvider.socketService.sendMessage(
        widget.conversationId,
        text,
        parentMessageId: replying?.id,
      );
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



  Future<void> _pickAudio() async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.audio,
      );
      if (!mounted) return;
      if (result != null && result.files.isNotEmpty) {
        final entries = result.files
            .where((f) => f.path != null)
            .map((f) => MapEntry(File(f.path!), 'AUDIO'))
            .toList();
        await _uploadAndSendMultipleMedia(entries);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking audio: $e')));
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
          else if (['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'].contains(ext)) type = 'VIDEO';
          else if (['mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'].contains(ext)) type = 'AUDIO';
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

  void _showCameraOptions() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WhatsAppMediaPickerScreen(
          onSend: (selectedList, caption, isViewOnce, isHD) {
            final entries = selectedList.map((m) => MapEntry(m.file, m.type)).toList();
            if (entries.length == 1) {
              _uploadAndSendMedia(entries.first.key, entries.first.value, caption: caption, isViewOnce: isViewOnce, isHD: isHD);
            } else {
              _uploadAndSendMultipleMedia(entries, caption: caption, isViewOnce: isViewOnce, isHD: isHD);
            }
          },
        ),
      ),
    );
  }

  Future<void> _captureCameraMedia({bool isVideo = false}) async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      final picker = ImagePicker();
      final XFile? file = isVideo
          ? await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 5))
          : await picker.pickImage(source: ImageSource.camera, imageQuality: 95);

      if (file != null && mounted) {
        final item = MediaItem(file: File(file.path), type: isVideo ? 'VIDEO' : 'IMAGE');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WhatsAppMediaPreviewScreen(
              initialItems: [item],
              onSend: (selectedList, caption, isViewOnce, isHD) {
                final entries = selectedList.map((m) => MapEntry(m.file, m.type)).toList();
                if (entries.length == 1) {
                  _uploadAndSendMedia(entries.first.key, entries.first.value, caption: caption, isViewOnce: isViewOnce, isHD: isHD);
                } else {
                  _uploadAndSendMultipleMedia(entries, caption: caption, isViewOnce: isViewOnce, isHD: isHD);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error opening camera: $e')));
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
  }

  Future<void> _pickGalleryMedia() async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      final picker = ImagePicker();
      List<XFile> pickedFiles = [];
      try {
        pickedFiles = await picker.pickMultipleMedia();
      } catch (_) {
        try {
          pickedFiles = await picker.pickMultiImage();
        } catch (_) {
          final XFile? single = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
          if (single != null) pickedFiles = [single];
        }
      }

      if (!mounted || pickedFiles.isEmpty) return;

      final items = pickedFiles.map((f) {
        final ext = f.path.split('.').last.toLowerCase();
        final isVid = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'flv', 'm4v'].contains(ext);
        return MediaItem(file: File(f.path), type: isVid ? 'VIDEO' : 'IMAGE');
      }).toList();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WhatsAppMediaPreviewScreen(
            initialItems: items,
            onSend: (selectedList, caption, isViewOnce, isHD) {
              final entries = selectedList.map((m) => MapEntry(m.file, m.type)).toList();
              if (entries.length == 1) {
                _uploadAndSendMedia(entries.first.key, entries.first.value, caption: caption, isViewOnce: isViewOnce, isHD: isHD);
              } else {
                _uploadAndSendMultipleMedia(entries, caption: caption, isViewOnce: isViewOnce, isHD: isHD);
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking gallery media: $e')));
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
  }

  Future<void> _uploadAndSendMedia(File file, String mediaType, {String caption = '', bool isViewOnce = false, bool isHD = false, bool showLoadingState = false}) async {
    if (!mounted) return;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_${file.path.hashCode}';
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final myUserId = (authProvider.user?['id'] ?? authProvider.user?['_id'])?.toString() ?? '';

    // 🟢 Instantly show the media bubble in chat with WhatsApp-style buffering overlay
    final tempMsg = Message(
      id: tempId,
      content: caption,
      senderId: myUserId,
      conversationId: widget.conversationId,
      mediaUrl: file.path,
      mediaType: mediaType,
      isViewOnce: isViewOnce,
      isPending: true,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(tempMsg);
    });
    _scrollToBottom();

    // 🟢 Queue for reliable background upload & retry without error popups
    final queueItem = <String, dynamic>{
      'tempId': tempId,
      'file': file,
      'mediaType': mediaType,
      'caption': caption,
      'isViewOnce': isViewOnce,
      'isHD': isHD,
      'isUploading': true,
    };
    _pendingMediaUploadQueue.add(queueItem);
    _startMediaRetryTimer();

    try {
      final apiService = ApiService();
      final response = await apiService.uploadMedia(file.path);
      if (response != null && response['fileUrl'] != null && mounted) {
        _pendingMediaUploadQueue.removeWhere((q) => q['tempId'] == tempId);
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            _messages[idx] = Message(
              id: tempId,
              content: caption,
              senderId: myUserId,
              conversationId: widget.conversationId,
              mediaUrl: response['fileUrl'],
              mediaType: mediaType,
              isViewOnce: isViewOnce,
              isPending: false,
              createdAt: _messages[idx].createdAt,
            );
          }
        });
        authProvider.socketService.sendMessage(
          widget.conversationId, 
          caption, 
          mediaUrl: response['fileUrl'], 
          mediaType: mediaType,
          isViewOnce: isViewOnce,
        );
      } else {
        queueItem['isUploading'] = false;
      }
    } catch (_) {
      queueItem['isUploading'] = false;
    }
  }

  Future<void> _uploadAndSendMultipleMedia(List<MapEntry<File, String>> files, {String caption = '', bool isViewOnce = false, bool isHD = false}) async {
    if (!mounted || files.isEmpty) return;
    
    // Concurrently upload all selected media files without locking the UI
    final futures = <Future>[];
    for (int i = 0; i < files.length; i++) {
      final entry = files[i];
      futures.add(
        _uploadAndSendMedia(
          entry.key, 
          entry.value, 
          caption: i == 0 ? caption : '', 
          isViewOnce: isViewOnce,
          isHD: isHD,
          showLoadingState: false,
        ),
      );
    }
    await Future.wait(futures);
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
                _buildAttachGridItem(sheetContext, 'Audio', Icons.headphones_rounded, const Color(0xFFFF6D00), _pickAudio),
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

  List<Map<String, dynamic>> _scheduledMessages = [];

  void _loadScheduledMessages() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.socketService.socket?.emit('get_scheduled_messages', {
      'conversationId': widget.conversationId,
    });
  }

  void _showScheduleMessageModal() async {
    final DateTime now = DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _activeScheduledTime ?? now.add(const Duration(minutes: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: _activeScheduledTime != null 
          ? TimeOfDay.fromDateTime(_activeScheduledTime!)
          : TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30))),
    );
    if (pickedTime == null) return;

    final scheduledDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (scheduledDateTime.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose a future date and time.')),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _activeScheduledTime = scheduledDateTime;
      });
      _focusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1E293B),
          content: Row(
            children: [
              const Icon(Icons.schedule, color: Color(0xFFFF9800), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Schedule mode active: ${DateFormat('EEE, MMM d @ h:mm a').format(scheduledDateTime)}. Type your message below and tap the clock icon.',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _sendScheduledMessageDirectly() {
    if (_activeScheduledTime == null) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message to schedule')),
      );
      _focusNode.requestFocus();
      return;
    }

    final scheduledDateTime = _activeScheduledTime!;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socket = authProvider.socketService.socket;

    _messageController.clear();
    setState(() {
      _activeScheduledTime = null;
    });

    final scheduledMsg = {
      'id': 'sched_${DateTime.now().millisecondsSinceEpoch}',
      'conversationId': widget.conversationId,
      'content': text,
      'scheduledFor': scheduledDateTime.millisecondsSinceEpoch,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };

    // Optimistic local add
    setState(() {
      _scheduledMessages.add(scheduledMsg);
      _scheduledMessages.sort((a, b) => (a['scheduledFor'] as int).compareTo(b['scheduledFor'] as int));
    });

    // Server persistent emit (works even when app is closed or offline)
    socket?.emit('schedule_message', {
      'conversationId': widget.conversationId,
      'content': text,
      'scheduledFor': scheduledDateTime.millisecondsSinceEpoch,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFFFF9800), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Message scheduled for ${DateFormat('MMM d @ h:mm a').format(scheduledDateTime)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduledMessagesBar() {
    if (_scheduledMessages.isEmpty) return const SizedBox.shrink();
    final firstSched = _scheduledMessages.first;
    final scheduledDate = DateTime.fromMillisecondsSinceEpoch(firstSched['scheduledFor'] as int);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_scheduledMessages.length} Scheduled Message${_scheduledMessages.length > 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Next: ${DateFormat('h:mm a, MMM d').format(scheduledDate)}',
                  style: TextStyle(color: Colors.orange.withValues(alpha: 0.9), fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              backgroundColor: Colors.orange.withValues(alpha: 0.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _showScheduledMessagesManagerModal,
            child: const Text('Manage', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showScheduledMessagesManagerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Scheduled Messages (${_scheduledMessages.length})',
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_scheduledMessages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No pending scheduled messages', style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _scheduledMessages.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                      itemBuilder: (context, index) {
                        final msg = _scheduledMessages[index];
                        final time = DateTime.fromMillisecondsSinceEpoch(msg['scheduledFor'] as int);
                        final authProvider = Provider.of<AuthProvider>(context, listen: false);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF332005),
                            child: Icon(Icons.access_time_rounded, color: Colors.orange, size: 22),
                          ),
                          title: Text(msg['content'] ?? '', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(DateFormat('EEE, MMM d @ h:mm a').format(time), style: const TextStyle(color: Colors.orange, fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Send Now',
                                icon: const Icon(Icons.send_rounded, color: Colors.green, size: 20),
                                onPressed: () {
                                  authProvider.socketService.socket?.emit('send_scheduled_message_now', {'id': msg['id']});
                                  setModalState(() {
                                    _scheduledMessages.removeAt(index);
                                  });
                                  setState(() {});
                                  if (_scheduledMessages.isEmpty) Navigator.pop(ctx);
                                },
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                onPressed: () {
                                  authProvider.socketService.socket?.emit('cancel_scheduled_message', {
                                    'id': msg['id'],
                                    'conversationId': widget.conversationId,
                                  });
                                  setModalState(() {
                                    _scheduledMessages.removeAt(index);
                                  });
                                  setState(() {});
                                  if (_scheduledMessages.isEmpty) Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
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

  void _scrollToBottom({bool animate = false}) {
    void scrollAction() {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (target <= 0) return;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollAction();
      Future.delayed(const Duration(milliseconds: 60), scrollAction);
      Future.delayed(const Duration(milliseconds: 180), scrollAction);
    });
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
    final themeProvider = Provider.of<ThemeProvider>(context);

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
                if (_selectedMessageIds.length == 1)
                  Builder(
                    builder: (context) {
                      final myId = currentUser?['id'] ?? currentUser?['_id'];
                      final selectedMsg = _messages.firstWhere((m) => m.id == _selectedMessageIds.first, orElse: () => _messages.first);
                      final isMine = selectedMsg.senderId == myId || (selectedMsg.sender != null && (selectedMsg.sender!['id'] == myId || selectedMsg.sender!['_id'] == myId));
                      final isTextOnly = selectedMsg.mediaUrl == null;
                      final isRecent = DateTime.now().toUtc().difference(selectedMsg.createdAt.toUtc()).inMinutes.abs() <= 15;
                      if (isMine && isTextOnly && isRecent) {
                        return IconButton(
                          icon: const Icon(Icons.edit_rounded),
                          tooltip: 'Edit Message',
                          onPressed: () {
                            setState(() => _selectedMessageIds.clear());
                            _editMessageDialog(selectedMsg);
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'edit') {
                      if (_selectedMessageIds.length == 1) {
                        final selectedMsg = _messages.firstWhere((m) => m.id == _selectedMessageIds.first);
                        setState(() => _selectedMessageIds.clear());
                        _editMessageDialog(selectedMsg);
                      }
                    } else if (value == 'copy') {
                      final selectedMsgs = _messages.where((m) => _selectedMessageIds.contains(m.id)).toList();
                      final copiedText = selectedMsgs.map((m) => m.content).join('\n');
                      Clipboard.setData(ClipboardData(text: copiedText));
                      setState(() => _selectedMessageIds.clear());
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${selectedMsgs.length} message(s) to clipboard')),
                      );
                    } else if (value == 'pin') {
                      _pinSelectedMessages();
                    }
                  },
                  itemBuilder: (context) {
                    final myId = currentUser?['id'] ?? currentUser?['_id'];
                    final bool canEdit = _selectedMessageIds.length == 1 &&
                        _messages.any((m) => m.id == _selectedMessageIds.first && (m.senderId == myId || (m.sender != null && (m.sender!['id'] == myId || m.sender!['_id'] == myId))));
                    return [
                      if (canEdit)
                        const PopupMenuItem<String>(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 20),
                              SizedBox(width: 12),
                              Text('Edit'),
                            ],
                          ),
                        ),
                      const PopupMenuItem<String>(
                        value: 'copy',
                        child: Row(
                          children: [
                            Icon(Icons.content_copy, size: 20),
                            SizedBox(width: 12),
                            Text('Copy'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'pin',
                        child: Row(
                          children: [
                            Icon(Icons.push_pin_outlined, size: 20),
                            SizedBox(width: 12),
                            Text('Pin'),
                          ],
                        ),
                      ),
                    ];
                  },
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
                                final fullUrl = ApiService.getMediaUrl(selectedMsg.mediaUrl!);
                                final response = await http.get(Uri.parse(fullUrl));
                                final tempDir = await getTemporaryDirectory();
                                final ext = selectedMsg.mediaType == 'VIDEO' ? 'mp4' : 'jpg';
                                final tempFile = File('${tempDir.path}/dolsyx_${DateTime.now().millisecondsSinceEpoch}.$ext');
                                await tempFile.writeAsBytes(response.bodyBytes);
                                
                                bool hasAccess = await Gal.hasAccess();
                                if (!hasAccess) {
                                  hasAccess = await Gal.requestAccess();
                                }

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
                                debugPrint('Popup download error: $e');
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
                    } else if (value == 'ask_ai_chat') {
                      _showAskAiChatContextModal();
                    } else if (value == 'wallpaper') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => WallpaperSettingsScreen(conversationId: widget.conversationId)));
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'ask_ai_chat',
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 20, color: Color(0xFFEC4899)),
                          SizedBox(width: 12),
                          Text('Ask AI About This Chat', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
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
      body: Stack(
        children: [
          if (wallpaperDecoration != null)
            Positioned.fill(
              child: Opacity(
                opacity: (wallpaperConfig.opacity * themeProvider.wallpaperOpacity).clamp(0.0, 1.0),
                child: (wallpaperConfig.blur > 0.0 || themeProvider.wallpaperBlur > 0.0)
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: wallpaperConfig.blur > 0.0 ? wallpaperConfig.blur : themeProvider.wallpaperBlur,
                          sigmaY: wallpaperConfig.blur > 0.0 ? wallpaperConfig.blur : themeProvider.wallpaperBlur,
                        ),
                        child: Container(
                          decoration: wallpaperDecoration,
                        ),
                      )
                    : Container(
                        decoration: wallpaperDecoration,
                      ),
              ),
            ),
          Column(
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
                    cacheExtent: 500.0,
                    addAutomaticKeepAlives: true,
                    addRepaintBoundaries: true,
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
                          if (isSelected && _selectedMessageIds.length == 1)
                            _buildQuickReactionPicker(message, isMe),
                          GestureDetector(
                            key: ValueKey(message.id),
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
                                color: isSelected 
                                    ? AppTheme.primaryColor.withAlpha(50) 
                                    : (_highlightedMessageId == message.id ? AppTheme.primaryColor.withAlpha(90) : Colors.transparent),
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
                                  onTapReplyReference: (targetId) {
                                    _scrollToMessage(targetId);
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
          _buildScheduledMessagesBar(),
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
                          _getReplySenderName(_replyingTo!),
                          style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getReplyPreviewText(_replyingTo!),
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
          if (_editingMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_rounded, color: AppTheme.primaryColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Editing Message', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          _editingMessage!.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _editingMessage = null;
                        _messageController.clear();
                      });
                    },
                    child: Icon(Icons.close, color: AppTheme.primaryColor, size: 18),
                  ),
                ],
              ),
            ),
          if (_activeScheduledTime != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: AppTheme.primaryColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scheduling for: ${DateFormat('EEE, MMM d, yyyy @ hh:mm a').format(_activeScheduledTime!)}',
                      style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showScheduleMessageModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Change', style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _activeScheduledTime = null),
                    child: Icon(Icons.close, color: AppTheme.primaryColor, size: 18),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            bottom: true,
            child: Container(
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                top: 8,
                bottom: MediaQuery.paddingOf(context).bottom > 0 ? (MediaQuery.paddingOf(context).bottom + 16) : 14,
              ),
              color: Colors.transparent,
              child: _isRecording || _isRecordingLocked
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Top Row: Timer, Waveform visualizer, View-Once toggle
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _isRecordingPaused ? Colors.grey : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDuration(_recordingDuration),
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Waveform visualizer bars
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(14, (i) {
                                  final heights = [10.0, 16.0, 22.0, 14.0, 28.0, 18.0, 24.0, 12.0, 20.0, 15.0, 26.0, 14.0, 18.0, 10.0];
                                  final h = _isRecordingPaused ? 6.0 : heights[i % heights.length];
                                  return Container(
                                    width: 3,
                                    height: h,
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: _isRecordingPaused ? AppTheme.textSecondary : AppTheme.primaryColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // View Once (1) Button
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isVoiceViewOnce = !_isVoiceViewOnce;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_isVoiceViewOnce ? 'Voice message set to view once' : 'View once turned off'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isVoiceViewOnce ? AppTheme.primaryColor : AppTheme.textSecondary,
                                    width: 2,
                                  ),
                                  color: _isVoiceViewOnce ? AppTheme.primaryColor.withOpacity(0.25) : Colors.transparent,
                                ),
                                child: Center(
                                  child: Text(
                                    '1',
                                    style: TextStyle(
                                      color: _isVoiceViewOnce ? AppTheme.primaryColor : AppTheme.textSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Bottom Row: Trash icon, Pause/Resume capsule, Send button
                        Row(
                          children: [
                            // Delete / Trash button
                            GestureDetector(
                              onTap: _cancelVoiceRecording,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2E141D),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF4B60), size: 22),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Center Pause / Resume Pill
                            Expanded(
                              child: GestureDetector(
                                onTap: _pauseOrResumeVoiceRecording,
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppTheme.backgroundColor,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isRecordingPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                        color: AppTheme.textPrimary,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isRecordingPaused ? 'Resume' : 'Pause',
                                        style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Send Action Button
                            GestureDetector(
                              onTap: _sendVoiceRecording,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withOpacity(0.4),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.multiline,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          onTap: () {
                            if (_isEmojiVisible) {
                              setState(() { _isEmojiVisible = false; });
                            }
                          },
                          style: TextStyle(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: _editingMessage != null
                                ? 'Edit message...'
                                : (_activeScheduledTime != null ? 'Type scheduled message...' : 'Message'),
                            hintStyle: TextStyle(
                              color: (_editingMessage != null || _activeScheduledTime != null)
                                  ? AppTheme.primaryColor.withValues(alpha: 0.8)
                                  : AppTheme.textSecondary,
                            ),
                            filled: true,
                            fillColor: AppTheme.surfaceColor,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            prefixIcon: IconButton(
                              icon: Icon(_isEmojiVisible ? Icons.keyboard : Icons.emoji_emotions_outlined, color: AppTheme.textSecondary),
                              onPressed: _showEmojiPicker,
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.attach_file_rounded, color: AppTheme.textSecondary, size: 22),
                                  onPressed: _showAttachmentOptions,
                                ),
                                IconButton(
                                  icon: Icon(Icons.camera_alt_rounded, color: AppTheme.textSecondary, size: 22),
                                  onPressed: _showCameraOptions,
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: (_editingMessage != null || _activeScheduledTime != null) ? BorderSide(color: AppTheme.primaryColor, width: 1.5) : BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: (_editingMessage != null || _activeScheduledTime != null) ? BorderSide(color: AppTheme.primaryColor, width: 1.5) : BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _messageController,
                      builder: (context, value, child) {
                        final hasText = value.text.trim().isNotEmpty;
                        if (_activeScheduledTime != null) {
                          return Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.schedule_send_rounded, color: Colors.white, size: 22),
                              tooltip: 'Schedule Message',
                              onPressed: _sendScheduledMessageDirectly,
                            ),
                          );
                        }
                        if (hasText) {
                          return Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: AppTheme.primaryColor.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                              onPressed: _sendMessage,
                            ),
                          );
                        }
                        return Listener(
                          onPointerDown: (event) {
                            _micDragStartOffset = event.position;
                            _micPressStartTime = DateTime.now();
                            _startVoiceRecording(locked: false);
                          },
                          onPointerMove: (event) {
                            if (_isRecording && !_isRecordingLocked && _micDragStartOffset != null) {
                              final dy = event.position.dy - _micDragStartOffset!.dy;
                              final dx = event.position.dx - _micDragStartOffset!.dx;
                              if (dy < -25) {
                                HapticFeedback.mediumImpact();
                                setState(() {
                                  _isRecordingLocked = true;
                                });
                              } else if (dx < -50) {
                                HapticFeedback.lightImpact();
                                _cancelVoiceRecording();
                              }
                            }
                          },
                          onPointerUp: (event) {
                            if (_isRecording && !_isRecordingLocked) {
                              final pressDuration = _micPressStartTime != null ? DateTime.now().difference(_micPressStartTime!) : Duration.zero;
                              if (pressDuration.inMilliseconds < 350) {
                                // Tap -> lock into hands-free mode
                                setState(() {
                                  _isRecordingLocked = true;
                                });
                              } else {
                                // Release after holding -> send
                                _sendVoiceRecording();
                              }
                            }
                          },
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: AppTheme.primaryColor.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: const Icon(
                              Icons.mic_rounded,
                              color: Colors.white, 
                              size: 24,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
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
      ],
      ),
    );
  }
}

class SlidingCameraOptionsSheet extends StatefulWidget {
  final VoidCallback onTakePhoto;
  final VoidCallback onTakeVideo;
  final VoidCallback onDirectGallery;

  const SlidingCameraOptionsSheet({
    Key? key,
    required this.onTakePhoto,
    required this.onTakeVideo,
    required this.onDirectGallery,
  }) : super(key: key);

  @override
  State<SlidingCameraOptionsSheet> createState() => _SlidingCameraOptionsSheetState();
}

class _SlidingCameraOptionsSheetState extends State<SlidingCameraOptionsSheet> {
  int _currentIndex = 0;
  late final PageController _pageController;

  final List<Map<String, dynamic>> _options = [
    {
      'title': 'Take Photo',
      'subtitle': 'Capture a photo with your camera',
      'icon': Icons.camera_alt_rounded,
      'color': const Color(0xFFEC407A),
    },
    {
      'title': 'Take Video',
      'subtitle': 'Record a video clip with your camera',
      'icon': Icons.videocam_rounded,
      'color': const Color(0xFFFF5252),
    },
    {
      'title': 'Direct Gallery',
      'subtitle': 'Select photos or videos directly from gallery',
      'icon': Icons.photo_library_rounded,
      'color': const Color(0xFFAB47BC),
    },
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _triggerAction(int index) {
    Navigator.pop(context);
    if (index == 0) {
      widget.onTakePhoto();
    } else if (index == 1) {
      widget.onTakeVideo();
    } else if (index == 2) {
      widget.onDirectGallery();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 24, left: 16, right: 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 46,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(23),
              ),
              child: Row(
                children: List.generate(_options.length, (index) {
                  final isSelected = _currentIndex == index;
                  final color = _options[index]['color'] as Color;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _currentIndex = index;
                        });
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected ? color : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [],
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _options[index]['icon'] as IconData,
                              size: 16,
                              color: isSelected ? Colors.white : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _options[index]['title'] as String,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 140,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _options.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final opt = _options[index];
                  final color = opt['color'] as Color;
                  final icon = opt['icon'] as IconData;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => _triggerAction(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withOpacity(0.15),
                            border: Border.all(color: color, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: CircleAvatar(
                              radius: 26,
                              backgroundColor: color,
                              child: Icon(icon, color: Colors.white, size: 28),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        opt['title'] as String,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        opt['subtitle'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swipe_left, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Slide horizontally to switch modes',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 4),
                Icon(Icons.swipe_right, size: 14, color: AppTheme.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
