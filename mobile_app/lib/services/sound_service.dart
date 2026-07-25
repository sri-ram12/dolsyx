import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _notificationPlayer = AudioPlayer();
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  bool _isRingtonePlaying = false;

  Future<void> _setNotificationAudioContext() async {
    try {
      AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
    } catch (e) {}
  }

  Future<void> _setRingtoneAudioContext() async {
    try {
      AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
    } catch (e) {}
  }

  Future<void> playNotificationSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tonesEnabled = prefs.getBool('notif_conversation_tones') ?? true;
      if (!tonesEnabled) return;

      await _setNotificationAudioContext();
      await _notificationPlayer.stop();
      await _notificationPlayer.setVolume(1.0);
      await _notificationPlayer.play(AssetSource('notificationsounds/notification_sound.mp3'));
    } catch (e) {
      print('SoundService notification error: $e');
    }
  }

  Future<void> playPreviewTone(String toneName, bool isCallRingtone) async {
    try {
      if (isCallRingtone) {
        await _setRingtoneAudioContext();
        await _ringtonePlayer.stop();
        await _ringtonePlayer.setVolume(1.0);
        await _ringtonePlayer.setReleaseMode(ReleaseMode.stop);
        await _ringtonePlayer.play(AssetSource('ringtonesounds/universfield-ringtone-030-437513.mp3'));
      } else {
        await _setNotificationAudioContext();
        await _notificationPlayer.stop();
        await _notificationPlayer.setVolume(1.0);
        await _notificationPlayer.play(AssetSource('notificationsounds/notification_sound.mp3'));
      }
    } catch (e) {
      print('SoundService preview error: $e');
    }
  }

  Future<void> startRingtone() async {
    if (_isRingtonePlaying) return;
    try {
      _isRingtonePlaying = true;
      await _setRingtoneAudioContext();
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(1.0);
      await _ringtonePlayer.play(AssetSource('ringtonesounds/universfield-ringtone-030-437513.mp3'));
    } catch (e) {
      print('SoundService ringtone error: $e');
    }
  }

  Future<void> startRingbackTone() async {
    if (_isRingtonePlaying) return;
    try {
      _isRingtonePlaying = true;
      await _setRingtoneAudioContext();
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(0.8);
      await _ringtonePlayer.play(AssetSource('ringtonesounds/universfield-ringtone-067-496273.mp3')); // Using another as ringback tone
    } catch (e) {
      print('SoundService ringback error: $e');
    }
  }

  Future<void> stopRingtone() async {
    try {
      _isRingtonePlaying = false;
      await _ringtonePlayer.stop();
    } catch (e) {
      print('SoundService stop ringtone error: $e');
    }
  }
}
