import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Who can see my personal info', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          _buildPrivacyOption('Last seen and online', 'Everyone'),
          _buildPrivacyOption('Profile photo', 'Everyone'),
          _buildPrivacyOption('About', 'Everyone'),
          _buildPrivacyOption('Status', 'My contacts'),
          SwitchListTile(
            title: const Text('Read receipts', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: const Text('If turned off, you won\'t send or receive Read receipts. Read receipts are always sent for group chats.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: true,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {},
          ),
          const Divider(color: Colors.grey),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Disappearing messages', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          _buildPrivacyOption('Default message timer', 'Off'),
          const Divider(color: Colors.grey),
          _buildPrivacyOption('Blocked contacts', 'None'),
        ],
      ),
    );
  }

  Widget _buildPrivacyOption(String title, String value) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
      subtitle: Text(value, style: const TextStyle(color: AppTheme.textSecondary)),
      onTap: () {},
    );
  }
}
