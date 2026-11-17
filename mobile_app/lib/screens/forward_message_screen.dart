import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/theme_check_badge.dart';

class ForwardMessageScreen extends StatefulWidget {
  final List<Message> messages;

  const ForwardMessageScreen({super.key, required this.messages});

  @override
  State<ForwardMessageScreen> createState() => _ForwardMessageScreenState();
}

class _ForwardMessageScreenState extends State<ForwardMessageScreen> {
  final ChatService _chatService = ChatService();
  List<Chat> _chats = [];
  bool _isLoading = true;
  final Set<String> _selectedConversationIds = {};

  @override
  void initState() {
    super.initState();
    _fetchChats();
  }

  Future<void> _fetchChats() async {
    final chats = await _chatService.getChats();
    if (mounted) {
      setState(() {
        _chats = chats;
        _isLoading = false;
      });
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
    return 'Unknown User';
  }

  String? _getChatAvatar(Chat chat) {
    if (chat.isGroup && chat.avatarUrl != null) return chat.avatarUrl;
    if (chat.participants != null && chat.participants!.isNotEmpty) {
      final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? Provider.of<AuthProvider>(context, listen: false).user?['_id'];
      final otherParticipant = chat.participants!.firstWhere(
        (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
        orElse: () => null,
      );
      if (otherParticipant != null && otherParticipant['user']['avatarUrl'] != null) {
        return otherParticipant['user']['avatarUrl'];
      }
    }
    return null;
  }

  void _forwardMessages() {
    if (_selectedConversationIds.isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    for (final conversationId in _selectedConversationIds) {
      for (final message in widget.messages) {
        // Exclude parentMessageId since we are forwarding, not replying
        authProvider.socketService.sendMessage(
          conversationId,
          message.content,
          mediaUrl: message.mediaUrl,
          mediaType: message.mediaType,
          isForwarded: true,
        );
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Forwarded to ${_selectedConversationIds.length} chat(s)')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Forward to...'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? Center(child: Text('No chats available', style: TextStyle(color: AppTheme.textSecondary)))
              : ListView.builder(
                  itemCount: _chats.length,
                  itemBuilder: (context, index) {
                    final chat = _chats[index];
                    final chatName = _getChatName(chat);
                    final avatarUrl = _getChatAvatar(chat);
                    final isSelected = _selectedConversationIds.contains(chat.id);

                    return ListTile(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedConversationIds.remove(chat.id);
                          } else {
                            // Phase 26: WhatsApp 5 chat forward limit
                            if (_selectedConversationIds.length >= 5) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('You can only share with up to 5 chats')),
                              );
                              return;
                            }
                            _selectedConversationIds.add(chat.id);
                          }
                        });
                      },
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
                            backgroundImage: avatarUrl != null
                                ? CachedNetworkImageProvider(
                                    avatarUrl.startsWith('http') ? avatarUrl : 'https://dolsyx.vercel.app$avatarUrl',
                                  )
                                : null,
                            child: avatarUrl == null
                                ? Icon(chat.isGroup ? Icons.group : Icons.person, color: AppTheme.primaryColor)
                                : null,
                          ),
                          if (isSelected)
                            const Positioned(
                              bottom: -2,
                              right: -2,
                              child: ThemeCheckBadge(isSelected: true, size: 18),
                            ),
                        ],
                      ),
                      title: Text(chatName, style: TextStyle(color: AppTheme.textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      trailing: ThemeCheckBadge(isSelected: isSelected, size: 22),
                    );
                  },
                ),
      floatingActionButton: _selectedConversationIds.isNotEmpty
          ? FloatingActionButton(
              onPressed: _forwardMessages,
              backgroundColor: AppTheme.primaryColor,
              child: const Icon(Icons.send, color: Colors.white),
            )
          : null,
    );
  }
}
