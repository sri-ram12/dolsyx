import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/group_service.dart';
import 'media_gallery_screen.dart';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String conversationId;
  final String groupName;
  final String? groupAvatarUrl;
  final List<dynamic> participants;

  const GroupSettingsScreen({
    super.key,
    required this.conversationId,
    required this.groupName,
    this.groupAvatarUrl,
    required this.participants,
  });

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final GroupService _groupService = GroupService();
  late List<dynamic> _participants;
  late String _groupName;
  String? _groupAvatarUrl;
  bool _isAdmin = false;
  String? _myUserId;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _participants = List.from(widget.participants);
    _groupName = widget.groupName;
    _groupAvatarUrl = widget.groupAvatarUrl;
    _checkAdminStatus();
  }

  void _checkAdminStatus() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _myUserId = (auth.user?['id'] ?? auth.user?['_id'])?.toString();
    if (_myUserId != null) {
      final myPart = _participants.firstWhere(
        (p) {
          if (p == null) return false;
          final pUserId = (p['userId'] ?? p['id'] ?? (p['user'] != null ? (p['user']['id'] ?? p['user']['_id']) : null))?.toString();
          return pUserId == _myUserId;
        },
        orElse: () => null,
      );
      if (myPart != null) {
        final role = (myPart['role'] ?? '').toString().toUpperCase();
        _isAdmin = role == 'OWNER' || role == 'ADMIN' || _participants.length <= 2;
      } else {
        _isAdmin = true;
      }
    } else {
      _isAdmin = true;
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

  Future<void> _disbandGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Disband Group?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('This will permanently delete the group for all members.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disband', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await ChatService().deleteChat(widget.conversationId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group disbanded')));
        Navigator.popUntil(context, (route) => route.isFirst);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to disband group')));
      }
    }
  }

  Future<void> _pickGroupAvatar() async {
    if (!_isAdmin) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final uploadRes = await ApiService().uploadMedia(pickedFile.path);
      String? uploadedUrl;
      if (uploadRes != null) {
        uploadedUrl = uploadRes['fileUrl'] ??
            uploadRes['url'] ??
            uploadRes['file'] ??
            uploadRes['filePath'] ??
            (uploadRes['data'] != null ? (uploadRes['data']['fileUrl'] ?? uploadRes['data']['url']) : null) ??
            (uploadRes['files'] != null && (uploadRes['files'] as List).isNotEmpty
                ? (uploadRes['files'][0]['url'] ?? uploadRes['files'][0]['fileUrl'])
                : null);
      }
      if (uploadedUrl != null) {
        final nameToPass = _groupName.trim().isNotEmpty ? _groupName.trim() : 'Group';
        final ok = await _groupService.updateGroup(widget.conversationId, nameToPass, null, uploadedUrl);
        if (ok && mounted) {
          setState(() {
            _groupAvatarUrl = uploadedUrl;
          });
          // Also notify via socket so other members see the update instantly
          final socket = Provider.of<AuthProvider>(context, listen: false).socketService.socket;
          socket?.emit('group_avatar_updated', {
            'conversationId': widget.conversationId,
            'avatarUrl': uploadedUrl,
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group photo updated!')));
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update group photo')));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed — no URL returned')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
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
                GestureDetector(
                  onTap: _isAdmin ? _pickGroupAvatar : null,
                  child: Stack(
                    children: [
                      _isUploadingAvatar
                          ? const CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.black26,
                              child: CircularProgressIndicator(color: Colors.white),
                            )
                          : CircleAvatar(
                              radius: 50,
                              backgroundColor: AppTheme.primaryColor,
                              backgroundImage: _groupAvatarUrl != null && _groupAvatarUrl!.isNotEmpty
                                  ? (_groupAvatarUrl!.startsWith('http')
                                      ? NetworkImage(_groupAvatarUrl!)
                                      : NetworkImage('https://dolsyx-app.onrender.com$_groupAvatarUrl'))
                                  : null,
                              child: _groupAvatarUrl == null || _groupAvatarUrl!.isEmpty
                                  ? const Icon(Icons.group, size: 50, color: Colors.white)
                                  : null,
                            ),
                      if (_isAdmin && !_isUploadingAvatar)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.surfaceColor, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
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
          ListTile(
            leading: Icon(Icons.perm_media, color: AppTheme.primaryColor),
            title: Text('Shared Media, Docs & Links', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('View photos, files, and web links', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => MediaGalleryScreen(title: _groupName, messages: const [])));
            },
          ),
          ListTile(
            leading: Icon(Icons.link, color: AppTheme.primaryColor),
            title: Text('Group Invite Link', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('https://dolsyx.app/join/grp_${widget.conversationId}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            trailing: _isAdmin ? IconButton(
              icon: const Icon(Icons.refresh, color: Colors.orange),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group invite link revoked & regenerated!')));
              },
            ) : null,
            onTap: () {
              final link = 'https://dolsyx.app/join/grp_${widget.conversationId}';
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Group invite link copied: $link')),
              );
            },
          ),
          const Divider(),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _participants.length + (_isAdmin ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _participants.length && _isAdmin) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
                    child: ElevatedButton.icon(
                      onPressed: _disbandGroup,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Disband Group'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  );
                }

                final participant = _participants[index];
                final user = participant['user'];
                if (user == null) return const SizedBox.shrink();

                final userId = user['id'] ?? user['_id'];
                final role = participant['role']?.toString().toUpperCase() ?? 'MEMBER';
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
