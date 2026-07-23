import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'call_screen.dart';

class OtherUserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const OtherUserProfileScreen({super.key, required this.user});

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  final ApiService _apiService = ApiService();
  bool _isProcessing = false;
  String? _localNickname;

  void _blockUser() async {
    setState(() => _isProcessing = true);
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (userId != null) {
      final success = await _apiService.blockUser(userId);
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'User blocked successfully' : 'Failed to block user')),
        );
        if (success) Navigator.pop(context);
      }
    }
  }

  void _editName() {
    final TextEditingController controller = TextEditingController(text: _localNickname ?? widget.user['username']);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: Text('Edit Name', style: TextStyle(color: AppTheme.textPrimary)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter name',
              hintStyle: TextStyle(color: AppTheme.textSecondary),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _localNickname = controller.text;
                });
                Navigator.pop(context);
              },
              child: const Text('Save', style: TextStyle(color: AppTheme.primaryColor)),
            ),
          ],
        );
      }
    );
  }

  void _makeCall(bool isVideo) {
    final userId = widget.user['id'] ?? widget.user['_id'];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          remoteUserId: userId,
          remoteUserName: _localNickname ?? widget.user['username'] ?? 'User',
          isVideo: isVideo,
        ),
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String text, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? Colors.redAccent : AppTheme.primaryColor),
      title: Text(text, style: TextStyle(color: isDestructive ? Colors.redAccent : AppTheme.textPrimary)),
      onTap: onTap,
    );
  }

  Widget _buildHeaderAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: AppTheme.primaryColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.user['avatarUrl'];
    final username = _localNickname ?? widget.user['username'] ?? 'User';
    final email = widget.user['email'] ?? '';
    final bio = widget.user['bio'] ?? 'Hey there, I am using DOLSYX';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Info'),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'edit_name') {
                _editName();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit_name',
                child: Text('Edit Name'),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              color: AppTheme.surfaceColor,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: AppTheme.backgroundColor,
                    backgroundImage: avatarUrl != null && avatarUrl.startsWith('http')
                        ? NetworkImage(avatarUrl)
                        : (avatarUrl != null ? NetworkImage('https://dolsyx-app.onrender.com$avatarUrl') : null),
                    child: avatarUrl == null ? Icon(Icons.person, size: 60, color: AppTheme.textSecondary) : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    username,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  Text(
                    email,
                    style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildHeaderAction(Icons.call, 'Audio', () => _makeCall(false)),
                      _buildHeaderAction(Icons.videocam, 'Video', () => _makeCall(true)),
                      _buildHeaderAction(Icons.search, 'Search', () {}),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Container(
              color: AppTheme.surfaceColor,
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(bio, style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Container(
              color: AppTheme.surfaceColor,
              child: Column(
                children: [
                  _buildActionItem(Icons.notifications, 'Notifications', () {}),
                  _buildActionItem(Icons.timelapse, 'Disappearing Messages', () {}),
                  _buildActionItem(Icons.lock, 'Chat Lock', () {}),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Container(
              color: AppTheme.surfaceColor,
              child: Column(
                children: [
                  _buildActionItem(Icons.group_add, 'Create group with user', () {}),
                  _buildActionItem(Icons.group, 'Add to group', () {}),
                  _buildActionItem(Icons.star, 'Add to favourite', () {}),
                  _buildActionItem(Icons.delete_outline, 'Clear chat', () {}, isDestructive: true),
                  _buildActionItem(Icons.block, 'Block user', _blockUser, isDestructive: true),
                  _buildActionItem(Icons.thumb_down_alt_outlined, 'Report user', () {}, isDestructive: true),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
