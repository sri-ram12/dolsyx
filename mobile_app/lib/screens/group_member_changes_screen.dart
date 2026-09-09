import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import '../services/chat_service.dart';
import '../services/api_service.dart';

class GroupMemberChangesScreen extends StatefulWidget {
  final String groupName;
  final String conversationId;
  final List<dynamic>? currentParticipants;

  const GroupMemberChangesScreen({
    super.key,
    required this.groupName,
    required this.conversationId,
    this.currentParticipants,
  });

  @override
  State<GroupMemberChangesScreen> createState() => _GroupMemberChangesScreenState();
}

class _GroupMemberChangesScreenState extends State<GroupMemberChangesScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';
  bool _isLoading = true;

  List<Map<String, dynamic>> _memberHistory = [];

  @override
  void initState() {
    super.initState();
    _loadRealHistory();
  }

  Future<void> _loadRealHistory() async {
    setState(() => _isLoading = true);
    final List<Map<String, dynamic>> history = [];
    final now = DateTime.now();

    try {
      final remoteHistory = await ApiService().getPastParticipants(widget.conversationId);
      if (remoteHistory.isNotEmpty) {
        for (var item in remoteHistory) {
          final dt = DateTime.tryParse(item['createdAt']?.toString() ?? '') ?? now;
          String dateStr = '${dt.day}/${dt.month}/${dt.year}';
          if (now.difference(dt).inDays == 0 && now.day == dt.day) {
            dateStr = 'Today';
          } else if (now.difference(dt).inDays <= 1) {
            dateStr = 'Yesterday';
          }

          final timeStr = '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';

          history.add({
            'id': item['id'] ?? UniqueKey().toString(),
            'name': item['name'] ?? 'Participant',
            'phone': '',
            'action': item['action'] ?? 'changed',
            'actionText': item['actionText'] ?? 'Member change',
            'date': dateStr,
            'time': timeStr,
            'avatarUrl': null,
          });
        }
      } else {
        final messages = await ChatService().getMessages(widget.conversationId);
        final sixtyDaysAgo = now.subtract(const Duration(days: 60));

        final systemMessages = messages.where((m) {
          if (m.createdAt.isBefore(sixtyDaysAgo)) return false;
          final content = m.content.toLowerCase();
          return m.mediaType == 'SYSTEM' ||
              m.senderId == 'system' ||
              content.contains('left the group') ||
              content.contains('left group') ||
              content.contains(' added ') ||
              content.contains(' removed ') ||
              content.contains('joined');
        }).toList();

        for (var msg in systemMessages) {
          String action = 'changed';
          String actionText = msg.content.replaceFirst('SYSTEM:', '').trim();
          final lower = actionText.toLowerCase();

          String name = 'Group Member';
          if (lower.contains(' left')) {
            action = 'left';
            name = actionText.split(RegExp(r'\s+left', caseSensitive: false)).first.trim();
          } else if (lower.contains(' removed ')) {
            action = 'removed';
            final parts = actionText.split(RegExp(r'\s+removed\s+', caseSensitive: false));
            name = parts.length > 1 ? parts[1].replaceFirst(RegExp(r'\s+from group$', caseSensitive: false), '').trim() : parts[0].trim();
          } else if (lower.contains(' added ')) {
            action = 'joined';
            final parts = actionText.split(RegExp(r'\s+added\s+', caseSensitive: false));
            name = parts.length > 1 ? parts[1].replaceFirst(RegExp(r'\s+to group$', caseSensitive: false), '').trim() : parts[0].trim();
          } else if (lower.contains(' joined')) {
            action = 'joined';
            name = actionText.split(RegExp(r'\s+joined', caseSensitive: false)).first.trim();
          }

          final dt = msg.createdAt;
          String dateStr = '${dt.day}/${dt.month}/${dt.year}';
          if (now.difference(dt).inDays == 0 && now.day == dt.day) {
            dateStr = 'Today';
          } else if (now.difference(dt).inDays <= 1) {
            dateStr = 'Yesterday';
          }

          final timeStr = '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';

          history.add({
            'id': msg.id,
            'name': name.isEmpty ? 'Participant' : name,
            'phone': '',
            'action': action,
            'actionText': actionText,
            'date': dateStr,
            'time': timeStr,
            'avatarUrl': null,
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading member history: $e');
    }

    if (mounted) {
      setState(() {
        _memberHistory = history;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _memberHistory.where((item) {
      final name = (item['name'] ?? '').toLowerCase();
      final phone = (item['phone'] ?? '').toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search past participants...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Past participants', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(
                    '${_memberHistory.length} member events',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info banner matching frame_0208s.jpg
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: AppTheme.surfaceColor.withOpacity(0.5),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Color(0xFF00A884)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Only participants who left or were removed from ${widget.groupName} in the past 60 days are shown here.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.3),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off_outlined, size: 56, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isEmpty ? 'No past participants' : 'No matching participants found',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final action = item['action'];
                      Color actionColor = Colors.grey;
                      IconData actionIcon = Icons.exit_to_app;

                      if (action == 'left') {
                        actionColor = Colors.orangeAccent;
                        actionIcon = Icons.logout;
                      } else if (action == 'removed') {
                        actionColor = Colors.redAccent;
                        actionIcon = Icons.remove_circle_outline;
                      } else if (action == 'joined') {
                        actionColor = const Color(0xFF00A884);
                        actionIcon = Icons.person_add_outlined;
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ColorAvatar(name: item['name'] ?? 'User', radius: 22),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(actionIcon, size: 14, color: actionColor),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          item['name'] ?? 'Participant',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Text(
                              item['actionText'] ?? '',
                              style: TextStyle(color: actionColor, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 6),
                            Text('•', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            const SizedBox(width: 6),
                            Text(
                              item['phone'] ?? '',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: Text(
                          item['date'] ?? '',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                        onTap: () {
                          // Show options to message or add contact
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: AppTheme.surfaceColor,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.chat, color: Color(0xFF00A884)),
                                    title: Text('Message ${item['name']}', style: TextStyle(color: AppTheme.textPrimary)),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Starting chat with ${item['name']}...')),
                                      );
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.person_add, color: Color(0xFF00A884)),
                                    title: const Text('Add to contacts', style: TextStyle(color: Colors.white)),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Contact info copied: ${item['phone']}')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
