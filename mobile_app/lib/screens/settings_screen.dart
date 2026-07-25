import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';
import 'privacy_settings_screen.dart';
import 'app_lock_screen.dart';
import 'chat_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user;

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.backgroundColor,
                backgroundImage: user?['avatarUrl'] != null && user!['avatarUrl'].startsWith('http')
                    ? NetworkImage(user!['avatarUrl'])
                    : (user?['avatarUrl'] != null ? NetworkImage('https://dolsyx-app.onrender.com${user!['avatarUrl']}') : null),
                child: user?['avatarUrl'] == null ? Icon(Icons.person, size: 30, color: AppTheme.textSecondary) : null,
              ),
              title: Text(user?['username'] ?? 'User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              subtitle: Text(user?['bio'] ?? 'Hey there, I am using DOLSYX', style: TextStyle(color: AppTheme.textSecondary)),
              trailing: Icon(Icons.qr_code, color: AppTheme.primaryColor),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              },
            ),
            const Divider(color: Colors.grey, height: 1),
            _buildSettingItem(context, Icons.notifications, 'Notification Tones & Call Ringtones', 'Message sounds, caller tones, custom device tones', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()));
            }),
            _buildSettingItem(context, Icons.key, 'Account', 'Security notifications, change number', () {}),
            _buildSettingItem(context, Icons.lock, 'Privacy', 'Block contacts, disappearing messages', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()));
            }),
            _buildSettingItem(context, Icons.chat, 'Chats', 'Theme, wallpapers, chat history', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatSettingsScreen()));
            }),
            _buildSettingItem(context, Icons.data_usage, 'Storage and data', 'Network usage, auto-download', () {}),
            _buildSettingItem(context, Icons.fingerprint, 'App Lock', 'Require biometric or PIN', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AppLockScreen()));
            }),
            _buildSettingItem(context, Icons.help_outline, 'Help', 'Help center, contact us, privacy policy', () {}),
            _buildSettingItem(context, Icons.group, 'Invite a friend', '', () {}),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Icon(icon, color: AppTheme.textSecondary),
      ),
      title: Text(title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)) : null,
      onTap: onTap,
    );
  }
}
