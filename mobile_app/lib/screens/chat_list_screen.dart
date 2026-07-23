import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'search_screen.dart';
import 'chat_room_screen.dart';
import 'profile_screen.dart';
import 'create_group_screen.dart';
import 'my_qr_screen.dart';
import 'qr_scanner_screen.dart';
import 'other_user_profile_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  List<Chat> _chats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchChats();
  }

  Future<void> _fetchChats() async {
    final chats = await _chatService.getChats();
    setState(() {
      _chats = chats;
      _isLoading = false;
    });
  }

  String _getChatName(Chat chat) {
    if (chat.isGroup && chat.name != null) return chat.name!;
    if (chat.participants != null && chat.participants!.isNotEmpty) {
      // Find the other user's username
      final otherParticipant = chat.participants!.firstWhere(
        (p) => p['user'] != null,
        orElse: () => null,
      );
      if (otherParticipant != null && otherParticipant['user']['username'] != null) {
        return otherParticipant['user']['username'];
      }
    }
    return "Unknown Chat";
  }

  String _getLastMessage(Chat chat) {
    if (chat.messages != null && chat.messages!.isNotEmpty) {
      return chat.messages!.last['content'] ?? "Sent a message";
    }
    return "No messages yet";
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DOLSYX', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
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
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _chats.isEmpty
              ? const Center(
                  child: Text(
                    'No conversations yet.\nStart a chat!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: _chats.length,
                  itemBuilder: (context, index) {
                    final chat = _chats[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: GestureDetector(
                        onTap: () {
                          if (!chat.isGroup && chat.participants != null && chat.participants!.isNotEmpty) {
                            final otherParticipant = chat.participants!.firstWhere(
                              (p) => p['user'] != null,
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
                        },
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.surfaceColor,
                          backgroundImage: chat.avatarUrl != null ? NetworkImage(chat.avatarUrl!) : null,
                          child: chat.avatarUrl == null
                              ? const Icon(Icons.person, color: AppTheme.textSecondary)
                              : null,
                        ),
                      ),
                      title: Text(
                        _getChatName(chat),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        _getLastMessage(chat),
                        style: const TextStyle(color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Text(
                        "12:00", // Placeholder for actual time formatting
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatRoomScreen(
                              conversationId: chat.id,
                              chatName: _getChatName(chat),
                              avatarUrl: chat.avatarUrl,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
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
                      leading: const Icon(Icons.person, color: AppTheme.primaryColor),
                      title: const Text('New Direct Chat', style: TextStyle(color: AppTheme.textPrimary)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.group, color: AppTheme.primaryColor),
                      title: const Text('New Group Chat', style: TextStyle(color: AppTheme.textPrimary)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
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
      ),
    );
  }
}
