import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

class ApiService {
  // DOLSYX Local Dev Backend (Your computer's Wi-Fi IP)
  static const String baseUrl = 'http://192.168.0.76:4000/api';

  static String getMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
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
      final response = await http.post(
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
      final response = await http.post(
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
      final response = await http.post(
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
      if (token == null) return null;

      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/chats/upload'));
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200 && response.statusCode != 201) {
        request = http.MultipartRequest('POST', Uri.parse('$baseUrl/uploads'));
        request.headers['Authorization'] = 'Bearer $token';
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
        streamedResponse = await request.send();
        response = await http.Response.fromStream(streamedResponse);
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } else {
        print('Upload failed: HTTP ${response.statusCode} - ${response.body}');
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

      final response = await http.get(
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

      final response = await http.put(
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

      final response = await http.get(
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

      final response = await http.get(
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

      final response = await http.post(
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

      final response = await http.get(
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

      final response = await http.delete(
        Uri.parse('$baseUrl/auth/block/$targetUserId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Unblock error: $e');
      return false;
    }
  }

  Future<bool> approveQrWebLogin(String token, String sessionId, {String? customBackendUrl, String? userId}) async {
    try {
      final candidateUrls = <String>[];

      void addCandidate(String? url) {
        if (url == null || url.trim().isEmpty) return;
        var clean = url.trim();
        while (clean.endsWith('/')) {
          clean = clean.substring(0, clean.length - 1);
        }
        if (clean.contains('localhost') || clean.contains('127.0.0.1')) {
          clean = clean.replaceAll('localhost', '192.168.0.182').replaceAll('127.0.0.1', '192.168.0.182');
        }
        final withApi = clean.endsWith('/api') ? clean : '$clean/api';
        if (!candidateUrls.contains(withApi)) candidateUrls.add(withApi);
        if (clean.endsWith('/api')) {
          final withoutApi = clean.substring(0, clean.length - 4);
          if (!candidateUrls.contains(withoutApi)) candidateUrls.add(withoutApi);
        } else {
          if (!candidateUrls.contains(clean)) candidateUrls.add(clean);
        }
      }

      addCandidate(customBackendUrl);
      addCandidate('http://192.168.0.182:4000/api');
      addCandidate(baseUrl);

      final bodyData = <String, dynamic>{
        'sessionId': sessionId,
        if (userId != null && userId.isNotEmpty) 'userId': userId,
      };

      for (final targetUrl in candidateUrls) {
        try {
          final response = await http
              .post(
                Uri.parse('$targetUrl/auth/approve-qr-session'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(bodyData),
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode == 200 || response.statusCode == 201) {
            return true;
          }
        } catch (_) {
          // Try next candidate URL
        }
      }
      return false;
    } catch (e) {
      print('Approve QR Web Login error: $e');
      return false;
    }
  }

  // Mandatory Google Play Policy: Permanently delete account and user data
  Future<bool> deleteAccount(String token) async {
    try {
      final response = await http.delete(
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

