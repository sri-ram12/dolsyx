import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import 'chat_room_screen.dart';
import 'secret_lock_settings_screen.dart';

class LockedChatsScreen extends StatefulWidget {
  final List<Chat>? initialLockedChats;
  final VoidCallback? onRefresh;
  final VoidCallback? onChatsUpdated;

  const LockedChatsScreen({
    super.key,
    this.initialLockedChats,
    this.onRefresh,
    this.onChatsUpdated,
  });

  @override
  State<LockedChatsScreen> createState() => _LockedChatsScreenState();
}

class _LockedChatsScreenState extends State<LockedChatsScreen> {
  final ChatService _chatService = ChatService();
  late List<Chat> _lockedChats;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _lockedChats = List.from(widget.initialLockedChats ?? []);
    if (_lockedChats.isEmpty) {
      _fetchLockedChats();
    }
  }

  Future<void> _fetchLockedChats() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final lockedIds = (prefs.getStringList('locked_chat_ids') ?? []).toSet();
    
    var allChats = await _chatService.getCachedChats();
    if (allChats.isEmpty) {
      try {
        allChats = await _chatService.getChats();
      } catch (_) {}
    } else {
      _chatService.getChats().then((remote) {
        if (mounted && remote.isNotEmpty) {
          for (var c in remote) {
            c.isLocked = lockedIds.contains(c.id);
          }
          setState(() {
            _lockedChats = remote.where((c) => c.isLocked).toList();
          });
        }
      }).catchError((_) {});
    }

    for (var c in allChats) {
      c.isLocked = lockedIds.contains(c.id);
    }

    if (mounted) {
      setState(() {
        _lockedChats = allChats.where((c) => c.isLocked).toList();
        _isLoading = false;
      });
      widget.onRefresh?.call();
      widget.onChatsUpdated?.call();
    }
  }

  String _getChatName(Chat chat) {
    if (chat.isGroup && chat.name != null) return chat.name!;
    if (chat.participants != null && chat.participants!.isNotEmpty) {
      final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? Provider.of<AuthProvider>(context, listen: false).user?['_id'];
      final other = chat.participants!.firstWhere(
        (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
        orElse: () => null,
      );
      if (other != null && other['user']['username'] != null) {
        return other['user']['username'];
      }
    }
    return "Locked Chat";
  }

  Future<void> _unlockChat(Chat chat) async {
    final chatId = chat.id;
    setState(() {
      chat.isLocked = false;
      _lockedChats.removeWhere((c) => c.id == chatId);
    });
    final prefs = await SharedPreferences.getInstance();
    final lockedIds = (prefs.getStringList('locked_chat_ids') ?? []).toSet();
    lockedIds.remove(chatId);
    await prefs.setStringList('locked_chat_ids', lockedIds.toList());
    _chatService.updateChatSettings(chatId, {'isLocked': false}).catchError((_) {});
    widget.onChatsUpdated?.call();
    widget.onRefresh?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unlocked "${_getChatName(chat)}" and restored to main chats')),
      );
    }
  }

  void _showLockedChatOptions(Chat chat) {
    final name = _getChatName(chat);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            title: Text('Open $name', style: const TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(
                    conversationId: chat.id,
                    chatName: name,
                    avatarUrl: chat.avatarUrl,
                  ),
                ),
              ).then((_) => _fetchLockedChats());
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_open, color: Color(0xFF00A884)),
            title: const Text('Unlock & Remove from Locked Chats', style: TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(ctx);
              _unlockChat(chat);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locked chats', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Lock settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SecretLockSettingsScreen()),
              ).then((_) => _fetchLockedChats());
            },
          ),
        ],
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
          : _lockedChats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF00A884).withOpacity(0.12),
                        ),
                        child: const Icon(Icons.lock_rounded, size: 64, color: Color(0xFF00A884)),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No locked chats',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Chats you lock will appear here. You can lock any chat from its chat options menu.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _lockedChats.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final chat = _lockedChats[index];
                    final name = _getChatName(chat);

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: chat.avatarUrl != null
                          ? CircleAvatar(
                              radius: 24,
                              backgroundColor: AppTheme.surfaceColor,
                              backgroundImage: CachedNetworkImageProvider(
                                chat.avatarUrl!.startsWith('http')
                                    ? chat.avatarUrl!
                                    : 'https://dolsyx-app.onrender.com${chat.avatarUrl!}',
                              ),
                            )
                          : ColorAvatar(name: name, radius: 24),
                      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Text(
                        chat.lastMessage?['content'] ?? (chat.lastMessage?['mediaUrl'] != null ? 'Media' : 'No messages'),
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton.icon(
                        icon: const Icon(Icons.lock_open, color: Color(0xFF00A884), size: 18),
                        label: const Text('Unlock', style: TextStyle(color: Color(0xFF00A884), fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => _unlockChat(chat),
                      ),
                      onLongPress: () => _showLockedChatOptions(chat),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatRoomScreen(
                              conversationId: chat.id,
                              chatName: name,
                              avatarUrl: chat.avatarUrl,
                            ),
                          ),
                        ).then((_) => _fetchLockedChats());
                      },
                    );
                  },
                ),
    );
  }
}
