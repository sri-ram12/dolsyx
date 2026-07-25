import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class ContactService {
  static const String _base = '${ApiService.baseUrl}/contacts';

  // Search for a user by email or username
  static Future<Map<String, dynamic>?> searchUser(String token, String query) async {
    final res = await http.get(
      Uri.parse('$_base/search?query=${Uri.encodeQueryComponent(query)}'),
      headers: ApiService.authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return null;
  }

  // Add contact by email or username
  static Future<Map<String, dynamic>?> addContact(String token, String query, {String? savedName}) async {
    final res = await http.post(
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
    final res = await http.post(
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
    final res = await http.get(
      Uri.parse(_base),
      headers: ApiService.authHeaders(token),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    return [];
  }

  // Check if a userId is already in contacts
  static Future<bool> isContact(String token, String targetUserId) async {
    final res = await http.get(
      Uri.parse('$_base/check/$targetUserId'),
      headers: ApiService.authHeaders(token),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      return body['isContact'] == true;
    }
    return false;
  }

  // Update contact (rename / toggle favorite)
  static Future<bool> updateContact(String token, String contactId, {String? savedName, bool? isFavorite}) async {
    final res = await http.put(
      Uri.parse('$_base/$contactId'),
      headers: ApiService.authHeaders(token),
      body: jsonEncode({
        if (savedName != null) 'savedName': savedName,
        if (isFavorite != null) 'isFavorite': isFavorite,
      }),
    );
    return res.statusCode == 200;
  }

  // Delete contact
  static Future<bool> deleteContact(String token, String contactId) async {
    final res = await http.delete(
      Uri.parse('$_base/$contactId'),
      headers: ApiService.authHeaders(token),
    );
    return res.statusCode == 200;
  }
}
