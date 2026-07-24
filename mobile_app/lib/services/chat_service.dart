import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../models/chat.dart';

class ChatService {
  Future<List<Chat>> getChats() async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return [];

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/chats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Chat.fromJson(json)).toList();
      } else {
        print('Error fetching chats: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Network error fetching chats: $e');
      return [];
    }
  }

  Future<List<dynamic>> searchUsers(String query) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return [];

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/chats/search?query=$query'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print('Network error searching users: $e');
      return [];
    }
  }

  Future<Chat?> createDirectChat(String targetUserId) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/chats/direct'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'targetUserId': targetUserId}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return Chat.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      print('Network error creating direct chat: $e');
      return null;
    }
  }

  Future<bool> deleteChat(String conversationId) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/chats/$conversationId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting chat: $e');
      return false;
    }
  }

  Future<bool> clearChat(String conversationId) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/chats/$conversationId/messages'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error clearing chat: $e');
      return false;
    }
  }

  Future<bool> updateChatSettings(String conversationId, Map<String, dynamic> settings) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.patch(
        Uri.parse('${ApiService.baseUrl}/chats/$conversationId/participant'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: jsonEncode(settings),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error updating chat settings: $e');
      return false;
    }
  }

  Future<bool> clearCallLogs() async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/chats/calls/clear'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error clearing call logs: $e');
      return false;
    }
  }

  Future<List<dynamic>> getCallLogs() async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return [];

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/chats/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print('Network error fetching call logs: $e');
      return [];
    }
  }
}
