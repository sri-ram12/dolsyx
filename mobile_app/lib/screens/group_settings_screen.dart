import 'package:flutter/material.dart';
import '../services/group_service.dart';
import '../theme/app_theme.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String conversationId;
  final String groupName;
  final List<dynamic> participants;

  const GroupSettingsScreen({
    super.key,
    required this.conversationId,
    required this.groupName,
    required this.participants,
  });

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final GroupService _groupService = GroupService();
  late List<dynamic> _participants;

  @override
  void initState() {
    super.initState();
    _participants = List.from(widget.participants);
  }

  Future<void> _removeMember(String userId) async {
    final success = await _groupService.removeMember(widget.conversationId, userId);
    if (success && mounted) {
      setState(() {
        _participants.removeWhere((p) => p['user']['_id'] == userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member removed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24.0),
            color: AppTheme.surfaceColor,
            width: double.infinity,
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: AppTheme.primaryColor,
                  child: Icon(Icons.group, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(widget.groupName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                Text('${_participants.length} members', style: const TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _participants.length,
              itemBuilder: (context, index) {
                final participant = _participants[index];
                final user = participant['user'];
                if (user == null) return const SizedBox.shrink();

                final isOwner = participant['role'] == 'owner';
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user['avatarUrl'] != null && user['avatarUrl'].startsWith('http')
                        ? NetworkImage(user['avatarUrl'])
                        : null,
                    child: user['avatarUrl'] == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(user['username'], style: const TextStyle(color: AppTheme.textPrimary)),
                  subtitle: Text(isOwner ? 'Group Admin' : 'Member', style: const TextStyle(color: AppTheme.textSecondary)),
                  trailing: !isOwner
                      ? IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                          onPressed: () => _removeMember(user['_id']),
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
