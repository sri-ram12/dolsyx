import 'dart:convert';
import '../../services/api_service.dart';

class E2EEApi {
  static String get _baseUrl => ApiService.baseUrl;

  static Future<void> uploadKeys(Map<String, dynamic> payload, String token) async {
    final response = await ApiService.client.post(
      Uri.parse('$_baseUrl/keys/upload'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to upload keys: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> fetchKeys(String email, String token) async {
    final response = await ApiService.client.get(
      Uri.parse('$_baseUrl/keys/fetch/$email'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch keys: ${response.body}');
    }

    return jsonDecode(response.body);
  }

  static Future<void> sendEncryptedMessage(Map<String, dynamic> payload, String token) async {
    final response = await ApiService.client.post(
      Uri.parse('$_baseUrl/messages/send'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to send encrypted message: ${response.body}');
    }
  }
}
