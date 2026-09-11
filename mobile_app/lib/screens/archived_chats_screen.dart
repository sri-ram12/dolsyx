import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import '../services/chat_service.dart';
import 'chat_room_screen.dart';
import '../utils/e2ee/crypto_service.dart';

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

  Widget _buildSubtitle(Chat chat) {
    if (chat.lastMessage == null) {
      return Text("No messages", style: TextStyle(color: AppTheme.textSecondary));
    }
    final msg = chat.lastMessage!;
    final mType = (msg['mediaType'] ?? '').toString();
    if (mType == 'IMAGE') return Text("📷 Photo", style: TextStyle(color: AppTheme.textSecondary));
    if (mType == 'VIDEO') return Text("🎬 Video", style: TextStyle(color: AppTheme.textSecondary));
    if (mType == 'AUDIO') return Text("🎵 Voice message", style: TextStyle(color: AppTheme.textSecondary));
    if (mType == 'FILE') return Text("📎 Document", style: TextStyle(color: AppTheme.textSecondary));
    if (mType == 'CALL_LOG') return Text("📞 Call", style: TextStyle(color: AppTheme.textSecondary));

    final raw = (msg['content'] ?? '').toString().trim();
    if (raw.isEmpty) return Text("Sent a message", style: TextStyle(color: AppTheme.textSecondary));
    if (raw.startsWith('{') && (raw.contains('ciphertext') || raw.contains('e2ee'))) {
      return FutureBuilder<String>(
        future: CryptoService.instance.decryptIncomingContent(
          content: raw,
          senderUserId: (msg['senderId'] ?? '').toString(),
          conversationId: chat.id,
        ),
        builder: (context, snapshot) {
          final text = snapshot.data;
          if (text != null && text.isNotEmpty && text != raw && !text.contains('ciphertext')) {
            return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.textSecondary));
          }
          return Text("Message", style: TextStyle(color: AppTheme.textSecondary));
        },
      );
    }
    if (raw.contains(':') && raw.split(':').length == 3) {
      return Text("Message", style: TextStyle(color: AppTheme.textSecondary));
    }
    return Text(raw, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.textSecondary));
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
                    subtitle: _buildSubtitle(chat),
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
