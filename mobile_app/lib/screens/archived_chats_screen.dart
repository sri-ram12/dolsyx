import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import '../services/chat_service.dart';
import 'chat_room_screen.dart';

class ArchivedChatsScreen extends StatefulWidget {
  final List<Chat> archivedChats;
  final Function() onRefresh;

  const ArchivedChatsScreen({
    super.key,
    required this.archivedChats,
    required this.onRefresh,
  });

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  final ChatService _chatService = ChatService();
  final Set<String> _selectedChatIds = {};

  void _unarchiveSelected() async {
    final idsToProcess = List.from(_selectedChatIds);
    for (String id in idsToProcess) {
      await _chatService.updateChatSettings(id, {'isArchived': false});
    }
    setState(() => _selectedChatIds.clear());
    widget.onRefresh();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedChatIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(hasSelection ? '${_selectedChatIds.length}' : 'Archived Chats'),
        actions: [
          if (hasSelection)
            IconButton(
              icon: const Icon(Icons.unarchive),
              onPressed: _unarchiveSelected,
            ),
        ],
      ),
      body: widget.archivedChats.isEmpty
          ? Center(
              child: Text(
                'No archived chats.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
              ),
            )
          : ListView.builder(
              itemCount: widget.archivedChats.length,
              itemBuilder: (context, index) {
                final chat = widget.archivedChats[index];
                final isSelected = _selectedChatIds.contains(chat.id);
                return Container(
                  color: isSelected ? AppTheme.primaryColor.withOpacity(0.2) : Colors.transparent,
                  child: ListTile(
                    selected: isSelected,
                    leading: chat.avatarUrl != null
                        ? CircleAvatar(backgroundImage: NetworkImage(chat.avatarUrl!))
                        : ColorAvatar(name: chat.name ?? "Chat"),
                    title: Text(chat.name ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(chat.lastMessage?['content'] ?? "No messages"),
                    onTap: () {
                      if (_selectedChatIds.isNotEmpty) {
                        setState(() {
                          if (isSelected) _selectedChatIds.remove(chat.id);
                          else _selectedChatIds.add(chat.id);
                        });
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatRoomScreen(
                            conversationId: chat.id,
                            chatName: chat.name ?? "Unknown",
                            avatarUrl: chat.avatarUrl,
                          ),
                        ),
                      ).then((_) => widget.onRefresh());
                    },
                    onLongPress: () {
                      setState(() {
                        if (isSelected) _selectedChatIds.remove(chat.id);
                        else _selectedChatIds.add(chat.id);
                      });
                    },
                  ),
                );
              },
            ),
    );
  }
}
