import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/color_avatar.dart';

class ShareTargetScreen extends StatefulWidget {
  final Map<String, dynamic> sharedData;

  const ShareTargetScreen({
    super.key,
    required this.sharedData,
  });

  @override
  State<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends State<ShareTargetScreen> {
  final ChatService _chatService = ChatService();
  List<dynamic> _conversations = [];
  bool _isLoading = true;
  final Set<String> _selectedConversationIds = {};
  bool _isSending = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchConversations();
  }

  Future<void> _fetchConversations() async {
    try {
      final chats = await _chatService.getChats();
      if (mounted) {
        setState(() {
          _conversations = chats.map((c) => {
            'id': c.id,
            'name': c.name,
            'isGroup': c.isGroup,
            'groupAvatar': c.avatarUrl,
            'participants': c.participants?.map((p) => {
              'user': {
                'id': p is Map ? (p['user']?['id'] ?? p['userId']) : p,
                'username': p is Map ? (p['user']?['username'] ?? p['username']) : 'User',
                'avatarUrl': p is Map ? (p['user']?['avatarUrl'] ?? p['avatarUrl']) : null,
              }
            }).toList() ?? [],
          }).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendSharedContent() async {
    if (_selectedConversationIds.isEmpty || _isSending) return;
    setState(() => _isSending = true);

    final socketService = Provider.of<AuthProvider>(context, listen: false).socketService;
    final type = widget.sharedData['type'];
    final text = widget.sharedData['text'];
    final List<dynamic> uris = widget.sharedData['uris'] ?? [];

    for (final convId in _selectedConversationIds) {
      try {
        if (type == 'text' && text != null) {
          socketService.sendMessage(convId, text);
        } else if (uris.isNotEmpty) {
          for (final uri in uris) {
            socketService.sendMessage(convId, uri.toString(), mediaUrl: uri.toString(), mediaType: 'IMAGE');
          }
        }
      } catch (e) {
        debugPrint('[ShareTarget] Error sending to $convId: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shared successfully to ${_selectedConversationIds.length} chat(s)!'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'];

    final filteredConversations = _conversations.where((conv) {
      final isGroup = conv['isGroup'] ?? false;
      String name = 'Chat';
      if (isGroup) {
        name = conv['name'] ?? 'Group';
      } else {
        final participants = conv['participants'] as List<dynamic>? ?? [];
        final other = participants.firstWhere(
          (p) => (p['user']?['id'] ?? p['user']?['_id']) != currentUserId,
          orElse: () => null,
        );
        name = other?['user']?['username'] ?? 'User';
      }
      return name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Share to...',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Shared item preview header
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.sharedData['type'] == 'text' ? Icons.link_rounded : Icons.photo_library_rounded,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.sharedData['type'] == 'text' ? 'Shared Link / Text' : 'Shared Media from Gallery',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.sharedData['text'] ?? '${(widget.sharedData['uris'] as List?)?.length ?? 1} item(s) ready to send',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Search input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search contacts & groups...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Contacts/Groups List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
                : ListView.builder(
                    itemCount: filteredConversations.length,
                    itemBuilder: (context, index) {
                      final conv = filteredConversations[index];
                      final convId = conv['id'] ?? conv['_id'];
                      final isGroup = conv['isGroup'] ?? false;
                      final isSelected = _selectedConversationIds.contains(convId);

                      String name = 'Chat';
                      String? avatarUrl;
                      if (isGroup) {
                        name = conv['name'] ?? 'Group';
                        avatarUrl = conv['groupAvatar'];
                      } else {
                        final participants = conv['participants'] as List<dynamic>? ?? [];
                        final other = participants.firstWhere(
                          (p) => (p['user']?['id'] ?? p['user']?['_id']) != currentUserId,
                          orElse: () => null,
                        );
                        name = other?['user']?['username'] ?? 'User';
                        avatarUrl = other?['user']?['avatarUrl'];
                      }

                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: AppTheme.primaryColor,
                        checkColor: Colors.white,
                        onChanged: (bool? val) {
                          setState(() {
                            if (val == true) {
                              _selectedConversationIds.add(convId);
                            } else {
                              _selectedConversationIds.remove(convId);
                            }
                          });
                        },
                        secondary: avatarUrl != null && avatarUrl.isNotEmpty
                            ? CircleAvatar(
                                backgroundColor: const Color(0xFF1E293B),
                                backgroundImage: NetworkImage(avatarUrl.startsWith('http') ? avatarUrl : 'https://dolsyx-app.onrender.com$avatarUrl'),
                              )
                            : ColorAvatar(name: name, radius: 20),
                        title: Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          isGroup ? 'Group Chat' : 'Direct Message',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              disabledBackgroundColor: Colors.grey.shade800,
            ),
            onPressed: _selectedConversationIds.isEmpty || _isSending ? null : _sendSharedContent,
            icon: _isSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded, color: Colors.white),
            label: Text(
              _isSending ? 'Sending...' : 'Send to ${_selectedConversationIds.length} chat(s)',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
