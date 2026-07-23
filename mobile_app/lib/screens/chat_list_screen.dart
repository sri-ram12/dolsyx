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
import 'status_screen.dart';
import 'settings_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  List<Chat> _chats = [];
  bool _isLoading = true;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchChats();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.socketService.socket?.on('new_message', _handleSocketUpdate);
      authProvider.socketService.socket?.on('messages_read', _handleSocketUpdate);
    });
  }

  @override
  void dispose() {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.socketService.socket?.off('new_message', _handleSocketUpdate);
      authProvider.socketService.socket?.off('messages_read', _handleSocketUpdate);
    } catch (_) {}
    super.dispose();
  }

  void _handleSocketUpdate(dynamic _) {
    if (mounted) {
      _fetchChats();
    }
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

  String _getLastMessage(Chat chat) {
    if (chat.lastMessage != null) {
      return chat.lastMessage!['content'] ?? "Sent a message";
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
                const SizedBox(width: 12),
                Text(
                  'Search',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
              : _chats.isEmpty
                  ? Center(
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: GestureDetector(
                            onTap: () {
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
                            },
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: AppTheme.surfaceColor,
                              backgroundImage: chat.avatarUrl != null ? NetworkImage(chat.avatarUrl!) : null,
                              child: chat.avatarUrl == null
                                  ? Icon(Icons.person, color: AppTheme.textSecondary)
                                  : null,
                            ),
                          ),
                          title: Text(
                            _getChatName(chat),
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            _getLastMessage(chat),
                            style: TextStyle(color: AppTheme.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "12:00", // Placeholder for time
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              ),
                              if (chat.unreadCount > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                  child: Text(
                                    "${chat.unreadCount}",
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ]
                            ],
                          ),
                           onTap: () {
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
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildCallsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.call, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            'No recent calls.\nStart a call from any chat room!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
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

  Widget _buildCommunitiesTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.groups_outlined, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            'Communities Section',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Group communities will appear here.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildChatsTab(),
      _buildUpdatesTab(),
      _buildCommunitiesTab(),
      _buildCallsTab(),
    ];

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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'settings') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              } else if (value == 'logout') {
                _handleLogout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new_group',
                child: Text('New Group'),
              ),
              const PopupMenuItem(
                value: 'new_community',
                child: Text('New Community'),
              ),
              const PopupMenuItem(
                value: 'linked_devices',
                child: Text('Linked Devices'),
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
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.surfaceColor,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.textSecondary,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
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
            label: 'Updates',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            activeIcon: Icon(Icons.groups),
            label: 'Communities',
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
                            leading: const Icon(Icons.person, color: AppTheme.primaryColor),
                            title: Text('New Direct Chat', style: TextStyle(color: AppTheme.textPrimary)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.group, color: AppTheme.primaryColor),
                            title: Text('New Group Chat', style: TextStyle(color: AppTheme.textPrimary)),
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
            )
          : null,
    );
  }
}
