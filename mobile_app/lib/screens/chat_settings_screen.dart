import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

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
            title: Text('Theme', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_selectedTheme, style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: AppTheme.surfaceColor,
                    title: Text('Choose theme', style: TextStyle(color: AppTheme.textPrimary)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildThemeOption('Light', themeProvider, _selectedTheme),
                        _buildThemeOption('Dark', themeProvider, _selectedTheme),
                        _buildThemeOption('Aqua Sky Blue', themeProvider, _selectedTheme),
                        _buildThemeOption('Lime', themeProvider, _selectedTheme),
                        _buildThemeOption('Violet', themeProvider, _selectedTheme),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: TextStyle(color: AppTheme.primaryColor)),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.wallpaper, color: AppTheme.textSecondary),
            title: Text('Wallpaper', style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () {},
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
            subtitle: Text(_fontSize == 12 ? 'Small' : _fontSize == 15 ? 'Medium' : 'Large', style: TextStyle(color: AppTheme.textSecondary)),
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
                          title: Text('Small', style: TextStyle(color: AppTheme.textPrimary)),
                          value: 12.0,
                          groupValue: _fontSize,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            themeProvider.setFontSize(val!);
                            Navigator.pop(context);
                          },
                        ),
                        RadioListTile<double>(
                          title: Text('Medium', style: TextStyle(color: AppTheme.textPrimary)),
                          value: 15.0,
                          groupValue: _fontSize,
                          activeColor: AppTheme.primaryColor,
                          onChanged: (val) {
                            themeProvider.setFontSize(val!);
                            Navigator.pop(context);
                          },
                        ),
                        RadioListTile<double>(
                          title: Text('Large', style: TextStyle(color: AppTheme.textPrimary)),
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
        ],
      ),
    );
  }

  Widget _buildThemeOption(String themeName, ThemeProvider themeProvider, String currentTheme) {
    return RadioListTile<String>(
      title: Text(themeName, style: TextStyle(color: AppTheme.textPrimary)),
      value: themeName,
      groupValue: currentTheme,
      activeColor: AppTheme.primaryColor,
      onChanged: (val) {
        themeProvider.setTheme(val!);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$themeName theme selected.')),
        );
      },
    );
  }
}
