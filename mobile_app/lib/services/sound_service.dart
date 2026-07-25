import 'dart:typed_data';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _notificationPlayer = AudioPlayer();
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  bool _isRingtonePlaying = false;

  Uint8List? _cachedChimeWav;
  Uint8List? _cachedRingtoneWav;

  /// Generates a 0.25s 16kHz PCM WAV chime audio buffer in memory (100% offline)
  Uint8List _generateChimeWav() {
    if (_cachedChimeWav != null) return _cachedChimeWav!;

    const sampleRate = 16000;
    const numSamples = (sampleRate * 0.25); // 0.25 seconds
    final int samplesCount = numSamples.toInt();
    final buffer = ByteData(44 + samplesCount * 2);

    // RIFF header
    buffer.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    buffer.setUint32(4, 36 + samplesCount * 2, Endian.little);
    buffer.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    buffer.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size
    buffer.setUint16(20, 1, Endian.little); // AudioFormat (PCM)
    buffer.setUint16(22, 1, Endian.little); // NumChannels (Mono)
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    buffer.setUint16(32, 2, Endian.little); // BlockAlign
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample
    buffer.setUint32(36, 0x64617461, Endian.big); // "data"
    buffer.setUint32(40, samplesCount * 2, Endian.little);

    for (int i = 0; i < samplesCount; i++) {
      double t = i / sampleRate;
      // Frequency sweep from 880Hz to 1320Hz with soft exponential decay
      double freq = 880.0 + (i / samplesCount) * 440.0;
      double amplitude = (1.0 - i / samplesCount);
      double sample = math.sin(2 * math.pi * freq * t) * amplitude;
      int intSample = (sample * 28000).clamp(-32768, 32767).toInt();
      buffer.setInt16(44 + i * 2, intSample, Endian.little);
    }
    _cachedChimeWav = buffer.buffer.asUint8List();
    return _cachedChimeWav!;
  }

  /// Generates a 1.2s 16kHz PCM WAV dual-tone call ringtone buffer in memory (100% offline)
  Uint8List _generateRingtoneWav() {
    if (_cachedRingtoneWav != null) return _cachedRingtoneWav!;

    const sampleRate = 16000;
    const numSamples = (sampleRate * 1.2); // 1.2 seconds
    final int samplesCount = numSamples.toInt();
    final buffer = ByteData(44 + samplesCount * 2);

    // RIFF header
    buffer.setUint32(0, 0x52494646, Endian.big);
    buffer.setUint32(4, 36 + samplesCount * 2, Endian.little);
    buffer.setUint32(8, 0x57415645, Endian.big);
    buffer.setUint32(12, 0x666d7420, Endian.big);
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    buffer.setUint32(36, 0x64617461, Endian.big);
    buffer.setUint32(40, samplesCount * 2, Endian.little);

    for (int i = 0; i < samplesCount; i++) {
      double t = i / sampleRate;
      // Pulse pattern: 0.4s tone, 0.2s pause, 0.4s tone, 0.2s pause
      double cycle = (t % 0.6);
      double envelope = (cycle < 0.4) ? 1.0 : 0.0;
      // Dual-frequency bell sound (440Hz + 480Hz)
      double sample = (math.sin(2 * math.pi * 440.0 * t) + math.sin(2 * math.pi * 480.0 * t)) * 0.5 * envelope;
      int intSample = (sample * 26000).clamp(-32768, 32767).toInt();
      buffer.setInt16(44 + i * 2, intSample, Endian.little);
    }
    _cachedRingtoneWav = buffer.buffer.asUint8List();
    return _cachedRingtoneWav!;
  }

  /// Configure Android speakerphone audio context for notification sounds
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
    } catch (e) {
      print('AudioContext error: $e');
    }
  }

  /// Configure Android speakerphone audio context for call ringtones
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
    } catch (e) {
      print('AudioContext error: $e');
    }
  }

  /// Plays a message notification sound
  Future<void> playNotificationSound() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tonesEnabled = prefs.getBool('notif_conversation_tones') ?? true;
      if (!tonesEnabled) return;

      await _setNotificationAudioContext();

      final customPath = prefs.getString('notif_custom_device_path');
      final toneName = prefs.getString('notif_message_tone') ?? 'Default (Chime)';

      await _notificationPlayer.stop();
      await _notificationPlayer.setVolume(1.0);

      if (customPath != null && customPath.isNotEmpty && toneName.contains('Custom')) {
        await _notificationPlayer.play(DeviceFileSource(customPath));
      } else {
        // Play 100% offline in-memory PCM WAV chime
        await _notificationPlayer.play(BytesSource(_generateChimeWav()));
      }
    } catch (e) {
      print('SoundService notification error: $e');
    }
  }

  /// Plays a preview tone for settings
  Future<void> playPreviewTone(String toneName, bool isCallRingtone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customPath = prefs.getString('notif_custom_device_path');

      if (isCallRingtone) {
        await _setRingtoneAudioContext();
        await _ringtonePlayer.stop();
        await _ringtonePlayer.setVolume(1.0);
        await _ringtonePlayer.setReleaseMode(ReleaseMode.stop);

        if (customPath != null && customPath.isNotEmpty && toneName.contains('Custom')) {
          await _ringtonePlayer.play(DeviceFileSource(customPath));
        } else {
          await _ringtonePlayer.play(BytesSource(_generateRingtoneWav()));
        }
      } else {
        await _setNotificationAudioContext();
        await _notificationPlayer.stop();
        await _notificationPlayer.setVolume(1.0);

        if (customPath != null && customPath.isNotEmpty && toneName.contains('Custom')) {
          await _notificationPlayer.play(DeviceFileSource(customPath));
        } else {
          await _notificationPlayer.play(BytesSource(_generateChimeWav()));
        }
      }
    } catch (e) {
      print('SoundService preview error: $e');
    }
  }

  /// Starts playing caller ringtone in a continuous loop
  Future<void> startRingtone() async {
    if (_isRingtonePlaying) return;
    try {
      _isRingtonePlaying = true;
      await _setRingtoneAudioContext();

      final prefs = await SharedPreferences.getInstance();
      final customPath = prefs.getString('notif_custom_device_path');
      final ringtoneName = prefs.getString('notif_call_ringtone') ?? 'Default (DOLSYX Bell)';

      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(1.0);

      if (customPath != null && customPath.isNotEmpty && ringtoneName.contains('Custom')) {
        await _ringtonePlayer.play(DeviceFileSource(customPath));
      } else {
        // Play 100% offline in-memory PCM WAV ringtone loop
        await _ringtonePlayer.play(BytesSource(_generateRingtoneWav()));
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
