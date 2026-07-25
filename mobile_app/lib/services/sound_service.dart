import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _notificationPlayer = AudioPlayer();
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  bool _isRingtonePlaying = false;

  /// Plays a message notification sound
  Future<void> playNotificationSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tonesEnabled = prefs.getBool('notif_conversation_tones') ?? true;
      if (!tonesEnabled) return;

      final customPath = prefs.getString('notif_custom_device_path');
      final toneName = prefs.getString('notif_message_tone') ?? 'Default (Chime)';

      await _notificationPlayer.stop();

      if (customPath != null && customPath.isNotEmpty && toneName.contains('Custom')) {
        await _notificationPlayer.play(DeviceFileSource(customPath));
      } else {
        // High quality notification sound
        await _notificationPlayer.play(
          UrlSource('https://actions.google.com/sounds/v1/notifications/positive_notification.ogg'),
        );
      }
    } catch (e) {
      print('SoundService notification error: $e');
    }
  }

  /// Starts playing caller ringtone in a continuous loop
  Future<void> startRingtone() async {
    if (_isRingtonePlaying) return;
    try {
      _isRingtonePlaying = true;
      final prefs = await SharedPreferences.getInstance();
      final customPath = prefs.getString('notif_custom_device_path');
      final ringtoneName = prefs.getString('notif_call_ringtone') ?? 'Default (DOLSYX Bell)';

      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);

      if (customPath != null && customPath.isNotEmpty && ringtoneName.contains('Custom')) {
        await _ringtonePlayer.play(DeviceFileSource(customPath));
      } else {
        // Ringing digital phone bell loop
        await _ringtonePlayer.play(
          UrlSource('https://actions.google.com/sounds/v1/emergency/beeping_emergency_synthesizer.ogg'),
        );
      }
    } catch (e) {
      print('SoundService ringtone error: $e');
    }
  }

  /// Stops caller ringtone loop
  Future<void> stopRingtone() async {
    try {
      _isRingtonePlaying = false;
      await _ringtonePlayer.stop();
    } catch (e) {
      print('SoundService stop ringtone error: $e');
    }
  }
}
