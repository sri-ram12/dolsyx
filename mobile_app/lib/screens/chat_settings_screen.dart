import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  String _selectedTheme = 'Dark';
  double _fontSize = 15.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Display', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_medium, color: AppTheme.textSecondary),
            title: const Text('Theme', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_selectedTheme, style: const TextStyle(color: AppTheme.textSecondary)),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: AppTheme.surfaceColor,
                    title: const Text('Choose theme', style: TextStyle(color: AppTheme.textPrimary)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildThemeOption('Light'),
                        _buildThemeOption('Dark'),
                        _buildThemeOption('Aqua Sky Blue'),
                        _buildThemeOption('Violet'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel', style: TextStyle(color: AppTheme.primaryColor)),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.wallpaper, color: AppTheme.textSecondary),
            title: const Text('Wallpaper', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () {},
          ),
          const Divider(color: Colors.grey),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Chat settings', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: const Text('Enter is send', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: const Text('Enter key will send your message', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: false,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {},
          ),
          ListTile(
            title: const Text('Font size', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_fontSize == 12 ? 'Small' : _fontSize == 15 ? 'Medium' : 'Large', style: const TextStyle(color: AppTheme.textSecondary)),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: AppTheme.surfaceColor,
                    title: const Text('Font size', style: TextStyle(color: AppTheme.textPrimary)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<double>(
                          title: const Text('Small', style: TextStyle(color: AppTheme.textPrimary)),
                          value: 12.0,
                          groupValue: _fontSize,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            setState(() => _fontSize = val!);
                            Navigator.pop(context);
                          },
                        ),
                        RadioListTile<double>(
                          title: const Text('Medium', style: TextStyle(color: AppTheme.textPrimary)),
                          value: 15.0,
                          groupValue: _fontSize,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            setState(() => _fontSize = val!);
                            Navigator.pop(context);
                          },
                        ),
                        RadioListTile<double>(
                          title: const Text('Large', style: TextStyle(color: AppTheme.textPrimary)),
                          value: 18.0,
                          groupValue: _fontSize,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            setState(() => _fontSize = val!);
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
        ],
      ),
    );
  }

  Widget _buildThemeOption(String themeName) {
    return RadioListTile<String>(
      title: Text(themeName, style: const TextStyle(color: AppTheme.textPrimary)),
      value: themeName,
      groupValue: _selectedTheme,
      activeColor: AppTheme.primaryColor,
      onChanged: (val) {
        setState(() {
          _selectedTheme = val!;
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$themeName theme selected.')),
        );
      },
    );
  }
}
