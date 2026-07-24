import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/message.dart';
import '../services/socket_service.dart';
import '../services/chat_service.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../services/socket_service.dart';
import '../models/chat.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import 'other_user_profile_screen.dart';
import '../widgets/color_avatar.dart';
import '../widgets/full_screen_image_view.dart';
import 'call_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final String conversationId;
  final String chatName;
  final String? avatarUrl;
  final String? remoteUserId;
  final Map<String, dynamic>? remoteUser;

  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    required this.chatName,
    this.avatarUrl,
    this.remoteUserId,
    this.remoteUser,
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

  @override
  void initState() {
    super.initState();
    _checkIfContact();
    _fetchMessages();
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.socketService.joinConversation(widget.conversationId);
    authProvider.socketService.onMessageReceived(_handleIncomingMessage);
    
    // Clear unread messages count on entry
    authProvider.socketService.socket?.emit('mark_read', {
      'conversationId': widget.conversationId,
    });

    authProvider.socketService.onTypingChange(_handleTypingChange);
    authProvider.socketService.onStatusChange(_handleStatusChange);
    authProvider.socketService.onChatCleared(_handleChatCleared);
    authProvider.socketService.onMessagesRead(_handleMessagesRead);
    authProvider.socketService.onProfileUpdated(_handleProfileUpdated);

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
    authProvider.socketService.offTypingChange(_handleTypingChange);
    authProvider.socketService.offStatusChange(_handleStatusChange);
    authProvider.socketService.offChatCleared(_handleChatCleared);
    authProvider.socketService.offMessagesRead(_handleMessagesRead);
    authProvider.socketService.offProfileUpdated(_handleProfileUpdated);
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
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
    if (mounted && data['conversationId'] == widget.conversationId && data['userId'] == widget.remoteUserId) {
      setState(() {
        _isRemoteUserTyping = data['isTyping'] == true;
      });
    }
  }

  void _handleStatusChange(dynamic data) {
    if (mounted && data['userId'] == widget.remoteUserId) {
      setState(() {
        _isRemoteUserOnline = data['status'] == 'online';
        if (data['lastSeen'] != null) {
          _remoteUserLastSeen = DateTime.tryParse(data['lastSeen'].toString());
        }
      });
    }
  }

  void _handleMessagesRead(dynamic data) {
    if (mounted && data['conversationId'] == widget.conversationId) {
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
        setState(() {
          _messages.add(Message.fromJson(data['message']));
        });
        _scrollToBottom();
        
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

  void _handleChatCleared(dynamic data) {
    if (mounted && data != null && data['conversationId'] == widget.conversationId) {
      setState(() {
        _messages.clear();
      });
    }
  }

  Future<void> _fetchMessages() async {
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
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _messages = data.map((json) => Message.fromJson(json)).toList();
            _isLoading = false;
          });
        }
        _scrollToBottom();
      }
    } catch (e) {
      print('Error fetching messages: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessageOptions(Message message, bool isMe) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              leading: const Icon(Icons.star_border),
              title: const Text('Star Message'),
              onTap: () {
                Navigator.pop(context);
                // _starMessage(message.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('Pin Message'),
              onTap: () {
                Navigator.pop(context);
                // _pinMessage(message.id);
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

  void _pinSelectedMessages() async {
    for (String msgId in _selectedMessageIds) {
      await _chatService.pinMessage(widget.conversationId, msgId);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_selectedMessageIds.length} message(s) pinned')));
      setState(() => _selectedMessageIds.clear());
    }
  }

  void _deleteSelectedMessages(bool forEveryone) async {
    for (String msgId in _selectedMessageIds) {
      _deleteMessage(msgId, forEveryone);
    }
    if (mounted) {
      setState(() => _selectedMessageIds.clear());
    }
  }

  Future<void> _checkIfContact() async {
    // This calls the backend to check if the user is in contacts.
    // For now, we simulate this call.
    try {
      final token = await ApiService().getToken();
      if (token == null || widget.remoteUserId == null) return;
      
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/contacts'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> contacts = jsonDecode(response.body);
        final isSaved = contacts.any((c) => c['contactId'] == widget.remoteUserId);
        if (mounted) {
          setState(() {
            _isContact = isSaved;
          });
        }
      }
    } catch (e) {
      print('Check contact error: $e');
    }
  }

  Future<void> _addContact() async {
    if (widget.remoteUser == null || widget.remoteUser!['email'] == null) return;
    try {
      final token = await ApiService().getToken();
      if (token == null) return;

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/contacts/add'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'email': widget.remoteUser!['email'],
          'savedName': widget.remoteUser!['username'],
        }),
      );

      if (response.statusCode == 201 && mounted) {
        setState(() {
          _isContact = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact added!')));
      }
    } catch (e) {
      print('Add contact error: $e');
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.socketService.socket?.connected != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Socket disconnected. Cannot send message.')),
      );
      return;
    }

    authProvider.socketService.sendMessage(widget.conversationId, text);
    _messageController.clear();
    if (_isTyping) {
      _isTyping = false;
      authProvider.socketService.emitTyping(widget.conversationId, false);
      _typingTimer?.cancel();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source, imageQuality: 70);
      if (!mounted) return;
      if (pickedFile != null) {
        _uploadAndSendMedia(File(pickedFile.path), 'IMAGE');
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles();
      if (!mounted) return;
      if (result != null && result.files.single.path != null) {
        _uploadAndSendMedia(File(result.files.single.path!), 'FILE');
      }
    } catch (e) {
      print('Error picking file: $e');
    }
  }

  Future<void> _uploadAndSendMedia(File file, String mediaType) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final apiService = ApiService();
      final response = await apiService.uploadMedia(file.path);
      
      if (response != null && response['fileUrl'] != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.socketService.sendMessage(
          widget.conversationId, 
          '', 
          mediaUrl: response['fileUrl'], 
          mediaType: mediaType
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed.')));
      }
    } catch (e) {
      print('Upload error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppTheme.primaryColor),
                title: Text('Camera', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo, color: AppTheme.primaryColor),
                title: Text('Gallery', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.insert_drive_file, color: AppTheme.primaryColor),
                title: Text('Document', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEmojiPicker() {
    final emojis = [
      '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
      '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚',
      '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🥸',
      '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️',
      '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😤', '😠', '😡',
      '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉',
      '👆', '🖕', '👇', '☝️', '👍', '👋', '🤚', '🖐', '✋', '🖖',
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔'
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Container(
          height: 250,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Emojis',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: emojis.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        final text = _messageController.text;
                        final selection = _messageController.selection;
                        final newText = text.replaceRange(
                          selection.start >= 0 ? selection.start : text.length,
                          selection.end >= 0 ? selection.end : text.length,
                          emojis[index],
                        );
                        _messageController.text = newText;
                        _messageController.selection = TextSelection.fromPosition(
                          TextPosition(
                            offset: (selection.start >= 0 ? selection.start : text.length) + emojis[index].length,
                          ),
                        );
                      },
                      child: Center(
                        child: Text(
                          emojis[index],
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
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

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<AuthProvider>(context).user;

    return Scaffold(
      appBar: _selectedMessageIds.isNotEmpty
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectedMessageIds.clear();
                  });
                },
              ),
              title: Text('${_selectedMessageIds.length}'),
              actions: [
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
                  icon: const Icon(Icons.reply),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply coming soon')));
                    setState(() => _selectedMessageIds.clear());
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.forward),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forward coming soon')));
                    setState(() => _selectedMessageIds.clear());
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.push_pin_outlined),
                  onPressed: _pinSelectedMessages,
                ),
              ],
            )
          : AppBar(
              titleSpacing: 0,
              title: GestureDetector(
                onTap: () {
                  if (widget.remoteUserId != null) {
                    final userMap = widget.remoteUser ?? {
                      'id': widget.remoteUserId,
                      'username': widget.chatName,
                      'avatarUrl': widget.avatarUrl,
                    };
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OtherUserProfileScreen(user: userMap),
                      ),
                    );
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
                    icon: const Icon(Icons.videocam, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
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
                    icon: const Icon(Icons.call, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
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
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) {
                    if (value == 'view_contact' && widget.remoteUserId != null) {
                      final userMap = widget.remoteUser ?? {
                        'id': widget.remoteUserId,
                        'username': widget.chatName,
                        'avatarUrl': widget.avatarUrl,
                      };
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => OtherUserProfileScreen(user: userMap)),
                      );
                    } else if (value == 'mute') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mute options coming soon')));
                    } else if (value == 'disappearing') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disappearing messages options coming soon')));
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.remoteUserId != null)
                      const PopupMenuItem(
                        value: 'view_contact',
                        child: Text('View Contact'),
                      ),
                    const PopupMenuItem(
                      value: 'mute',
                      child: Text('Mute Notifications'),
                    ),
                    const PopupMenuItem(
                      value: 'disappearing',
                      child: Text('Disappearing Messages'),
                    ),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
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
                      return GestureDetector(
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
                          child: MessageBubble(message: message, isMe: isMe),
                        ),
                      );
                    },
                  ),
          ),
          if (_isLoading && _messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: LinearProgressIndicator(color: AppTheme.primaryColor),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: Colors.transparent,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      hintStyle: TextStyle(color: AppTheme.textSecondary),
                      filled: true,
                      fillColor: AppTheme.surfaceColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      prefixIcon: IconButton(
                        icon: Icon(Icons.emoji_emotions_outlined, color: AppTheme.textSecondary),
                        onPressed: _showEmojiPicker,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.attach_file, color: AppTheme.textSecondary),
                            onPressed: _showAttachmentOptions,
                          ),
                          IconButton(
                            icon: Icon(Icons.camera_alt_outlined, color: AppTheme.textSecondary),
                            onPressed: () => _pickImage(ImageSource.camera),
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
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primaryColor,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
