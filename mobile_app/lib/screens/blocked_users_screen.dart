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
    setState(() => _isLoading = true);
    final users = await _apiService.getBlockedUsers();
    if (mounted) {
      setState(() {
        _blockedUsers = users;
        _isLoading = false;
      });
    }
  }

  Future<void> _unblockUser(String userId) async {
    final success = await _apiService.unblockUser(userId);
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User unblocked')));
        _fetchBlockedUsers(); // Refresh
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to unblock user')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _blockedUsers.isEmpty
              ? Center(
                  child: Text('No blocked users', style: TextStyle(color: AppTheme.textSecondary)),
                )
              : ListView.builder(
                  itemCount: _blockedUsers.length,
                  itemBuilder: (context, index) {
                    final blockedRecord = _blockedUsers[index];
                    final blockedUser = blockedRecord['blockedUser']; // based on auth.controller.ts getBlockedUsers populating blockedUser
                    if (blockedUser == null) return const SizedBox.shrink();

                    final avatarUrl = blockedUser['avatarUrl'];
                    final username = blockedUser['username'] ?? 'Unknown User';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.surfaceColor,
                        backgroundImage: avatarUrl != null && avatarUrl.startsWith('http')
                            ? NetworkImage(avatarUrl)
                            : (avatarUrl != null ? NetworkImage('https://dolsyx-app.onrender.com$avatarUrl') : null),
                        child: avatarUrl == null ? Icon(Icons.person, color: AppTheme.textSecondary) : null,
                      ),
                      title: Text(username, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: BorderSide(color: AppTheme.primaryColor),
                        ),
                        onPressed: () => _unblockUser(blockedUser['_id'] ?? blockedUser['id']),
                        child: Text('Unblock', style: TextStyle(color: AppTheme.primaryColor)),
                      ),
                    );
                  },
                ),
    );
  }
}
