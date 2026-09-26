import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';

/// Represents the integrity and tamper status of the host environment
class DeviceSecurityReport {
  final bool isCompromised;
  final bool isRootedOrJailbroken;
  final bool isDebugMode;
  final List<String> detectedFlags;
  final String clientVersion;
  final String platform;

  const DeviceSecurityReport({
    required this.isCompromised,
    required this.isRootedOrJailbroken,
    required this.isDebugMode,
    required this.detectedFlags,
    required this.clientVersion,
    required this.platform,
  });

  @override
  String toString() =>
      'DeviceSecurityReport(compromised: $isCompromised, root/jailbreak: $isRootedOrJailbroken, debug: $isDebugMode, flags: $detectedFlags)';
}

/// Anti-Tamper & Security Engine (Phase 20)
/// Provides root/jailbreak detection, app integrity verification,
/// HMAC-SHA256 request signing, and client version attestation.
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  static const String clientVersion = '1.0.5';
  static const String _appSecret = 'dolsyx_tamper_seal_2025_sec_token';

  static String get platformName {
    try {
      if (kIsWeb) return 'Web';
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Unknown';
  }

  /// Known binaries and paths for rooted Android devices
  static const List<String> _androidRootPaths = [
    '/system/app/Superuser.apk',
    '/sbin/su',
    '/system/bin/su',
    '/system/xbin/su',
    '/data/local/xbin/su',
    '/data/local/bin/su',
    '/system/sd/xbin/su',
    '/system/bin/failsafe/su',
    '/data/local/su',
    '/su/bin/su',
    '/magisk/.core/bin/su',
  ];

  /// Known paths and indicators for jailbroken iOS devices
  static const List<String> _iosJailbreakPaths = [
    '/Applications/Cydia.app',
    '/Library/MobileSubstrate/MobileSubstrate.dylib',
    '/bin/bash',
    '/usr/sbin/sshd',
    '/etc/apt',
    '/private/var/lib/apt/',
    '/Applications/RockApp.app',
    '/Applications/Icy.app',
    '/Applications/WinterBoard.app',
    '/Applications/SBSettings.app',
  ];

  /// Inspects the device for indicators of root, jailbreak, or tampering
  Future<DeviceSecurityReport> checkDeviceIntegrity() async {
    final flags = <String>[];
    bool isRooted = false;

    if (!kIsWeb) {
      try {
        if (Platform.isAndroid) {
          for (final path in _androidRootPaths) {
            try {
              if (File(path).existsSync()) {
                flags.add('Root binary detected: $path');
                isRooted = true;
                break;
              }
            } catch (_) {}
          }
        } else if (Platform.isIOS) {
          for (final path in _iosJailbreakPaths) {
            try {
              if (File(path).existsSync() || Directory(path).existsSync()) {
                flags.add('Jailbreak artifact detected: $path');
                isRooted = true;
                break;
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        flags.add('Filesystem security check error: $e');
      }
    }

    if (kDebugMode) {
      flags.add('Running in debug mode');
    }

    final isCompromised = isRooted;

    return DeviceSecurityReport(
      isCompromised: isCompromised,
      isRootedOrJailbroken: isRooted,
      isDebugMode: kDebugMode,
      detectedFlags: flags,
      clientVersion: clientVersion,
      platform: platformName,
    );
  }

  /// Baseline security headers required for all authenticated API communications
  Map<String, String> getSecurityHeaders([String? token]) {
    final headers = <String, String>{
      'X-DOLSYX-Client-Version': clientVersion,
      'X-DOLSYX-Platform': platformName,
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Cryptographically signs a request payload with HMAC-SHA256 to guarantee integrity
  Future<Map<String, String>> signRequest({
    required String method,
    required String url,
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final headers = getSecurityHeaders(token);
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final bodyStr = body != null && body.isNotEmpty ? jsonEncode(body) : '';

    final canonicalPayload = '${method.toUpperCase()}:$url:$timestamp:$bodyStr';

    final hmac = Hmac.sha256();
    final mac = await hmac.calculateMac(
      utf8.encode(canonicalPayload),
      secretKey: SecretKey(utf8.encode(_appSecret)),
    );

    final signatureHex = mac.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    headers['X-DOLSYX-Signature'] = signatureHex;
    headers['X-DOLSYX-Timestamp'] = timestamp;

    return headers;
  }
}
