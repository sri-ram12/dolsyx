import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _readReceipts = true;
  String _lastSeenPrivacy = 'PUBLIC';
  String _disappearingTimer = 'OFF';

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // Use current user data
    if (authProvider.user != null) {
      setState(() {
        _lastSeenPrivacy = authProvider.user!['lastSeenPrivacy'] ?? 'PUBLIC';
        _readReceipts = authProvider.user!['readReceipts'] ?? true;
        _disappearingTimer = authProvider.user!['disappearingTimer'] ?? 'OFF';
      });
    }
  }

  Future<void> _updatePrivacy(String key, dynamic value) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    if (token == null) return;

    try {
      final response = await http.put(
        Uri.parse('https://dolsyx-app.onrender.com/api/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          key: value,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        authProvider.updateUser(data['user']);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Privacy settings updated')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update privacy settings')));
      }
    } catch (e) {
      print('Privacy update error: $e');
    }
  }

  void _showPrivacyPicker(String title, List<String> options, String currentValue, Function(String) onSelected) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          title: Text(title, style: TextStyle(color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              return RadioListTile<String>(
                title: Text(opt, style: TextStyle(color: AppTheme.textPrimary)),
                value: opt,
                groupValue: currentValue,
                activeColor: AppTheme.primaryColor,
                onChanged: (val) {
                  Navigator.pop(context);
                  onSelected(val!);
                },
              );
            }).toList(),
          ),
        );
      }
    );
  }

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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Who can see my personal info', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          _buildPrivacyOption('Last seen and online', _lastSeenPrivacy, () {
            _showPrivacyPicker('Last seen and online', ['PUBLIC', 'CONTACTS', 'NOBODY'], _lastSeenPrivacy, (val) {
              setState(() => _lastSeenPrivacy = val);
              _updatePrivacy('lastSeenPrivacy', val);
            });
          }),
          _buildPrivacyOption('Profile photo', 'Everyone', () {}),
          _buildPrivacyOption('About', 'Everyone', () {}),
          _buildPrivacyOption('Status', 'My contacts', () {}),
          SwitchListTile(
            title: Text('Read receipts', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('If turned off, you won\'t send or receive Read receipts. Read receipts are always sent for group chats.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: _readReceipts,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {
              setState(() => _readReceipts = val);
              _updatePrivacy('readReceipts', val);
            },
          ),
          const Divider(color: Colors.grey),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Disappearing messages', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          _buildPrivacyOption('Default message timer', _disappearingTimer, () {
            _showPrivacyPicker('Message timer', ['OFF', '24H', '7D', '90D'], _disappearingTimer, (val) {
              setState(() => _disappearingTimer = val);
              _updatePrivacy('disappearingTimer', val);
            });
          }),
          const Divider(color: Colors.grey),
          _buildPrivacyOption('Blocked contacts', 'None', () {}),
        ],
      ),
    );
  }

  Widget _buildPrivacyOption(String title, String value, VoidCallback onTap) {
    return ListTile(
      title: Text(title, style: TextStyle(color: AppTheme.textPrimary)),
      subtitle: Text(value, style: TextStyle(color: AppTheme.textSecondary)),
      onTap: onTap,
    );
  }
}

