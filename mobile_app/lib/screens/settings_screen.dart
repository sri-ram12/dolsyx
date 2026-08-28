import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'profile_screen.dart';
import 'privacy_settings_screen.dart';
import 'account_settings_screen.dart';
import 'help_settings_screen.dart';
import 'app_lock_screen.dart';
import 'chat_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'storage_settings_screen.dart';
import '../widgets/switch_account_modal.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
            _buildSettingItem(context, Icons.switch_account, 'Switch Account', 'Switch between logged-in accounts or add account', () {
              SwitchAccountModal.show(context);
            }),
            _buildSettingItem(context, Icons.notifications, 'Notification Tones & Call Ringtones', 'Message sounds, caller tones, custom device tones', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()));
            }),
            _buildSettingItem(context, Icons.key, 'Account', 'Security notifications, two-factor auth, delete account', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsScreen()));
            }),
            _buildSettingItem(context, Icons.lock, 'Privacy', 'Block contacts, disappearing messages', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()));
            }),
            _buildSettingItem(context, Icons.chat, 'Chats', 'Theme, wallpapers, chat history', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatSettingsScreen()));
            }),
            _buildSettingItem(context, Icons.data_usage, 'Storage and data', 'Network usage, auto-download, clear cache', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const StorageSettingsScreen()));
            }),
            _buildSettingItem(context, Icons.fingerprint, 'App Lock', 'Require biometric or PIN', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AppLockScreen()));
            }),
            _buildSettingItem(context, Icons.help_outline, 'Help', 'Help center, contact us, privacy policy & terms', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSettingsScreen()));
            }),
            _buildSettingItem(context, Icons.group, 'Invite a friend', 'Share DOLSYX with your friends and family', () {
              Share.share(
                'Experience fast, secure, end-to-end encrypted messaging and crystal-clear calls on DOLSYX! Join now: https://dolsyx-app.onrender.com',
                subject: 'Join me on DOLSYX',
              );
            }),
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
