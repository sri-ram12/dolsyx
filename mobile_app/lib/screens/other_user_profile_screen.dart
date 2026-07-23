import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';

class OtherUserProfileScreen extends StatelessWidget {
  final Map<String, dynamic> user;

  const OtherUserProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user['avatarUrl'];
    final username = user['username'] ?? 'User';
    final email = user['email'] ?? '';
    final bio = user['bio'] ?? 'No bio provided';

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
            CircleAvatar(
              radius: 60,
              backgroundColor: AppTheme.surfaceColor,
              backgroundImage: avatarUrl != null && avatarUrl.startsWith('http')
                  ? NetworkImage(avatarUrl)
                  : (avatarUrl != null ? NetworkImage('https://dolsyx-app.onrender.com$avatarUrl') : null),
              child: avatarUrl == null ? const Icon(Icons.person, size: 60, color: AppTheme.textSecondary) : null,
            ),
            const SizedBox(height: 24),
            Text(
              username,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            Text(
              email,
              style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
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
                  const Text('About', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(bio, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
