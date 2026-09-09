import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import '../widgets/full_screen_image_view.dart';
import 'login_screen.dart';
import 'tabs/calls_tab.dart';
import 'search_screen.dart';
import 'chat_room_screen.dart';
import 'profile_screen.dart';
import 'create_group_screen.dart';
import 'my_qr_screen.dart';
import 'qr_scanner_screen.dart';
import 'other_user_profile_screen.dart';
import 'status_screen.dart';
import 'status_privacy_screen.dart';
import 'settings_screen.dart';
import 'archived_chats_screen.dart';
import 'contacts_screen.dart';
import 'group_settings_screen.dart';
import 'dolsyx_ai_screen.dart';
import 'starred_messages_screen.dart';
import '../models/message.dart';
import '../services/auto_download_service.dart';
import '../widgets/switch_account_modal.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'secret_lock_settings_screen.dart';
import 'locked_chats_screen.dart';
import 'linked_devices_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with WidgetsBindingObserver {
  final ChatService _chatService = ChatService();
  List<Chat> _chats = [];
  bool _isLoading = true;
  int _selectedIndex = 0;
  late PageController _pageController;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _profileSubscription;
  StreamSubscription? _onlineSubscription;
  StreamSubscription? _typingSubscription;
  final Set<String> _selectedChatIds = {};
  Set<String> _onlineUsers = {};
  Map<String, bool> _typingStatus = {};
  bool _hideLockedChats = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _fetchChats();
    
    WidgetsBinding.instance.addObserver(this);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _messageSubscription = authProvider.socketService.onMessageStream.listen((event) {
        _handleSocketUpdate(event);
      });
      _profileSubscription = authProvider.socketService.profileUpdates.stream.listen((event) {
        _handleSocketUpdate(event);
      });
      authProvider.socketService.socket?.on('messages_read', (data) {
        _handleSocketUpdate(data);
      });
      _onlineSubscription = authProvider.socketService.onlineUsersStream.stream.listen((users) {
        if (mounted && (users.length != _onlineUsers.length || !users.containsAll(_onlineUsers))) {
          setState(() { _onlineUsers = users; });
        }
      });
      _typingSubscription = authProvider.socketService.typingUpdates.stream.listen((data) {
        if (mounted) {
          final convId = data['conversationId'];
          final isTyping = data['isTyping'] == true;
          if (_typingStatus[convId] != isTyping) {
            setState(() { _typingStatus[convId] = isTyping; });
          }
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchChats();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSubscription?.cancel();
    _profileSubscription?.cancel();
    _onlineSubscription?.cancel();
    _typingSubscription?.cancel();
    _pageController.dispose();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.socketService.socket?.off('messages_read');
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

  void _handleSocketUpdate(dynamic event) {
    if (!mounted) return;
    try {
      if (event != null && event is Map<String, dynamic> && event['conversationId'] != null) {
        final conversationId = event['conversationId'];
        String? currentUserId;
        try {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          currentUserId = (auth.user?['id'] ?? auth.user?['_id'])?.toString();
        } catch (_) {}

        final message = event['message'];
        final senderId = message != null ? (message['senderId'] ?? message['sender']?['id'] ?? message['sender']?['_id'])?.toString() : null;

        bool found = false;
        if (mounted) {
          setState(() {
            final index = _chats.indexWhere((c) {
              if (c.id == conversationId) return true;
              if (!c.isGroup && senderId != null && c.participants != null) {
                final otherP = c.participants!.firstWhere(
                  (p) => p['user'] != null && (p['user']['id']?.toString() == senderId || p['user']['_id']?.toString() == senderId),
                  orElse: () => null,
                );
                return otherP != null;
              }
              return false;
            });
            if (index != -1) {
              found = true;
              if (event['type'] == 'read') {
                 _chats[index].unreadCount = 0;
              } else {
                 if (senderId != null && senderId != currentUserId) {
                   _chats[index].unreadCount += 1;
                 }
                  if (message != null) {
                    _chats[index].lastMessage = message;
                    try {
                      final msgObj = Message.fromJson(Map<String, dynamic>.from(message));
                      AutoDownloadService.checkAndAutoDownload(msgObj);
                    } catch (_) {}
                  }
                  _chats[index].updatedAt = DateTime.now();
                  
                  // Move the updated chat to the top of the list
                  final updatedChat = _chats.removeAt(index);
                  _chats.insert(0, updatedChat);
               }
             }
           });
         }
        if (!found && message != null && mounted) {
          try {
            final msgObj = Message.fromJson(Map<String, dynamic>.from(message));
            AutoDownloadService.checkAndAutoDownload(msgObj);
          } catch (_) {}
          _fetchChats();
        }
      }
    } catch (e) {
      debugPrint('Error handling socket update in ChatListScreen: $e');
    }
  }

  void _sortChats() {
    _chats.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      final timeA = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final timeB = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return timeB.compareTo(timeA);
    });
  }

  void _setChatsDeduplicated(List<Chat> newChats) {
    final Map<String, Chat> directChatsByUserId = {};
    final Map<String, Chat> chatsById = {};
    String? currentUserId;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      currentUserId = (auth.user?['id'] ?? auth.user?['_id'])?.toString();
    } catch (_) {}

    for (final chat in newChats) {
      // 1. Deduplicate by conversation ID
      if (chatsById.containsKey(chat.id)) continue;
      chatsById[chat.id] = chat;

      // 2. Deduplicate 1-on-1 direct chats by recipient user ID
      if (!chat.isGroup) {
        String? otherUserId;
        if (chat.participants != null && chat.participants!.isNotEmpty) {
          final otherP = chat.participants!.firstWhere(
            (p) => p['user'] != null && (p['user']['id']?.toString() != currentUserId && p['user']['_id']?.toString() != currentUserId),
            orElse: () => null,
          );
          if (otherP != null) {
            otherUserId = (otherP['user']['id'] ?? otherP['user']['_id'])?.toString();
          }
        }
        if (otherUserId != null && otherUserId.isNotEmpty) {
          if (directChatsByUserId.containsKey(otherUserId)) {
            final existing = directChatsByUserId[otherUserId]!;
            final timeExisting = existing.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final timeCurrent = chat.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            if (timeCurrent.isAfter(timeExisting)) {
              directChatsByUserId[otherUserId] = chat;
            }
          } else {
            directChatsByUserId[otherUserId] = chat;
          }
        }
      }
    }

    final uniqueChats = chatsById.values.where((chat) {
      if (chat.isGroup) return true;
      String? otherUserId;
      if (chat.participants != null && chat.participants!.isNotEmpty) {
        final otherP = chat.participants!.firstWhere(
          (p) => p['user'] != null && (p['user']['id']?.toString() != currentUserId && p['user']['_id']?.toString() != currentUserId),
          orElse: () => null,
        );
        if (otherP != null) {
          otherUserId = (otherP['user']['id'] ?? otherP['user']['_id'])?.toString();
        }
      }
      if (otherUserId == null) return true;
      return directChatsByUserId[otherUserId]?.id == chat.id;
    }).toList();

    _chats = uniqueChats;
    _sortChats();
  }

  Future<void> _fetchChats() async {
    Set<String> lockedIds = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      _hideLockedChats = prefs.getBool('hide_locked_chats') ?? false;
      lockedIds = (prefs.getStringList('locked_chat_ids') ?? []).toSet();
    } catch (_) {}

    if (mounted) {
      final cachedChats = await _chatService.getCachedChats();
      if (cachedChats.isNotEmpty) {
        for (var c in cachedChats) {
          c.isLocked = lockedIds.contains(c.id);
        }
        setState(() {
          _setChatsDeduplicated(cachedChats);
          _isLoading = false;
        });
      }
    }

    try {
      final chats = await _chatService.getChats();
      for (var c in chats) {
        c.isLocked = lockedIds.contains(c.id);
      }

      if (mounted) {
        setState(() {
          _setChatsDeduplicated(chats);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching chats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }


  String _getChatName(Chat chat) {
    if (chat.isGroup && chat.name != null) return chat.name!;
    if (chat.participants != null && chat.participants!.isNotEmpty) {
      final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? Provider.of<AuthProvider>(context, listen: false).user?['_id'];
      final otherParticipant = chat.participants!.firstWhere(
        (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
        orElse: () => null,
      );
      if (otherParticipant != null && otherParticipant['user']['username'] != null) {
        return otherParticipant['user']['username'];
      }
    }
    return "Unknown Chat";
  }

  Widget _buildLastMessageWidget(Chat chat) {
    if (_typingStatus[chat.id] == true) {
      return Text("Typing...", style: TextStyle(color: AppTheme.primaryColor), maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    
    if (chat.lastMessage != null) {
      final msg = chat.lastMessage!;
      if (msg['mediaType'] == 'CALL_LOG') {
        IconData icon = msg['mediaUrl'] == 'video' ? Icons.videocam : Icons.phone;
        String text = msg['content'] == 'missed' ? 'Missed call' : 
                      (msg['content'] == 'declined' ? 'Declined call' : 'Call ended');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Flexible(child: Text(text, style: TextStyle(color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        );
      } else if (msg['mediaType'] == 'IMAGE') {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Flexible(child: Text("Photo", style: TextStyle(color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        );
      }
      return Text(msg['content'] ?? "Sent a message", style: TextStyle(color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text("No messages yet", style: TextStyle(color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  bool _isChatOnline(Chat chat) {
    if (chat.isGroup) return false;
    if (chat.participants != null && chat.participants!.isNotEmpty) {
      final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? Provider.of<AuthProvider>(context, listen: false).user?['_id'];
      final otherParticipant = chat.participants!.firstWhere(
        (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
        orElse: () => null,
      );
      if (otherParticipant != null) {
        final userId = otherParticipant['user']['id'] ?? otherParticipant['user']['_id'];
        return _onlineUsers.contains(userId.toString());
      }
    }
    return false;
  }

  String _formatTime(DateTime? time) {
    if (time == null) return "";
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inDays == 0 && now.day == time.day) {
      return DateFormat('hh:mm a').format(time); // Today
    } else if (difference.inDays == 1 || (difference.inDays == 0 && now.day != time.day)) {
      return "Yesterday";
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE').format(time); // Day of week
    } else {
      return DateFormat('dd/MM/yyyy').format(time); // Date
    }
  }

  void _handleLogout() async {
    await Provider.of<AuthProvider>(context, listen: false).logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Widget _buildChatsTab() {
    return Column(
      children: [
        // Search Bar (Pic 2 style)
        GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
                SizedBox(width: 12),
                Text(
                  'Search',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchChats,
            color: AppTheme.primaryColor,
            backgroundColor: AppTheme.surfaceColor,
            child: _isLoading && _chats.isEmpty
                ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : _chats.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 100),
                          Center(
                            child: Text(
                              'No conversations yet.\nStart a chat!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        cacheExtent: 1500.0,
                        addAutomaticKeepAlives: true,
                        addRepaintBoundaries: true,
                        itemCount: () {
                          final activeCount = _chats.where((c) => !c.isArchived && !c.isLocked).length;
                          final lockedCount = _chats.where((c) => c.isLocked).length;
                          final showLockedTile = !_hideLockedChats && lockedCount > 0;
                          return 1 + (showLockedTile ? 1 : 0) + activeCount + (_chats.any((c) => c.isArchived) ? 1 : 0);
                        }(),
                        itemBuilder: (context, index) {
                          final activeChats = _chats.where((c) => !c.isArchived && !c.isLocked).toList();
                          final lockedCount = _chats.where((c) => c.isLocked).length;
                          final showLockedTile = !_hideLockedChats && lockedCount > 0;

                          if (index == 0) {
                            return ListTile(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const DolsyxAiScreen()),
                                );
                              },
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              leading: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF3B82F6)],
                                  ),
                                ),
                                child: const CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Color(0xFF0B141A),
                                  child: Icon(Icons.smart_toy, color: Color(0xFFEC4899), size: 22),
                                ),
                              ),
                              title: Row(
                                children: [
                                  const Text(
                                    'DOLSYX AI',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEC4899).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('Interactive Bot', style: TextStyle(color: Color(0xFFEC4899), fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              subtitle: const Text(
                                'Generate images, Q&A, draft emails & code...',
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }

                          if (showLockedTile && index == 1) {
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A884).withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.lock_rounded, color: Color(0xFF00A884), size: 24),
                              ),
                              title: const Text(
                                'Locked chats',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              subtitle: Text(
                                '$lockedCount locked chat${lockedCount > 1 ? 's' : ''}',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              ),
                              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LockedChatsScreen(onChatsUpdated: _fetchChats),
                                  ),
                                );
                              },
                            );
                          }

                          final offset = 1 + (showLockedTile ? 1 : 0);
                          final chatIndex = index - offset;

                          if (chatIndex == activeChats.length) {
                            return ListTile(
                              leading: Icon(Icons.archive_outlined, color: AppTheme.textSecondary),
                              title: Text('Archived Chats', style: TextStyle(color: AppTheme.textSecondary)),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ArchivedChatsScreen(
                                      archivedChats: _chats.where((c) => c.isArchived).toList(),
                                      onRefresh: _fetchChats,
                                    ),
                                  ),
                                );
                              },
                            );
                          }
                          
                          final chat = activeChats[chatIndex];
                          final isSelected = _selectedChatIds.contains(chat.id);
                          return Container(
                            color: isSelected ? AppTheme.primaryColor.withOpacity(0.2) : Colors.transparent,
                            child: ListTile(
                              selected: isSelected,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: GestureDetector(
                              onTap: () {
                                if (chat.avatarUrl != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FullScreenImageView(imageUrl: chat.avatarUrl!),
                                    ),
                                  );
                                } else {
                                  if (!chat.isGroup && chat.participants != null && chat.participants!.isNotEmpty) {
                                    final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? Provider.of<AuthProvider>(context, listen: false).user?['_id'];
                                    final otherParticipant = chat.participants!.firstWhere(
                                      (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
                                      orElse: () => null,
                                    );
                                    if (otherParticipant != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => OtherUserProfileScreen(user: otherParticipant['user']),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  chat.avatarUrl != null
                                      ? CircleAvatar(
                                          radius: 24,
                                          backgroundColor: AppTheme.surfaceColor,
                                          backgroundImage: CachedNetworkImageProvider(
                                            chat.avatarUrl!.startsWith('http')
                                                ? chat.avatarUrl!
                                                : 'https://dolsyx-app.onrender.com${chat.avatarUrl!}',
                                            maxHeight: 120,
                                            maxWidth: 120,
                                          ),
                                        )
                                      : (chat.isGroup
                                          ? CircleAvatar(
                                              radius: 24,
                                              backgroundColor: AppTheme.surfaceColor,
                                              child: Icon(Icons.group, color: AppTheme.textSecondary, size: 28),
                                            )
                                          : ColorAvatar(name: _getChatName(chat), radius: 24)),
                                  if (isSelected)
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00A884),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppTheme.backgroundColor, width: 2),
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _getChatName(chat),
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (chat.isPinned)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.push_pin, size: 16, color: Colors.green),
                                ),
                            ],
                          ),
                          subtitle: _buildLastMessageWidget(chat),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatTime(chat.updatedAt ?? (chat.lastMessage != null && chat.lastMessage!['createdAt'] != null ? DateTime.tryParse(chat.lastMessage!['createdAt']) : null)),
                                style: TextStyle(
                                  color: chat.unreadCount > 0 ? Colors.green : AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: chat.unreadCount > 0 ? FontWeight.bold : FontWeight.normal
                                ),
                              ),
                              if (chat.unreadCount > 0) ...[
                                SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                  child: Text(
                                    chat.unreadCount > 99 ? "99+" : "${chat.unreadCount}",
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ]
                            ],
                          ),
                           onTap: () {
                            if (_selectedChatIds.isNotEmpty) {
                              setState(() {
                                if (isSelected) {
                                  _selectedChatIds.remove(chat.id);
                                } else {
                                  _selectedChatIds.add(chat.id);
                                }
                              });
                              return;
                            }
                            _openChat(chat);
                          },
                          onLongPress: () {
                            setState(() {
                              if (isSelected) {
                                _selectedChatIds.remove(chat.id);
                              } else {
                                _selectedChatIds.add(chat.id);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  void _showChatOptions(Chat chat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: AppTheme.primaryColor),
              title: Text(chat.isPinned ? 'Unpin Chat' : 'Pin Chat', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _togglePinChat(chat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(chat.isArchived ? 'Unarchive Chat' : 'Archive Chat', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () async {
                Navigator.pop(ctx);
                await _chatService.archiveChat(chat.id, !chat.isArchived);
                _fetchChats();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _togglePinChat(Chat chat) {
    final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
    final newPin = !chat.isPinned;
    final pinnedCount = _chats.where((c) => c.isPinned).length;
    if (newPin && pinnedCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only pin up to 3 chats')),
      );
      return;
    }
    socket?.emit('pin_contact', {
      'conversationId': chat.id,
      'pin': newPin,
    });
    setState(() {
      chat.isPinned = newPin;
      chat.pinnedAt = newPin ? DateTime.now() : null;
      _sortChats();
    });
  }

  Widget _buildCallsTab() {
    return const CallsTab();
  }

  Widget _buildOtherTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.widgets, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            'Other Section',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'More tools and features coming soon.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatesTab() {
    return const StatusScreen();
  }

  Widget _buildGroupsTab() {
    final groupChats = _chats.where((c) => c.isGroup).toList();

    return RefreshIndicator(
      onRefresh: _fetchChats,
      color: AppTheme.primaryColor,
      backgroundColor: AppTheme.surfaceColor,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        children: [
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.groups_rounded, color: AppTheme.primaryColor),
          ),
          title: Text('New Group', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          subtitle: Text('Create a new group for your friends, family or team', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          onTap: () async {
            final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
            if (res == true) {
              _fetchChats();
            }
          },
        ),
        const Divider(color: Colors.grey),
        if (groupChats.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: Column(
              children: [
                Icon(Icons.groups_outlined, size: 64, color: AppTheme.textSecondary),
                const SizedBox(height: 16),
                Text(
                  'No Groups Yet',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap "New Group" above to build your first group.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...groupChats.map((chat) {
            final cleanName = chat.name ?? 'Group';
            final avatar = chat.avatarUrl;
            return ListTile(
              leading: GestureDetector(
                onTap: () {
                  if (avatar != null && avatar.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenImageView(imageUrl: avatar),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupSettingsScreen(
                          conversationId: chat.id,
                          groupName: cleanName,
                          groupAvatarUrl: avatar,
                          participants: chat.participants ?? [],
                        ),
                      ),
                    );
                  }
                },
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryColor,
                  backgroundImage: avatar != null && avatar.isNotEmpty
                      ? CachedNetworkImageProvider(ApiService.getMediaUrl(avatar))
                      : null,
                  child: avatar == null || avatar.isEmpty
                      ? Text(cleanName.isNotEmpty ? cleanName[0].toUpperCase() : 'G', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                      : null,
                ),
              ),
              title: Text(cleanName, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
              subtitle: Text('${chat.participants?.length ?? 0} members', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              onTap: () => _openChat(chat),
            );
          }),
        ],
      ),
    );
  }

  void _openChat(Chat chat) async {
    if (chat.isLocked) {
      try {
        final localAuth = LocalAuthentication();
        final canAuth = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();
        if (canAuth) {
          final authenticated = await localAuth.authenticate(
            localizedReason: 'Authenticate to open locked chat',
          );
          if (!authenticated) return;
        }
      } catch (e) {
        debugPrint('Biometric error: $e');
      }
    }

    String? remoteId;
    Map<String, dynamic>? remoteUser;
    if (!chat.isGroup && chat.participants != null) {
      final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? Provider.of<AuthProvider>(context, listen: false).user?['_id'];
      final otherParticipant = chat.participants!.firstWhere(
        (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
        orElse: () => null,
      );
      if (otherParticipant != null) {
        remoteId = otherParticipant['user']['id'] ?? otherParticipant['user']['_id'];
        remoteUser = otherParticipant['user'];
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          conversationId: chat.id,
          chatName: _getChatName(chat),
          avatarUrl: chat.avatarUrl,
          remoteUserId: remoteId,
          remoteUser: remoteUser,
        ),
      ),
    ).then((_) {
      if (mounted) _fetchChats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildChatsTab(),
      _buildUpdatesTab(),
      _buildGroupsTab(),
      _buildCallsTab(),
    ];

    final isSocketConnected = Provider.of<AuthProvider>(context).socketService.isConnected;

    return Scaffold(
      appBar: _selectedChatIds.isNotEmpty ? AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              _selectedChatIds.clear();
            });
          },
        ),
        title: Text('${_selectedChatIds.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.push_pin),
            onPressed: () {
              final idsToProcess = List.from(_selectedChatIds);
              for (String id in idsToProcess) {
                final chat = _chats.firstWhere((c) => c.id == id, orElse: () => _chats.first);
                _togglePinChat(chat);
              }
              setState(() {
                _selectedChatIds.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final idsToProcess = List.from(_selectedChatIds);
              for (String id in idsToProcess) {
                await _chatService.deleteChat(id);
              }
              setState(() {
                _selectedChatIds.clear();
              });
              _fetchChats();
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_off),
            onPressed: () async {
              final idsToProcess = List.from(_selectedChatIds);
              for (String id in idsToProcess) {
                // Setting muteUntil far in the future
                await _chatService.updateChatSettings(id, {'muteUntil': DateTime.now().add(const Duration(days: 3650)).toIso8601String()});
              }
              setState(() {
                _selectedChatIds.clear();
              });
              _fetchChats();
            },
          ),
          if (_selectedChatIds.any((id) => _chats.firstWhere((c) => c.id == id, orElse: () => _chats.first).isArchived))
            IconButton(
              icon: const Icon(Icons.unarchive),
              onPressed: () async {
                final idsToProcess = List.from(_selectedChatIds);
                for (String id in idsToProcess) {
                  await _chatService.updateChatSettings(id, {'isArchived': false});
                }
                setState(() => _selectedChatIds.clear());
                _fetchChats();
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.archive),
              onPressed: () async {
                final idsToProcess = List.from(_selectedChatIds);
                for (String id in idsToProcess) {
                  await _chatService.updateChatSettings(id, {'isArchived': true});
                }
                setState(() => _selectedChatIds.clear());
                _fetchChats();
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              final idsToProcess = List.from(_selectedChatIds);
              if (value == 'clear_chat') {
                for (String id in idsToProcess) {
                  await _chatService.clearChat(id);
                }
                setState(() => _selectedChatIds.clear());
                _fetchChats();
              } else if (value == 'lock') {
                final prefs = await SharedPreferences.getInstance();
                final lockedIds = (prefs.getStringList('locked_chat_ids') ?? []).toSet();
                for (String id in idsToProcess) {
                  lockedIds.add(id);
                  _chatService.updateChatSettings(id, {'isLocked': true}).catchError((_) {});
                }
                await prefs.setStringList('locked_chat_ids', lockedIds.toList());
                setState(() => _selectedChatIds.clear());
                _fetchChats();
              } else if (value == 'unlock') {
                final prefs = await SharedPreferences.getInstance();
                final lockedIds = (prefs.getStringList('locked_chat_ids') ?? []).toSet();
                for (String id in idsToProcess) {
                  lockedIds.remove(id);
                  _chatService.updateChatSettings(id, {'isLocked': false}).catchError((_) {});
                }
                await prefs.setStringList('locked_chat_ids', lockedIds.toList());
                setState(() => _selectedChatIds.clear());
                _fetchChats();
              } else if (value == 'favorite') {
                for (String id in idsToProcess) {
                  await _chatService.updateChatSettings(id, {'isFavorite': true});
                }
                setState(() => _selectedChatIds.clear());
                _fetchChats();
              } else if (value == 'block') {
                for (String id in idsToProcess) {
                  final chat = _chats.firstWhere((c) => c.id == id, orElse: () => _chats.first);
                  if (!chat.isGroup && chat.participants != null) {
                    final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? Provider.of<AuthProvider>(context, listen: false).user?['_id'];
                    final otherParticipant = chat.participants!.firstWhere(
                      (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
                      orElse: () => null,
                    );
                    if (otherParticipant != null) {
                      final remoteId = otherParticipant['user']['id'] ?? otherParticipant['user']['_id'];
                      await ApiService().blockUser(remoteId);
                    }
                  }
                }
                setState(() => _selectedChatIds.clear());
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Users blocked')));
                _fetchChats();
              }
            },
            itemBuilder: (context) {
              final anyLocked = _selectedChatIds.any((id) => _chats.firstWhere((c) => c.id == id, orElse: () => _chats.first).isLocked);
              return [
                if (_selectedChatIds.length == 1)
                  const PopupMenuItem(
                    value: 'view_contact',
                    child: Text('View Contact'),
                  ),
                PopupMenuItem(
                  value: anyLocked ? 'unlock' : 'lock',
                  child: Text(anyLocked ? 'Unlock Chat' : 'Lock Chat'),
                ),
                const PopupMenuItem(
                  value: 'favorite',
                  child: Text('Add to Favourite'),
                ),
                const PopupMenuItem(
                  value: 'clear_chat',
                  child: Text('Clear Chat'),
                ),
                const PopupMenuItem(
                  value: 'block',
                  child: Text('Block'),
                ),
              ];
            },
          ),
        ],
      ) : AppBar(
        title: Row(
          children: [
            Consumer<AuthProvider>(
              builder: (context, auth, child) {
                final user = auth.user;
                return GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                  },
                  child: user?['avatarUrl'] != null
                      ? CircleAvatar(
                          radius: 18,
                          backgroundColor: AppTheme.backgroundColor,
                          backgroundImage: CachedNetworkImageProvider(ApiService.getMediaUrl(user!['avatarUrl'])),
                        )
                      : ColorAvatar(
                          name: user?['username'] ?? '?',
                          radius: 18,
                        ),
                );
              },
            ),
            const SizedBox(width: 12),
            const Text('DOLSYX', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: false,
        actions: [
          if (_selectedIndex == 1) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'status_privacy') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StatusPrivacyScreen()),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'status_privacy',
                  child: Text('Status Privacy'),
                ),
              ],
            )
          ] else if (_selectedIndex == 3) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'clear_all_calls') {
                  CallsTab.clearAllCallsGlobal?.call();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'clear_all_calls',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, color: Colors.redAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Clear all call logs'),
                    ],
                  ),
                ),
              ],
            )
          ] else ...[
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
              },
            ),
            IconButton(
              icon: const Icon(Icons.qr_code),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MyQrScreen()));
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'settings') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                } else if (value == 'starred') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const StarredMessagesScreen(starredMessages: [])));
                } else if (value == 'linked_devices') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LinkedDevicesScreen()));
                } else if (value == 'secret_lock') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SecretLockSettingsScreen())).then((_) => _fetchChats());
                } else if (value == 'switch_account') {
                  SwitchAccountModal.show(context);
                } else if (value == 'logout') {
                  _handleLogout();
                } else if (value == 'new_group') {
                  final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
                  if (res == true) {
                    _fetchChats();
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'new_group',
                  child: Text('New Group'),
                ),
                const PopupMenuItem(
                  value: 'linked_devices',
                  child: Text('Linked Devices'),
                ),
                const PopupMenuItem(
                  value: 'secret_lock',
                  child: Text('Chat Lock Settings'),
                ),
                const PopupMenuItem(
                  value: 'starred',
                  child: Text('Starred Messages'),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Settings'),
                ),
                const PopupMenuItem(
                  value: 'switch_account',
                  child: Text('Switch Account'),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Text('Logout'),
                ),
              ],
            ),
          ]
        ],
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          if (!isSocketConnected)
            Container(
              width: double.infinity,
              color: Colors.redAccent.withOpacity(0.9),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const Text(
                'Waiting for network...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              children: pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.surfaceColor,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.textSecondary,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (index) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.blur_circular),
            activeIcon: Icon(Icons.blur_circular),
            label: 'Status',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            activeIcon: Icon(Icons.groups),
            label: 'Groups',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.phone_outlined),
            activeIcon: Icon(Icons.phone),
            label: 'Calls',
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: AppTheme.surfaceColor,
                  builder: (context) {
                    return SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: Icon(Icons.person, color: AppTheme.primaryColor),
                            title: Text('New Direct Chat', style: TextStyle(color: AppTheme.textPrimary)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen()));
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.group, color: AppTheme.primaryColor),
                            title: Text('New Group Chat', style: TextStyle(color: AppTheme.textPrimary)),
                            onTap: () async {
                              Navigator.pop(context);
                              final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
                              if (res == true) {
                                _fetchChats();
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              backgroundColor: AppTheme.primaryColor,
              child: const Icon(Icons.chat_bubble, color: Colors.white),
            )
          : null,
    );
  }
}
