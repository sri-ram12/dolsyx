import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'blocked_users_screen.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _readReceipts = true;
  String _lastSeenPrivacy = 'EVERYONE';
  String _onlinePrivacy = 'EVERYONE';
  String _avatarPrivacy = 'EVERYONE';
  String _aboutPrivacy = 'EVERYONE';
  String _statusPrivacy = 'MY_CONTACTS';
  String _disappearingTimer = 'OFF';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  void _loadPrivacySettings() {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      setState(() {
        _lastSeenPrivacy = user['lastSeenPrivacy'] ?? 'EVERYONE';
        _onlinePrivacy = user['onlinePrivacy'] ?? 'EVERYONE';
        _avatarPrivacy = user['avatarPrivacy'] ?? 'EVERYONE';
        _aboutPrivacy = user['aboutPrivacy'] ?? 'EVERYONE';
        _statusPrivacy = user['statusPrivacyType'] ?? 'MY_CONTACTS';
        _readReceipts = user['readReceipts'] ?? true;
        _disappearingTimer = user['disappearingTimer'] ?? 'OFF';
      });
    }
  }

  Future<void> _updatePrivacy(Map<String, dynamic> fields) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    if (token == null) return;

    setState(() => _isSaving = true);
    try {
      final response = await http.put(
        Uri.parse('https://dolsyx-app.onrender.com/api/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(fields),
      );

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        authProvider.updateUser(data['user']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Privacy settings updated'), backgroundColor: AppTheme.primaryColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showPicker(String title, List<Map<String, String>> options, String currentValue, Function(String) onSelected) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(title, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ...options.map((opt) {
            final isSelected = opt['value'] == currentValue;
            return ListTile(
              title: Text(opt['label']!, style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: opt['desc'] != null ? Text(opt['desc']!, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)) : null,
              trailing: isSelected ? Icon(Icons.check_circle, color: AppTheme.primaryColor) : Icon(Icons.circle_outlined, color: AppTheme.textSecondary),
              onTap: () {
                Navigator.pop(ctx);
                onSelected(opt['value']!);
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _friendlyLabel(String val) {
    switch (val) {
      case 'EVERYONE': return 'Everyone';
      case 'MY_CONTACTS': return 'My Contacts';
      case 'EXCEPT': return 'My Contacts Except...';
      case 'NOBODY': return 'Nobody';
      case 'SAME_AS_LAST_SEEN': return 'Same as Last Seen';
      case 'ONLY_SHARE': return 'Only Share With...';
      case 'OFF': return 'Off';
      case '24H': return '24 Hours';
      case '7D': return '7 Days';
      case '90D': return '90 Days';
      default: return val;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy'),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          if (_isSaving) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
        ],
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        children: [
          // == WHO CAN SEE MY INFO ==
          _sectionHeader('Who can see my personal info'),

          // Last Seen & Online
          ListTile(
            title: Text('Last seen & online', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_friendlyLabel(_lastSeenPrivacy), style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () => _showPicker('Last seen', [
              {'value': 'EVERYONE', 'label': 'Everyone', 'desc': 'Any DOLSYX user can see when you were last online'},
              {'value': 'MY_CONTACTS', 'label': 'My Contacts', 'desc': 'Only people in your contacts'},
              {'value': 'NOBODY', 'label': 'Nobody', 'desc': 'No one will see your last seen'},
            ], _lastSeenPrivacy, (val) {
              setState(() => _lastSeenPrivacy = val);
              _updatePrivacy({'lastSeenPrivacy': val});
            }),
          ),

          // Online Status
          ListTile(
            title: Text('Online', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_friendlyLabel(_onlinePrivacy), style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () => _showPicker('Online visibility', [
              {'value': 'EVERYONE', 'label': 'Everyone'},
              {'value': 'SAME_AS_LAST_SEEN', 'label': 'Same as Last Seen'},
              {'value': 'NOBODY', 'label': 'Nobody'},
            ], _onlinePrivacy, (val) {
              setState(() => _onlinePrivacy = val);
              _updatePrivacy({'onlinePrivacy': val});
            }),
          ),

          // Profile Photo
          ListTile(
            title: Text('Profile photo', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_friendlyLabel(_avatarPrivacy), style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () => _showPicker('Profile photo', [
              {'value': 'EVERYONE', 'label': 'Everyone'},
              {'value': 'MY_CONTACTS', 'label': 'My Contacts'},
              {'value': 'NOBODY', 'label': 'Nobody'},
            ], _avatarPrivacy, (val) {
              setState(() => _avatarPrivacy = val);
              _updatePrivacy({'avatarPrivacy': val});
            }),
          ),

          // About
          ListTile(
            title: Text('About', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_friendlyLabel(_aboutPrivacy), style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () => _showPicker('About', [
              {'value': 'EVERYONE', 'label': 'Everyone'},
              {'value': 'MY_CONTACTS', 'label': 'My Contacts'},
              {'value': 'NOBODY', 'label': 'Nobody'},
            ], _aboutPrivacy, (val) {
              setState(() => _aboutPrivacy = val);
              _updatePrivacy({'aboutPrivacy': val});
            }),
          ),

          // Status
          ListTile(
            title: Text('Status', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_friendlyLabel(_statusPrivacy), style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () => _showPicker('Status visibility', [
              {'value': 'MY_CONTACTS', 'label': 'My Contacts'},
              {'value': 'EXCEPT', 'label': 'My Contacts Except...', 'desc': 'Share with everyone except selected contacts'},
              {'value': 'ONLY_SHARE', 'label': 'Only Share With...', 'desc': 'Only share with selected contacts'},
            ], _statusPrivacy, (val) {
              setState(() => _statusPrivacy = val);
              _updatePrivacy({'statusPrivacyType': val});
            }),
          ),

          const Divider(color: Colors.grey),
          _sectionHeader('Messages'),

          // Read Receipts
          SwitchListTile(
            title: Text('Read receipts', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(
              'If turned off, you won\'t send or receive read receipts. Blue ticks will be hidden.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            value: _readReceipts,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {
              setState(() => _readReceipts = val);
              _updatePrivacy({'readReceipts': val});
            },
          ),

          const Divider(color: Colors.grey),
          _sectionHeader('Disappearing messages'),

          ListTile(
            title: Text('Default message timer', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_friendlyLabel(_disappearingTimer), style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () => _showPicker('Default message timer', [
              {'value': 'OFF', 'label': 'Off'},
              {'value': '24H', 'label': '24 Hours'},
              {'value': '7D', 'label': '7 Days'},
              {'value': '90D', 'label': '90 Days'},
            ], _disappearingTimer, (val) {
              setState(() => _disappearingTimer = val);
              _updatePrivacy({'disappearingTimer': val});
            }),
          ),

          const Divider(color: Colors.grey),
          _sectionHeader('Contacts'),

          ListTile(
            leading: Icon(Icons.block, color: Colors.red),
            title: Text('Blocked contacts', style: TextStyle(color: AppTheme.textPrimary)),
            trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedUsersScreen())),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}
