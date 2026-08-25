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
  String _vibrationPattern = 'Default';
  bool _quietHoursEnabled = false;
  String _messageTone = 'Pop';
  String _callRingtone = 'Marimba Melody';
  bool _highPriorityNotifications = true;
  String? _customDeviceTonePath;

  final AudioPlayer _audioPlayer = AudioPlayer();

  final List<String> _appMessageTones = [
    'Default (Chime)',
    'Pop',
    'Whistle',
    'Gentle Drop',
  ];

  final List<String> _appCallRingtones = [
    'Default (DOLSYX Bell)',
    'Classic Telephone',
    'Digital Pulse',
    'Marimba Melody',
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    SoundService().playPreviewTone('', false);
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _conversationTones = prefs.getBool('notif_conversation_tones') ?? true;
      _vibrate = prefs.getBool('notif_vibrate') ?? true;
      _vibrationPattern = prefs.getString('notif_vibration_pattern') ?? 'Default';
      _messageTone = prefs.getString('notif_message_tone') ?? 'Pop';
      _callRingtone = prefs.getString('notif_call_ringtone') ?? 'Marimba Melody';
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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Set custom tone: $fileName')),
          );
        }

        // Play preview of selected file
        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(filePath));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load audio file: $e')),
        );
      }
    }
  }

  void _showTonePickerModal({
    required String title,
    required String currentTitle,
    required List<String> appTones,
    required bool isCallRingtone,
    required Function(String title) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Custom Storage Option
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.primaryColor.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(Icons.folder_open, color: AppTheme.primaryColor, size: 20),
                ),
                title: Text('Custom Tone from Device Storage...', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                subtitle: Text('Pick any MP3 / WAV audio file from phone', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickCustomAudioFile(isCallRingtone);
                },
              ),
              const Divider(height: 1),

              // App Tones List
              ...appTones.map((toneName) {
                final isSelected = currentTitle == toneName;
                return ListTile(
                  title: Text(toneName, style: TextStyle(color: AppTheme.textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  leading: Icon(Icons.music_note, color: isSelected ? AppTheme.primaryColor : Colors.grey),
                  trailing: isSelected ? Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                  onTap: () async {
                    onSelect(toneName);
                    await _playSoundPreview(toneName, isCallRingtone);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showPatternPicker(String title, String current, List<String> options, Function(String) onSelect) {
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
                  leading: Icon(Icons.vibration, color: AppTheme.primaryColor),
                  trailing: opt == current ? Icon(Icons.check_circle, color: AppTheme.primaryColor) : null,
                  onTap: () {
                    Navigator.pop(context);
                    onSelect(opt);
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
        title: const Text('Notifications & Sounds'),
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
              _showTonePickerModal(
                title: 'Select Notification Tone',
                currentTitle: _messageTone,
                appTones: _appMessageTones,
                isCallRingtone: false,
                onSelect: (title) async {
                  setState(() => _messageTone = title);
                  await _saveString('notif_message_tone', title);
                },
              );
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
          ListTile(
            title: Text('Vibration Pattern', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_vibrationPattern, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            leading: Icon(Icons.vibration, color: AppTheme.primaryColor),
            onTap: () {
              _showPatternPicker('Select Vibration Pattern', _vibrationPattern, ['Default', 'Short Pulse', 'Long Vibration', 'Heartbeat', 'Rapid'], (val) {
                setState(() => _vibrationPattern = val);
                _saveString('notif_vibration_pattern', val);
              });
            },
          ),
          const Divider(height: 1),
          _buildSectionHeader('Quiet Hours & Do Not Disturb'),
          SwitchListTile(
            title: Text('Quiet Hours (Do Not Disturb)', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_quietHoursEnabled ? 'Notifications silenced between 10:00 PM – 7:00 AM' : 'Automatically silence alerts during night', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            value: _quietHoursEnabled,
            activeColor: AppTheme.primaryColor,
            onChanged: (val) {
              setState(() => _quietHoursEnabled = val);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(val ? 'Quiet Hours Enabled (10:00 PM – 7:00 AM)' : 'Quiet Hours Disabled')),
              );
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
              _showTonePickerModal(
                title: 'Select Call Ringtone',
                currentTitle: _callRingtone,
                appTones: _appCallRingtones,
                isCallRingtone: true,
                onSelect: (title) async {
                  setState(() => _callRingtone = title);
                  await _saveString('notif_call_ringtone', title);
                },
              );
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
