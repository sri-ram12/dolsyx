import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/group_service.dart';
import '../services/contact_service.dart';
import '../providers/auth_provider.dart';
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
  late String _groupName;
  bool _isAdmin = false;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _participants = List.from(widget.participants);
    _groupName = widget.groupName;
    _checkAdminStatus();
  }

  void _checkAdminStatus() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _myUserId = auth.user?['id'] ?? auth.user?['_id'];
    if (_myUserId != null) {
      final myPart = _participants.firstWhere(
        (p) => p['user'] != null && (p['user']['id'] == _myUserId || p['user']['_id'] == _myUserId),
        orElse: () => null,
      );
      if (myPart != null) {
        _isAdmin = myPart['role'] == 'OWNER' || myPart['role'] == 'ADMIN' || myPart['role'] == 'owner' || myPart['role'] == 'admin';
      }
    }
  }

  Future<void> _removeMember(String userId) async {
    final success = await _groupService.removeMember(widget.conversationId, userId);
    if (success && mounted) {
      setState(() {
        _participants.removeWhere((p) => p['user'] != null && (p['user']['id'] == userId || p['user']['_id'] == userId));
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member removed')));
      _checkAdminStatus();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove member')));
    }
  }

  Future<void> _addMemberFlow() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
    final contacts = await ContactService.getContacts(token);
    
    // Filter contacts that are not already participants
    final List<dynamic> availableContacts = contacts.where((c) {
      final contactUser = c['contact'];
      if (contactUser == null) return false;
      final contactId = contactUser['id'] ?? contactUser['_id'];
      return !_participants.any((p) => p['user'] != null && (p['user']['id'] == contactId || p['user']['_id'] == contactId));
    }).toList();

    if (!mounted) return;

    if (availableContacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contacts available to add')));
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundColor,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Member', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: availableContacts.length,
                  itemBuilder: (ctx, idx) {
                    final contact = availableContacts[idx];
                    final user = contact['contact'];
                    final displayName = contact['savedName'] ?? user['username'] ?? 'Unknown';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user['avatarUrl'] != null && user['avatarUrl'].startsWith('http')
                            ? NetworkImage(user['avatarUrl'])
                            : null,
                        child: user['avatarUrl'] == null ? const Icon(Icons.person) : null,
                      ),
                      title: Text(displayName, style: TextStyle(color: AppTheme.textPrimary)),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        final targetUserId = user['id'] ?? user['_id'];
                        final ok = await _groupService.addMember(widget.conversationId, targetUserId);
                        if (ok && mounted) {
                          setState(() {
                            _participants.add({
                              'userId': targetUserId,
                              'role': 'MEMBER',
                              'user': user,
                            });
                          });
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$displayName added')));
                          _checkAdminStatus();
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to add member')));
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editGroupProfile() async {
    final nameController = TextEditingController(text: _groupName);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: Text('Edit Group Profile', style: TextStyle(color: AppTheme.textPrimary)),
          content: TextField(
            controller: nameController,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Group Name',
              labelStyle: TextStyle(color: AppTheme.textSecondary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty) {
                  Navigator.pop(ctx);
                  final ok = await _groupService.updateGroup(widget.conversationId, newName, null, null);
                  if (ok && mounted) {
                    setState(() {
                      _groupName = newName;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group updated')));
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update group')));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editGroupProfile,
            ),
        ],
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
                CircleAvatar(
                  radius: 50,
                  backgroundColor: AppTheme.primaryColor,
                  child: const Icon(Icons.group, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(_groupName, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                Text('${_participants.length} members', style: TextStyle(color: AppTheme.textSecondary)),
                if (_isAdmin) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _addMemberFlow,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add Member'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
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

                final userId = user['id'] ?? user['_id'];
                final role = participant['role'].toString().toUpperCase();
                final isOwner = role == 'OWNER' || role == 'ADMIN';
                final isMe = userId == _myUserId;
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user['avatarUrl'] != null && user['avatarUrl'].toString().startsWith('http')
                        ? NetworkImage(user['avatarUrl'])
                        : null,
                    child: user['avatarUrl'] == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(user['username'] ?? 'Unknown', style: TextStyle(color: AppTheme.textPrimary)),
                  subtitle: Text(isOwner ? 'Group Admin' : 'Member', style: TextStyle(color: AppTheme.textSecondary)),
                  trailing: (_isAdmin && !isOwner && !isMe)
                      ? IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                          onPressed: () => _removeMember(userId),
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
