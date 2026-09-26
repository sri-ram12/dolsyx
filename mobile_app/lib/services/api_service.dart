import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

class ApiService {
  // DOLSYX Production Render Backend (works on all devices, Wi-Fi, and 4G/5G)
  static const String baseUrl = 'https://dolsyx-app.onrender.com/api';
  static const String localUrl = 'http://192.168.0.171:4000/api';

  static String getMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('blob:')) {
      return path;
    }
    // Return directly if it is a local file system path or file URI
    if (path.startsWith('file://') ||
        path.startsWith('/data/') ||
        path.startsWith('/storage/')) {
      return path;
    }
    if (!path.startsWith('/') && !path.startsWith('uploads/')) {
      try {
        if (File(path).existsSync()) return path;
      } catch (_) {}
    }
    final serverBase = baseUrl.endsWith('/api')
        ? baseUrl.substring(0, baseUrl.length - 4)
        : baseUrl;
    return '$serverBase${path.startsWith('/') ? '' : '/'}$path';
  }

  static Map<String, String> authHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  // Persistent singleton HTTP client with HTTP Keep-Alive connection reuse
  static final http.Client _client = http.Client();
  static http.Client get client => _client;

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _client.get(url, headers: headers);

  static Future<http.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _client.post(url, headers: headers, body: body, encoding: encoding);

  static Future<http.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _client.put(url, headers: headers, body: body, encoding: encoding);

  static Future<http.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _client.delete(url, headers: headers, body: body, encoding: encoding);

  static Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _client.send(request);

  Future<String?> _getFcmToken() async {
    try {
      if (Firebase.apps.isNotEmpty) {
        return await FirebaseMessaging.instance.getToken();
      }
    } catch (e) {
      print("FCM Token error: $e");
    }
    return null;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final fcmToken = await _getFcmToken();
      final response = await _client.post(
        Uri.parse('$baseUrl/auth/login-without-otp'), // Changed to support passwordless OTP accounts
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'fcmToken': fcmToken}), // Only send email + token
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Save the token securely
        final prefs = await SharedPreferences.getInstance();
        if (data['token'] != null) {
          await prefs.setString('jwt_token', data['token']);
        }
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: Could not connect to server.'};
    }
  }

  Future<Map<String, dynamic>> googleLogin({
    required String email,
    String? displayName,
    String? googleId,
    String? avatarUrl,
    String? idToken,
  }) async {
    try {
      final fcmToken = await _getFcmToken();
      final response = await _client.post(
        Uri.parse('$baseUrl/auth/google/verify-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'displayName': displayName,
          'googleId': googleId,
          'avatarUrl': avatarUrl,
          'idToken': idToken,
          'fcmToken': fcmToken,
          'deviceName': 'Android Phone',
          'deviceType': 'android',
        }),
      );

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        return {
          'success': false,
          'message': 'Server returned unexpected response (Code ${response.statusCode}).'
        };
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        if (data['token'] != null) {
          await prefs.setString('jwt_token', data['token']);
        }
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Google login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: Could not connect to server.'};
    }
  }


  Future<Map<String, dynamic>> register(String email, String username, String password) async {
    try {
      final fcmToken = await _getFcmToken();
      final response = await _client.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
          'fcmToken': fcmToken,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        if (data['token'] != null) {
          await prefs.setString('jwt_token', data['token']);
        }
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Registration failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: Could not connect to server.'};
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<Map<String, dynamic>?> uploadMedia(String filePath) async {
    try {
      final token = await getToken();
      if (token == null) {
        print('Upload error: JWT token is missing or expired');
        return null;
      }

      final localFile = File(filePath);
      if (!await localFile.exists()) {
        print('Upload error: local file does not exist at $filePath');
        return null;
      }

      // 1. Primary: POST to /chats/upload with timeout
      try {
        final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/chats/upload'));
        request.headers['Authorization'] = 'Bearer $token';
        request.files.add(await http.MultipartFile.fromPath('file', filePath));

        final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 45));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } else {
          print('Chats upload returned HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        print('Chats upload error ($e), attempting fallback to /uploads endpoint...');
      }

      // 2. Resilient secondary: POST to /uploads
      try {
        final fallbackRequest = http.MultipartRequest('POST', Uri.parse('$baseUrl/uploads'));
        fallbackRequest.headers['Authorization'] = 'Bearer $token';
        fallbackRequest.files.add(await http.MultipartFile.fromPath('file', filePath));

        final streamedFallback = await _client.send(fallbackRequest).timeout(const Duration(seconds: 45));
        final fallbackResponse = await http.Response.fromStream(streamedFallback);

        if (fallbackResponse.statusCode == 200 || fallbackResponse.statusCode == 201) {
          final decoded = jsonDecode(fallbackResponse.body);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        } else {
          print('Uploads fallback returned HTTP ${fallbackResponse.statusCode}: ${fallbackResponse.body}');
        }
      } catch (e) {
        print('Uploads fallback error: $e');
      }
    } catch (e) {
      print('Upload error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getProfile([String? customToken]) async {
    try {
      final token = customToken ?? await getToken();
      if (token == null) return null;

      final response = await _client.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return (decoded['user'] is Map<String, dynamic>) ? decoded['user'] : decoded;
        }
      }
    } catch (e) {
      print('Get profile error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> updateProfile({String? bio, String? username, String? avatarUrl}) async {
    try {
      final token = await getToken();
      if (token == null) return null;

      final body = <String, dynamic>{};
      if (bio != null) body['bio'] = bio;
      if (username != null) body['username'] = username;
      if (avatarUrl != null) body['avatarUrl'] = avatarUrl;

      final response = await _client.put(
        Uri.parse('$baseUrl/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body)['user'];
      }
      return null;
    } catch (e) {
      print('Update profile error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      final token = await getToken();
      if (token == null) return null;

      final response = await _client.get(
        Uri.parse('$baseUrl/auth/users/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await logout();
      }
      return null;
    } catch (e) {
      print('Get user by id error: $e');
      return null;
    }
  }

  Future<List<dynamic>> getBlockedUsers() async {
    try {
      final token = await getToken();
      if (token == null) return [];

      final response = await _client.get(
        Uri.parse('$baseUrl/auth/blocks'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Get blocked users error: $e');
    }
    return [];
  }

  Future<bool> blockUser(String targetUserId) async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final response = await _client.post(
        Uri.parse('$baseUrl/auth/block/$targetUserId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Block error: $e');
      return false;
    }
  }

  Future<List<dynamic>> getPastParticipants(String conversationId) async {
    try {
      final token = await getToken();
      if (token == null) return [];

      final response = await _client.get(
        Uri.parse('$baseUrl/groups/$conversationId/past-participants'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (e) {
      print('Get past participants error: $e');
    }
    return [];
  }

  Future<bool> unblockUser(String targetUserId) async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final response = await _client.delete(
        Uri.parse('$baseUrl/auth/block/$targetUserId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Unblock error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DOLSYX Secure Linked Device QR Login & Multi-Device Management
  // ─────────────────────────────────────────────────────────────────────────

  List<String> _resolveCandidateUrls(String? customBackendUrl) {
    final candidateUrls = <String>[];
    void addCandidate(String? url) {
      if (url == null || url.trim().isEmpty) return;
      var clean = url.trim();
      while (clean.endsWith('/')) {
        clean = clean.substring(0, clean.length - 1);
      }
      final withApi = clean.endsWith('/api') ? clean : '$clean/api';
      if (!candidateUrls.contains(withApi)) {
        candidateUrls.add(withApi);
      }
    }

    // 1. If customBackendUrl is passed in the QR code (and not pointing to loopback on mobile)
    if (customBackendUrl != null && customBackendUrl.trim().isNotEmpty) {
      if (!customBackendUrl.contains('localhost') && !customBackendUrl.contains('127.0.0.1')) {
        addCandidate(customBackendUrl);
      } else {
        // Laptop localhost replaced with active dev machine IP & Android emulator host
        addCandidate(customBackendUrl.replaceAll('localhost', '192.168.0.171').replaceAll('127.0.0.1', '192.168.0.171'));
        addCandidate(customBackendUrl.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2'));
      }
    }

    // 2. Production Render cloud backend (reliable globally across Wi-Fi & cellular data)
    addCandidate(baseUrl);

    // 3. Current active local dev machine IP fallbacks (short timeout)
    addCandidate(localUrl);
    addCandidate('http://192.168.0.171:4000/api');
    addCandidate('http://10.0.2.2:4000/api');

    return candidateUrls;
  }

  /// 1. Scan QR pairing session (verifies challenge & gets requesting device metadata)
  Future<Map<String, dynamic>?> scanDevicePairing(
    String token,
    String pairingId,
    String challenge, {
    String? customBackendUrl,
  }) async {
    final candidateUrls = _resolveCandidateUrls(customBackendUrl);
    final bodyData = jsonEncode({'pairingId': pairingId, 'challenge': challenge});

    for (final targetUrl in candidateUrls) {
      try {
        final isLocal = targetUrl.contains('192.168.') || targetUrl.contains('10.0.2.2') || targetUrl.contains('localhost');
        final timeoutSec = isLocal ? 2 : 7;
        final endpoint = targetUrl.endsWith('/api') ? '$targetUrl/devices/pair/scan' : '$targetUrl/api/devices/pair/scan';
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: authHeaders(token),
              body: bodyData,
            )
            .timeout(Duration(seconds: timeoutSec));

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 || response.statusCode == 201) {
          if (data['success'] == true) {
            return data;
          }
        } else if (response.statusCode == 400 && data['message'] != null) {
          return {'success': false, 'message': data['message']};
        }
      } catch (_) {
        // Try next candidate
      }
    }
    return null;
  }

  /// 2. Explicitly approve QR pairing after user confirmation
  Future<bool> approveDevicePairing(
    String token,
    String pairingId,
    String challenge, {
    String? customBackendUrl,
  }) async {
    final candidateUrls = _resolveCandidateUrls(customBackendUrl);
    final bodyData = jsonEncode({'pairingId': pairingId, 'challenge': challenge});

    for (final targetUrl in candidateUrls) {
      try {
        final isLocal = targetUrl.contains('192.168.') || targetUrl.contains('10.0.2.2') || targetUrl.contains('localhost');
        final timeoutSec = isLocal ? 3 : 8;
        final endpoint = targetUrl.endsWith('/api') ? '$targetUrl/devices/pair/approve' : '$targetUrl/api/devices/pair/approve';
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: authHeaders(token),
              body: bodyData,
            )
            .timeout(Duration(seconds: timeoutSec));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            return true;
          }
        }
      } catch (_) {
        // Try next candidate
      }
    }
    return false;
  }

  /// 3. Reject / cancel QR pairing
  Future<bool> rejectDevicePairing(
    String token,
    String pairingId, {
    String? customBackendUrl,
  }) async {
    final candidateUrls = _resolveCandidateUrls(customBackendUrl);
    final bodyData = jsonEncode({'pairingId': pairingId});

    for (final targetUrl in candidateUrls) {
      try {
        final isLocal = targetUrl.contains('192.168.') || targetUrl.contains('10.0.2.2') || targetUrl.contains('localhost');
        final timeoutSec = isLocal ? 2 : 5;
        final endpoint = targetUrl.endsWith('/api') ? '$targetUrl/devices/pair/reject' : '$targetUrl/api/devices/pair/reject';
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: authHeaders(token),
              body: bodyData,
            )
            .timeout(Duration(seconds: timeoutSec));

        if (response.statusCode == 200) {
          return true;
        }
      } catch (_) {
        // Try next candidate
      }
    }
    return false;
  }

  /// 4. Fetch all linked devices for authenticated user
  Future<List<Map<String, dynamic>>> getLinkedDevices(String token) async {
    final candidateUrls = _resolveCandidateUrls(null);
    for (final targetUrl in candidateUrls) {
      try {
        final isLocal = targetUrl.contains('192.168.') || targetUrl.contains('10.0.2.2') || targetUrl.contains('localhost');
        final timeoutSec = isLocal ? 2 : 6;
        final endpoint = targetUrl.endsWith('/api') ? '$targetUrl/devices' : '$targetUrl/api/devices';
        final response = await _client
            .get(
              Uri.parse(endpoint),
              headers: authHeaders(token),
            )
            .timeout(Duration(seconds: timeoutSec));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['devices'] != null) {
            return List<Map<String, dynamic>>.from(data['devices']);
          }
        }
      } catch (_) {}
    }
    return [];
  }

  /// 5. Revoke a specific linked device session
  Future<bool> revokeLinkedDevice(String token, String sessionId) async {
    final candidateUrls = _resolveCandidateUrls(null);
    for (final targetUrl in candidateUrls) {
      try {
        final isLocal = targetUrl.contains('192.168.') || targetUrl.contains('10.0.2.2') || targetUrl.contains('localhost');
        final timeoutSec = isLocal ? 2 : 6;
        final endpoint = targetUrl.endsWith('/api') ? '$targetUrl/devices/$sessionId' : '$targetUrl/api/devices/$sessionId';
        final response = await _client
            .delete(
              Uri.parse(endpoint),
              headers: authHeaders(token),
            )
            .timeout(Duration(seconds: timeoutSec));

        if (response.statusCode == 200) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// 6. Log out from all other linked devices
  Future<bool> logoutAllOtherDevices(String token) async {
    final candidateUrls = _resolveCandidateUrls(null);
    for (final targetUrl in candidateUrls) {
      try {
        final isLocal = targetUrl.contains('192.168.') || targetUrl.contains('10.0.2.2') || targetUrl.contains('localhost');
        final timeoutSec = isLocal ? 2 : 6;
        final endpoint = targetUrl.endsWith('/api') ? '$targetUrl/devices/logout-all' : '$targetUrl/api/devices/logout-all';
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: authHeaders(token),
            )
            .timeout(Duration(seconds: timeoutSec));

        if (response.statusCode == 200) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Legacy support wrapper for approveQrWebLogin
  Future<bool> approveQrWebLogin(String token, String sessionId, {String? customBackendUrl, String? userId}) async {
    return approveDevicePairing(token, sessionId, "legacy", customBackendUrl: customBackendUrl);
  }

  // Mandatory Google Play Policy: Permanently delete account and user data
  Future<bool> deleteAccount(String token) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/auth/account'),
        headers: authHeaders(token),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Delete account error: $e');
      return false;
    }
  }
}

