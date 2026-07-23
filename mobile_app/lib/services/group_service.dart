import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class GroupService {
  final ApiService _apiService = ApiService();

  Future<Map<String, dynamic>?> createGroup(String name, String? description, String? avatarUrl, List<String> memberIds) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/groups'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'description': description,
          'avatarUrl': avatarUrl,
          'memberIds': memberIds,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        print('Create group failed: ${response.body}');
      }
    } catch (e) {
      print('Error creating group: $e');
    }
    return null;
  }

  Future<bool> updateGroup(String conversationId, String name, String? description, String? avatarUrl) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/groups/$conversationId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'description': description,
          'avatarUrl': avatarUrl,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error updating group: $e');
      return false;
    }
  }

  Future<bool> addMember(String conversationId, String userId) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/groups/$conversationId/members'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': userId,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error adding member: $e');
      return false;
    }
  }

  Future<bool> removeMember(String conversationId, String targetUserId) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/groups/$conversationId/members/$targetUserId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error removing member: $e');
      return false;
    }
  }

  Future<bool> changeMemberRole(String conversationId, String targetUserId, String role) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/groups/$conversationId/role'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'targetUserId': targetUserId,
          'role': role,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error changing role: $e');
      return false;
    }
  }
}
