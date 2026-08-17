import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

class ApiService {
  // Replace with your computer's local Wi-Fi IP address or production server
  static const String baseUrl = 'https://dolsyx-app.onrender.com/api';

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

      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/chats/upload'));
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        print('Upload failed: ${response.body}');
      }
    } catch (e) {
      print('Upload error: $e');
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

  Future<bool> approveQrWebLogin(String token, String sessionId, {String? customBackendUrl}) async {
    try {
      String targetBaseUrl = baseUrl;
      if (customBackendUrl != null && customBackendUrl.isNotEmpty) {
        final cleanUrl = customBackendUrl.trim();
        if (!cleanUrl.contains('localhost') && !cleanUrl.contains('127.0.0.1')) {
          targetBaseUrl = cleanUrl.endsWith('/api') ? cleanUrl : '$cleanUrl/api';
        }
      }

      final response = await http.post(
        Uri.parse('$targetBaseUrl/auth/approve-qr-session'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sessionId': sessionId}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) return true;

      if (targetBaseUrl != baseUrl) {
        final fallbackResponse = await http.post(
          Uri.parse('$baseUrl/auth/approve-qr-session'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'sessionId': sessionId}),
        );
        return fallbackResponse.statusCode == 200 || fallbackResponse.statusCode == 201;
      }
      return false;
    } catch (e) {
      print('Approve QR Web Login error: $e');
      return false;
    }
  }
}
