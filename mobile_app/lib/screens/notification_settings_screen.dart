import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import '../theme/app_theme.dart';
import '../services/sound_service.dart';

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
  String? _customDeviceTonePath;
  
  final AudioPlayer _audioPlayer = AudioPlayer();

  final List<String> _messageTones = [
    'Default (Chime)',
    'Pop',
    'Whistle',
    'Gentle Drop',
    'Custom Tone from Device Storage...',
  ];

  final List<String> _callRingtones = [
    'Default (DOLSYX Bell)',
    'Classic Telephone',
    'Digital Pulse',
    'Marimba Melody',
    'Custom Ringtone from Device Storage...',
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _conversationTones = prefs.getBool('notif_conversation_tones') ?? true;
      _vibrate = prefs.getBool('notif_vibrate') ?? true;
      _messageTone = prefs.getString('notif_message_tone') ?? 'Default (Chime)';
      _callRingtone = prefs.getString('notif_call_ringtone') ?? 'Default (DOLSYX Bell)';
      _highPriorityNotifications = prefs.getBool('notif_high_priority') ?? true;
      _customDeviceTonePath = prefs.getString('notif_custom_device_path');
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

  Future<void> _playSoundPreview(String toneName, bool isCallRingtone) async {
    try {
      await SoundService().playPreviewTone(toneName, isCallRingtone);
    } catch (e) {
      print('Error playing preview: $e');
    }
  }

  Future<void> _pickCustomAudioFile(bool isCallRingtone) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('notif_custom_device_path', filePath);

        final label = 'Custom ($fileName)';
        if (isCallRingtone) {
          setState(() {
            _callRingtone = label;
            _customDeviceTonePath = filePath;
          });
          await _saveString('notif_call_ringtone', label);
        } else {
          setState(() {
            _messageTone = label;
            _customDeviceTonePath = filePath;
          });
          await _saveString('notif_message_tone', label);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Set custom tone: $fileName')),
        );

        // Play preview of selected file
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(filePath));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load audio file: $e')),
      );
    }
  }

  void _showPicker(String title, String current, List<String> options, bool isCallRingtone, Function(String) onSelect) {
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
                  leading: Icon(
                    opt.contains('Custom') ? Icons.folder_open : Icons.music_note,
                    color: AppTheme.primaryColor,
                  ),
                  trailing: opt == current ? Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                  onTap: () async {
                    Navigator.pop(context);
                    if (opt.contains('Custom')) {
                      await _pickCustomAudioFile(isCallRingtone);
                    } else {
                      onSelect(opt);
                      await _playSoundPreview(opt, isCallRingtone);
                    }
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
            trailing: IconButton(
              icon: Icon(Icons.volume_up, color: AppTheme.primaryColor),
              onPressed: () => _playSoundPreview(_messageTone, false),
            ),
            onTap: () {
              _showPicker('Select Notification Tone', _messageTone, _messageTones, false, (val) {
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
            trailing: IconButton(
              icon: Icon(Icons.volume_up, color: AppTheme.primaryColor),
              onPressed: () => _playSoundPreview(_callRingtone, true),
            ),
            onTap: () {
              _showPicker('Select Call Ringtone', _callRingtone, _callRingtones, true, (val) {
                setState(() => _callRingtone = val);
                _saveString('notif_call_ringtone', val);
              });
            },
          ),
          ListTile(
            title: Text('Select Custom Tone from Device Storage', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_customDeviceTonePath != null ? 'Selected: ${_customDeviceTonePath!.split('/').last}' : 'Pick any MP3 or WAV audio file from phone', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            leading: Icon(Icons.folder_open, color: AppTheme.primaryColor),
            onTap: () => _pickCustomAudioFile(true),
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
