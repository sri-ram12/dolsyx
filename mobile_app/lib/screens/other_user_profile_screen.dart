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
        if (success) Navigator.pop(context); // Close profile after blocking
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.user['avatarUrl'];
    final username = widget.user['username'] ?? 'User';
    final email = widget.user['email'] ?? '';
    final bio = widget.user['bio'] ?? 'No bio provided';

    return Scaffold(
      appBar: AppBar(
        title: Text(username),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: AppTheme.surfaceColor,
                  builder: (sheetContext) {
                    return SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: Icon(Icons.phone, color: AppTheme.primaryColor),
                            title: Text('Voice Call', style: TextStyle(color: AppTheme.textPrimary)),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CallScreen(
                                    remoteUserId: widget.user['id'] ?? widget.user['_id'],
                                    remoteUserName: username,
                                    isVideo: false,
                                  ),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.videocam, color: AppTheme.primaryColor),
                            title: Text('Video Call', style: TextStyle(color: AppTheme.textPrimary)),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CallScreen(
                                    remoteUserId: widget.user['id'] ?? widget.user['_id'],
                                    remoteUserName: username,
                                    isVideo: true,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              child: CircleAvatar(
                radius: 60,
                backgroundColor: AppTheme.surfaceColor,
                backgroundImage: avatarUrl != null && avatarUrl.startsWith('http')
                    ? NetworkImage(avatarUrl)
                    : (avatarUrl != null ? NetworkImage('https://dolsyx-app.onrender.com$avatarUrl') : null),
                child: avatarUrl == null ? Icon(Icons.person, size: 60, color: AppTheme.textSecondary) : null,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              username,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            Text(
              email,
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(bio, style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _blockUser,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.1),
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
                icon: _isProcessing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                  : const Icon(Icons.block),
                label: Text(_isProcessing ? 'Blocking...' : 'Block User'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
