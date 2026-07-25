import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _conversationTones = true;
  bool _vibrate = true;
  String _messageTone = 'Default (Chime)';
  String _callRingtone = 'Default (DOLSYX Bell)';
  bool _highPriorityNotifications = true;

  final List<String> _messageTones = [
    'Default (Chime)',
    'Pop',
    'Whistle',
    'Gentle Drop',
    'Device System Tone (Default)',
  ];

  final List<String> _callRingtones = [
    'Default (DOLSYX Bell)',
    'Classic Telephone',
    'Digital Pulse',
    'Marimba Melody',
    'Device Custom Ringtone',
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _conversationTones = prefs.getBool('notif_conversation_tones') ?? true;
      _vibrate = prefs.getBool('notif_vibrate') ?? true;
      _messageTone = prefs.getString('notif_message_tone') ?? 'Default (Chime)';
      _callRingtone = prefs.getString('notif_call_ringtone') ?? 'Default (DOLSYX Bell)';
      _highPriorityNotifications = prefs.getBool('notif_high_priority') ?? true;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  void _showPicker(String title, String current, List<String> options, Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            ),
            const Divider(height: 1),
            ...options.map((opt) => ListTile(
                  title: Text(opt, style: TextStyle(color: AppTheme.textPrimary)),
                  trailing: opt == current ? Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                  onTap: () {
                    onSelect(opt);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification & Ringtone Tones'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        children: [
          _buildSectionHeader('Messages'),
          SwitchListTile(
            title: Text('Conversation Tones', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Play sounds for incoming and outgoing messages', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            value: _conversationTones,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {
              setState(() => _conversationTones = val);
              _saveBool('notif_conversation_tones', val);
            },
          ),
          ListTile(
            title: Text('Notification Tone', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_messageTone, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            leading: Icon(Icons.music_note, color: AppTheme.primaryColor),
            onTap: () {
              _showPicker('Select Notification Tone', _messageTone, _messageTones, (val) {
                setState(() => _messageTone = val);
                _saveString('notif_message_tone', val);
              });
            },
          ),
          SwitchListTile(
            title: Text('Vibrate', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Vibrate phone on new message', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            value: _vibrate,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {
              setState(() => _vibrate = val);
              _saveBool('notif_vibrate', val);
            },
          ),
          const Divider(height: 1),
          _buildSectionHeader('Calls & Ringtones'),
          ListTile(
            title: Text('Caller Ringtone', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_callRingtone, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            leading: Icon(Icons.ring_volume, color: AppTheme.primaryColor),
            onTap: () {
              _showPicker('Select Call Ringtone', _callRingtone, _callRingtones, (val) {
                setState(() => _callRingtone = val);
                _saveString('notif_call_ringtone', val);
              });
            },
          ),
          ListTile(
            title: Text('Custom Tone Access', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Allow DOLSYX to access custom tones on device storage', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            leading: Icon(Icons.sd_storage, color: AppTheme.primaryColor),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Device tone access granted')),
              );
            },
          ),
          const Divider(height: 1),
          _buildSectionHeader('Priority'),
          SwitchListTile(
            title: Text('High Priority Notifications', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Show pop-ups at the top of the screen', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            value: _highPriorityNotifications,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {
              setState(() => _highPriorityNotifications = val);
              _saveBool('notif_high_priority', val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
      child: Text(
        title,
        style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }
}
