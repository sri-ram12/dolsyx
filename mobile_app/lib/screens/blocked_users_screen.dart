import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBlockedUsers();
  }

  Future<void> _fetchBlockedUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final users = await _apiService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fetch blocked users error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unblockUser(String userId, String username) async {
    final success = await _apiService.unblockUser(userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? '$username unblocked' : 'Failed to unblock user')),
      );
      if (success) _fetchBlockedUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
        backgroundColor: AppTheme.surfaceColor,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _blockedUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block_outlined, size: 64, color: AppTheme.textSecondary),
                      const SizedBox(height: 16),
                      Text(
                        'No blocked users',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 18),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _blockedUsers.length,
                  separatorBuilder: (_, __) => Divider(color: AppTheme.surfaceColor, height: 1),
                  itemBuilder: (context, index) {
                    final record = _blockedUsers[index];
                    final blockedUser = record['blockedUser'];
                    if (blockedUser == null) return const SizedBox.shrink();

                    final avatarUrl = blockedUser['avatarUrl']?.toString();
                    final username = blockedUser['username']?.toString() ?? 'Unknown User';
                    final userId = blockedUser['id']?.toString() ?? blockedUser['_id']?.toString() ?? '';

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: AppTheme.surfaceColor,
                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                            ? (avatarUrl.startsWith('http')
                                ? NetworkImage(avatarUrl)
                                : NetworkImage('https://dolsyx-app.onrender.com$avatarUrl')) as ImageProvider
                            : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? Text(
                                username.isNotEmpty ? username[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      title: Text(username, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                      subtitle: Text('Blocked', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      trailing: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.primaryColor),
                          foregroundColor: AppTheme.primaryColor,
                        ),
                        onPressed: () => _unblockUser(userId, username),
                        child: const Text('Unblock'),
                      ),
                    );
                  },
                ),
    );
  }
}
