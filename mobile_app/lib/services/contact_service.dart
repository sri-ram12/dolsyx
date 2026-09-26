import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class ContactService {
  static const String _base = '${ApiService.baseUrl}/contacts';

  // Search for a user by email or username
  static Future<Map<String, dynamic>?> searchUser(String token, String query) async {
    final res = await ApiService.client.get(
      Uri.parse('$_base/search?query=${Uri.encodeQueryComponent(query)}'),
      headers: ApiService.authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  // Add contact by email or username
  static Future<Map<String, dynamic>?> addContact(String token, String query, {String? savedName}) async {
    final res = await ApiService.client.post(
      Uri.parse(_base),
      headers: ApiService.authHeaders(token),
      body: jsonEncode({'query': query, 'savedName': savedName}),
    );
    if (res.statusCode == 201) return jsonDecode(res.body);
    final body = jsonDecode(res.body);
    throw Exception(body['message'] ?? 'Failed to add contact');
  }

  // Add contact by userId (called from chat room)
  static Future<Map<String, dynamic>?> addContactById(String token, String contactUserId, {String? savedName}) async {
    final res = await ApiService.client.post(
      Uri.parse('$_base/by-id'),
      headers: ApiService.authHeaders(token),
      body: jsonEncode({'contactUserId': contactUserId, 'savedName': savedName}),
    );
    if (res.statusCode == 201) return jsonDecode(res.body);
    final body = jsonDecode(res.body);
    throw Exception(body['message'] ?? 'Failed to add contact');
  }

  // Get all contacts
  static Future<List<dynamic>> getContacts(String token) async {
    try {
      final res = await ApiService.client.get(
        Uri.parse(_base),
        headers: ApiService.authHeaders(token),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return [];
  }

  // Check if a userId is already in contacts
  static Future<bool> isContact(String token, String targetUserId) async {
    try {
      final res = await ApiService.client.get(
        Uri.parse('$_base/check/$targetUserId'),
        headers: ApiService.authHeaders(token),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['isContact'] == true;
      }
    } catch (_) {}
    return false;
  }

  // Update contact (rename / toggle favorite)
  static Future<bool> updateContact(String token, String contactId, {String? savedName, bool? isFavorite}) async {
    try {
      final res = await ApiService.client.put(
        Uri.parse('$_base/$contactId'),
        headers: ApiService.authHeaders(token),
        body: jsonEncode({
          if (savedName != null) 'savedName': savedName,
          if (isFavorite != null) 'isFavorite': isFavorite,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Delete contact (handles both Contact Record ID and Target User ID)
  static Future<bool> deleteContact(String token, String contactIdOrUserId) async {
    if (contactIdOrUserId.trim().isEmpty) return false;
    final cleanId = contactIdOrUserId.trim();

    try {
      // 1. Direct attempt
      final res = await ApiService.client.delete(
        Uri.parse('$_base/$cleanId'),
        headers: ApiService.authHeaders(token),
      );
      if (res.statusCode == 200) return true;

      // 2. Check if cleanId is a targetUserId and get the Contact record ID
      final checkRes = await ApiService.client.get(
        Uri.parse('$_base/check/$cleanId'),
        headers: ApiService.authHeaders(token),
      );
      if (checkRes.statusCode == 200) {
        final data = jsonDecode(checkRes.body);
        if (data['isContact'] == true && data['contact'] != null) {
          final recordId = data['contact']['id']?.toString();
          if (recordId != null && recordId.isNotEmpty && recordId != cleanId) {
            final deleteRes = await ApiService.client.delete(
              Uri.parse('$_base/$recordId'),
              headers: ApiService.authHeaders(token),
            );
            if (deleteRes.statusCode == 200) return true;
          }
        }
      }

      // 3. Fallback: Search all saved contacts
      final allContacts = await getContacts(token);
      for (final c in allContacts) {
        final recordId = c['id']?.toString();
        final cUserId = (c['contactId'] ?? c['contact']?['id'] ?? c['contact']?['_id'])?.toString();
        final email = (c['contact']?['email'] ?? '').toString();
        final username = (c['contact']?['username'] ?? '').toString();

        if (recordId == cleanId ||
            cUserId == cleanId ||
            (email.isNotEmpty && email.toLowerCase() == cleanId.toLowerCase()) ||
            (username.isNotEmpty && username.toLowerCase() == cleanId.toLowerCase())) {
          if (recordId != null && recordId.isNotEmpty) {
            final deleteRes = await ApiService.client.delete(
              Uri.parse('$_base/$recordId'),
              headers: ApiService.authHeaders(token),
            );
            if (deleteRes.statusCode == 200) return true;
          }
        }
      }
    } catch (e) {
      print('Error deleting contact: $e');
    }
    return false;
  }
}
