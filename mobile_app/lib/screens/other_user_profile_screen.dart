import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import 'package:intl/intl.dart';
import '../widgets/color_avatar.dart';
import '../widgets/full_screen_image_view.dart';
import '../screens/call_screen.dart';

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
  bool _isBlocked = false;
  bool _isOnline = false;
  bool _isTyping = false;
  DateTime? _lastSeen;

  @override
  void initState() {
    super.initState();
    _checkBlockedStatus();
    // Initialize from widget data
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (widget.user['lastSeen'] != null) {
      _lastSeen = DateTime.tryParse(widget.user['lastSeen'].toString());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _isOnline = authProvider.socketService.onlineUserIds.contains(userId?.toString());
      setState(() {});
      authProvider.socketService.onStatusChange(_handleStatusChange);
      authProvider.socketService.onTypingChange(_handleTypingChange);
    });
  }

  @override
  void dispose() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.socketService.offStatusChange(_handleStatusChange);
    authProvider.socketService.offTypingChange(_handleTypingChange);
    super.dispose();
  }

  void _handleStatusChange(dynamic data) {
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (mounted && data['userId']?.toString() == userId?.toString()) {
      setState(() {
        _isOnline = data['status'] == 'online';
        if (data['lastSeen'] != null) {
          _lastSeen = DateTime.tryParse(data['lastSeen'].toString());
        }
      });
    }
  }

  void _handleTypingChange(dynamic data) {
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (mounted && data['userId']?.toString() == userId?.toString()) {
      setState(() {
        _isTyping = data['isTyping'] == true;
      });
    }
  }

  Future<void> _checkBlockedStatus() async {
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (userId != null) {
      final blockedUsers = await _apiService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _isBlocked = blockedUsers.any((u) {
            final blockedUser = u['blockedUser'];
            return blockedUser != null && (blockedUser['_id'] == userId || blockedUser['id'] == userId);
          });
        });
      }
    }
  }

  void _unblockUser() async {
    setState(() => _isProcessing = true);
    final userId = widget.user['id'] ?? widget.user['_id'];
    if (userId != null) {
      final success = await _apiService.unblockUser(userId);
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'User unblocked successfully' : 'Failed to unblock user')),
        );
        if (success) _checkBlockedStatus();
      }
    }
  }

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
        if (success) _checkBlockedStatus();
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
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryColor)),
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
              child: Text('Save', style: TextStyle(color: AppTheme.primaryColor)),
            ),
          ],
        );
      }
    );
  }

  void _startAudioCall() => _startCall(false);
  void _startVideoCall() => _startCall(true);

  Future<void> _startCall(bool isVideo) async {
    final remoteUserId = widget.user['id'] ?? widget.user['_id'];
    if (remoteUserId == null) return;

    String conversationId = widget.user['conversationId'] ?? '';
    
    if (conversationId.isEmpty) {
      setState(() => _isProcessing = true);
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final response = await http.post(
          Uri.parse('https://dolsyx-app.onrender.com/api/chats/direct'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${authProvider.token}',
          },
          body: jsonEncode({'targetUserId': remoteUserId}),
        );
        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          conversationId = data['id'];
        }
      } catch (e) {
        print(e);
      }
      setState(() => _isProcessing = false);
    }

    if (conversationId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            conversationId: conversationId,
            remoteUserId: remoteUserId,
            remoteUserName: _localNickname ?? widget.user['username'] ?? 'User',
            remoteAvatarUrl: widget.user['avatarUrl'],
            isAudioOnly: !isVideo,
            isIncoming: false,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to start call')));
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return "Unknown";
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inDays == 0 && now.day == time.day) {
      return 'Today at ${DateFormat('hh:mm a').format(time)}';
    } else if (difference.inDays == 1 || (difference.inDays == 0 && now.day != time.day)) {
      return 'Yesterday at ${DateFormat('hh:mm a').format(time)}';
    } else if (difference.inDays < 7) {
      return '${DateFormat('EEEE').format(time)} at ${DateFormat('hh:mm a').format(time)}';
    } else {
      return '${DateFormat('dd/MM/yyyy').format(time)} at ${DateFormat('hh:mm a').format(time)}';
    }
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
            SizedBox(height: 8),
            Text(label, style: TextStyle(color: AppTheme.primaryColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Clear this chat?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Messages will be removed for you on this device.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear chat', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final token = authProvider.token;
        final conversationId = widget.user['conversationId'] ?? '';
        if (conversationId.isEmpty) return;

        final response = await http.delete(
          Uri.parse('https://dolsyx-app.onrender.com/api/chat/$conversationId/messages'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared')));
          Navigator.pop(context); // Go back to chat screen
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to clear chat')));
        }
      } catch (e) {
        print(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.user['avatarUrl'];
    final username = _localNickname ?? widget.user['username'] ?? 'User';
    final email = widget.user['email'] ?? '';
    final bio = widget.user['bio'] ?? 'Hey there, I am using DOLSYX';

    return Scaffold(
      appBar: AppBar(
        title: Text('Contact Info'),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert),
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
            // Profile Header Card
            Container(
              color: AppTheme.surfaceColor,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Avatar
                  GestureDetector(
                    onTap: () {
                      if (avatarUrl != null) {
                        String fullUrl = avatarUrl.startsWith('http')
                            ? avatarUrl
                            : 'https://dolsyx-app.onrender.com$avatarUrl';
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullScreenImageView(imageUrl: fullUrl),
                          ),
                        );
                      }
                    },
                    child: avatarUrl == null
                        ? ColorAvatar(name: username, radius: 50, fontSize: 36)
                        : CircleAvatar(
                            radius: 50,
                            backgroundColor: AppTheme.backgroundColor,
                            backgroundImage: avatarUrl.startsWith('http')
                                ? NetworkImage(avatarUrl)
                                : NetworkImage('https://dolsyx-app.onrender.com$avatarUrl'),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    username,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Live presence badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isTyping
                          ? AppTheme.primaryColor.withOpacity(0.15)
                          : _isOnline
                              ? Colors.green.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _isTyping
                          ? '✏️ Typing...'
                          : _isOnline
                              ? '🟢 Online'
                              : (_lastSeen != null
                                  ? '🕐 Last seen ${_formatTime(_lastSeen!)}'
                                  : (widget.user['lastSeen'] != null
                                      ? '🕐 Last seen ${_formatTime(DateTime.tryParse(widget.user['lastSeen'].toString()))}'
                                      : '⚫ Offline')),
                      style: TextStyle(
                        color: _isTyping || _isOnline ? AppTheme.primaryColor : AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Action Buttons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildHeaderAction(Icons.call, 'Audio', _startAudioCall),
                      _buildHeaderAction(Icons.videocam, 'Video', _startVideoCall),
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
                  _buildActionItem(Icons.group_add, 'Create group with user', () {
                    // Navigate to group creation with this user pre-selected if supported
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select other participants in the New Group screen.')));
                  }),
                  _buildActionItem(Icons.group, 'Add to group', () {}),
                  _buildActionItem(Icons.star, 'Add to favourite', () {}),
                  _buildActionItem(Icons.delete_outline, 'Clear chat', _clearChat, isDestructive: true),
                  _isBlocked 
                      ? _buildActionItem(Icons.block, 'Unblock user', _unblockUser, isDestructive: false)
                      : _buildActionItem(Icons.block, 'Block user', _blockUser, isDestructive: true),
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
