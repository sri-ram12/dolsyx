import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  static const MethodChannel _ringtoneChannel = MethodChannel('com.dolsyx/ringtones');

  final AudioPlayer _notificationPlayer = AudioPlayer();
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  bool _isRingtonePlaying = false;

  Future<List<Map<String, String>>> fetchSystemNotificationSounds() async {
    try {
      final List<dynamic>? res = await _ringtoneChannel.invokeMethod('getNotificationSounds');
      if (res != null) {
        return res.map((e) => Map<String, String>.from(e as Map)).toList();
      }
    } catch (e) {
      print('Error fetching system notification sounds: $e');
    }
    return [];
  }

  Future<List<Map<String, String>>> fetchSystemRingtones() async {
    try {
      final List<dynamic>? res = await _ringtoneChannel.invokeMethod('getRingtones');
      if (res != null) {
        return res.map((e) => Map<String, String>.from(e as Map)).toList();
      }
    } catch (e) {
      print('Error fetching system ringtones: $e');
    }
    return [];
  }

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
          usageType: AndroidUsageType.notificationRingtone,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
    } catch (e) {}
  }

  Source _getNotificationSource(String toneName, String? customPath) {
    if (toneName.startsWith('Custom') && customPath != null) {
      return DeviceFileSource(customPath);
    }
    switch (toneName) {
      case 'Pop':
        return AssetSource('notificationsounds/live_messenger.mp3');
      case 'Whistle':
        return AssetSource('notificationsounds/silbido.mp3');
      case 'Gentle Drop':
        return AssetSource('notificationsounds/sm_onedrop.mp3');
      case 'Default (Chime)':
      default:
        return AssetSource('notificationsounds/notification_sound.mp3');
    }
  }

  Source _getRingtoneSource(String toneName, String? customPath) {
    if (toneName.startsWith('Custom') && customPath != null) {
      return DeviceFileSource(customPath);
    }
    switch (toneName) {
      case 'Classic Telephone':
        return AssetSource('ringtonesounds/universfield-ringtone-032-480574.mp3');
      case 'Digital Pulse':
        return AssetSource('ringtonesounds/universfield-ringtone-067-496273.mp3');
      case 'Marimba Melody':
        return AssetSource('ringtonesounds/universfield-ringtone-030-437513.mp3');
      case 'Default (DOLSYX Bell)':
      default:
        return AssetSource('notificationsounds/tyy.mp3'); // Using tir tir as default call tune
    }
  }

  Future<void> playNotificationSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tonesEnabled = prefs.getBool('notif_conversation_tones') ?? true;
      if (!tonesEnabled) return;

      final toneName = prefs.getString('notif_message_tone') ?? 'Pop';
      final toneUri = prefs.getString('notif_message_tone_uri');
      final customPath = prefs.getString('notif_custom_device_path');

      if (toneUri != null && toneUri.startsWith('content://')) {
        await _ringtoneChannel.invokeMethod('playTone', {'uri': toneUri});
        return;
      }

      await _setNotificationAudioContext();
      await _notificationPlayer.stop();
      await _notificationPlayer.setVolume(1.0);
      await _notificationPlayer.play(_getNotificationSource(toneName, customPath));
    } catch (e) {
      print('SoundService notification error: $e');
    }
  }

  Future<void> playPreviewTone(String toneName, bool isCallRingtone, {String? toneUri}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customPath = prefs.getString('notif_custom_device_path');

      if (toneUri != null && toneUri.startsWith('content://')) {
        await _notificationPlayer.stop();
        await _ringtonePlayer.stop();
        await _ringtoneChannel.invokeMethod('playTone', {'uri': toneUri});
        return;
      }

      // Stop native tone if running
      try {
        await _ringtoneChannel.invokeMethod('stopTone');
      } catch (_) {}

      if (isCallRingtone) {
        await _setRingtoneAudioContext();
        await _ringtonePlayer.stop();
        await _ringtonePlayer.setVolume(1.0);
        await _ringtonePlayer.setReleaseMode(ReleaseMode.stop);
        await _ringtonePlayer.play(_getRingtoneSource(toneName, customPath));
      } else {
        await _setNotificationAudioContext();
        await _notificationPlayer.stop();
        await _notificationPlayer.setVolume(1.0);
        await _notificationPlayer.play(_getNotificationSource(toneName, customPath));
      }
    } catch (e) {
      print('SoundService preview error: $e');
    }
  }

  Future<void> startRingtone() async {
    if (_isRingtonePlaying) return;
    try {
      _isRingtonePlaying = true;
      final prefs = await SharedPreferences.getInstance();
      final toneName = prefs.getString('notif_call_ringtone') ?? 'Marimba Melody';
      final toneUri = prefs.getString('notif_call_ringtone_uri');
      final customPath = prefs.getString('notif_custom_device_path');

      if (toneUri != null && toneUri.startsWith('content://')) {
        await _ringtoneChannel.invokeMethod('playTone', {'uri': toneUri});
        return;
      }

      await _setRingtoneAudioContext();
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(1.0);
      await _ringtonePlayer.play(_getRingtoneSource(toneName, customPath));
    } catch (e) {
      print('SoundService ringtone error: $e');
    }
  }

  Future<void> _setEarSpeakerAudioContext() async {
    try {
      AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false, // Route to Ear Speaker / Earpiece!
          stayAwake: true,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.voiceCommunication,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ));
    } catch (e) {}
  }

  Future<void> startRingbackTone() async {
    try {
      _isRingtonePlaying = true;
      await _ringtonePlayer.stop();
      await _setEarSpeakerAudioContext();
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(1.0);
      // Play classic tir tir ringback tone in earpiece / ear speaker
      await _ringtonePlayer.play(AssetSource('notificationsounds/tyy.mp3'));
    } catch (e) {
      print('SoundService ringback error: $e');
    }
  }

  Future<void> playBusyTone() async {
    try {
      await _setEarSpeakerAudioContext();
      await _notificationPlayer.stop();
      await _notificationPlayer.setVolume(1.0);
      await _notificationPlayer.play(AssetSource('notificationsounds/tyy.mp3'));
    } catch (e) {}
  }

  Future<void> stopRingtone() async {
    try {
      _isRingtonePlaying = false;
      await _ringtonePlayer.stop();
      // Restore standard speech audio context so WebRTC voice audio is audible
      try {
        await AudioPlayer.global.setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.voiceCommunication,
            audioFocus: AndroidAudioFocus.none,
          ),
        ));
      } catch (_) {}
    } catch (e) {
      print('SoundService stop ringtone error: $e');
    }
  }
}
