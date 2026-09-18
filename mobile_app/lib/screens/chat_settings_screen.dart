import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/backup_service.dart';

import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'theme_settings_screen.dart';
import 'wallpaper_settings_screen.dart';

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final _selectedTheme = themeProvider.currentTheme;
    final _fontSize = themeProvider.currentFontSize;

    return Scaffold(
      appBar: AppBar(
        title: Text('Chats'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Display', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: Icon(Icons.brightness_medium, color: AppTheme.textSecondary),
            title: Text('App theme', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_selectedTheme.name, style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ThemeSettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.wallpaper, color: AppTheme.textSecondary),
            title: Text('Wallpaper', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WallpaperSettingsScreen()),
              );
            },
          ),
          const Divider(color: Colors.grey),
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Chat settings', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: Text('Enter is send', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Enter key will send your message', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: false,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {},
          ),
          ListTile(
            title: Text('Font size', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_fontSize <= 14 ? 'Small (14px)' : _fontSize <= 16 ? 'Medium (16px)' : 'Large (18px)', style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: AppTheme.surfaceColor,
                    title: Text('Font size', style: TextStyle(color: AppTheme.textPrimary)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<double>(
                          title: Text('Small (14px)', style: TextStyle(color: AppTheme.textPrimary)),
                          value: 14.0,
                          groupValue: _fontSize,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            themeProvider.setFontSize(val!);
                            Navigator.pop(context);
                          },
                        ),
                        RadioListTile<double>(
                          title: Text('Medium (16px)', style: TextStyle(color: AppTheme.textPrimary)),
                          value: 16.0,
                          groupValue: _fontSize,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            themeProvider.setFontSize(val!);
                            Navigator.pop(context);
                          },
                        ),
                        RadioListTile<double>(
                          title: Text('Large (18px)', style: TextStyle(color: AppTheme.textPrimary)),
                          value: 18.0,
                          groupValue: _fontSize,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            themeProvider.setFontSize(val!);
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.backup, color: AppTheme.textSecondary),
            title: Text('Chat backup & restore', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Export & restore encrypted .dolsyx backups', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: _showBackupDialog,
          ),
        ],
      ),
    );
  }

  void _showBackupDialog() {
    final passphraseCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Encrypted Chat Backup', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter a secret passphrase to encrypt your local chat backup file (.dolsyx):', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: passphraseCtrl,
              obscureText: true,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Secret Passphrase',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            onPressed: () async {
              final pass = passphraseCtrl.text.trim();
              if (pass.length < 4) return;
              Navigator.pop(ctx);
              final file = await BackupService().exportEncryptedBackup(passphrase: pass, messages: []);
              if (file != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green,
                    content: Text('🟢 Encrypted backup exported to ${file.path.split('/').last}'),
                  ),
                );
              }
            },
            child: const Text('Export Backup', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
