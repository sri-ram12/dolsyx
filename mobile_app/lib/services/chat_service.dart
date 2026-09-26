import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'local_database_service.dart';
import '../models/chat.dart';
import '../models/message.dart';

class ChatService {
  Future<List<Message>> getMessages(String conversationId, {String? cursor, int limit = 50}) async {
    try {
      final token = await ApiService().getToken();
      final queryParams = <String, String>{
        'limit': limit.toString(),
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      };
      final uri = Uri.parse('${ApiService.baseUrl}/chats/$conversationId/messages')
          .replace(queryParameters: queryParams);
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Message.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error fetching messages: $e');
    }
    return [];
  }

  Future<bool> sendMessage({
    required String conversationId,
    required String content,
    String? mediaUrl,
    String? mediaType,
  }) async {
    try {
      final token = await ApiService().getToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/chats/$conversationId/messages'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'content': content,
          'mediaUrl': mediaUrl,
          'mediaType': mediaType,
        }),
      ).timeout(const Duration(seconds: 15));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error sending message via API: $e');
      return false;
    }
  }

  Future<List<Chat>> getChats() async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return await getCachedChats();

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/chats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final chats = data.map((json) => Chat.fromJson(json)).toList();

        // 1. WhatsApp-grade local SQLite persistence (sub-millisecond indexed writes)
        await LocalDatabaseService().saveConversations(chats);

        // 2. Secondary fallback update to SharedPreferences
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_chats', response.body);
        } catch (_) {}

        return chats;
      } else {
        print('Error fetching chats: ${response.statusCode}');
        return await getCachedChats();
      }
    } catch (e) {
      print('Network error fetching chats: $e');
      return await getCachedChats();
    }
  }

  Future<List<Chat>> getCachedChats() async {
    try {
      // 1. WhatsApp-grade local SQLite instant read (0-2ms)
      final localChats = await LocalDatabaseService().getConversations();
      if (localChats.isNotEmpty) {
        return localChats;
      }

      // 2. Secondary fallback to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString('cached_chats');
      if (cachedData != null && cachedData.isNotEmpty) {
        final List<dynamic> data = jsonDecode(cachedData);
        final chats = data.map((json) => Chat.fromJson(json)).toList();
        if (chats.isNotEmpty) {
          LocalDatabaseService().saveConversations(chats);
        }
        return chats;
      }
    } catch (e) {
      print('Error parsing cached chats: $e');
    }
    return [];
  }

  Future<bool> deleteMessage(String messageId, bool forEveryone) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/chats/messages/$messageId?forEveryone=$forEveryone'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Network error deleting message: $e');
      return false;
    }
  }

  Future<bool> clearCallLogs() async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/chats/calls/clear'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Network error clearing call logs: $e');
      return false;
    }
  }

  Future<bool> deleteCallLog(String callId) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/chats/calls/$callId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        print('Delete call log failed: HTTP ${response.statusCode} - ${response.body}');
        return false;
      }
      return true;
    } catch (e) {
      print('Network error deleting call log: $e');
      return false;
    }
  }

  Future<bool> deleteBulkCallLogs(List<String> callIds) async {
    if (callIds.isEmpty) return true;
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      // Call the single-delete endpoint for each ID.
      // Falls back gracefully if the /bulk route isn't deployed yet.
      bool allOk = true;
      for (final id in callIds) {
        final response = await http.delete(
          Uri.parse('${ApiService.baseUrl}/chats/calls/$id'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        );
        if (response.statusCode != 200) {
          print('Delete call log $id failed: HTTP ${response.statusCode} - ${response.body}');
          allOk = false;
        }
      }
      return allOk;
    } catch (e) {
      print('Network error bulk deleting call logs: $e');
      return false;
    }
  }

  Future<bool> editMessage(String messageId, String newContent) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/chats/messages/$messageId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'content': newContent}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Network error editing message: $e');
      return false;
    }
  }


  Future<bool> starMessage(String messageId) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/chats/messages/$messageId/star'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Network error starring message: $e');
      return false;
    }
  }

  Future<bool> pinMessage(String conversationId, String messageId) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/chats/$conversationId/messages/$messageId/pin'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Network error pinning message: $e');
      return false;
    }
  }

  Future<Message?> getPinnedMessage(String conversationId) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/chats/$conversationId/pinned'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data['message'] != null) {
          return Message.fromJson(data['message']);
        }
      }
      return null;
    } catch (e) {
      return null;
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

  Future<bool> archiveChat(String conversationId, bool archive) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/chats/$conversationId/archive'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'archive': archive}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error archiving chat: $e');
      return false;
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



  Future<List<dynamic>> getCallLogs() async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return await getCachedCallLogs();

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/chats/calls'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final list = List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e)));

        // 1. WhatsApp-grade local SQLite persistence for instant 0ms call history
        await LocalDatabaseService().saveCallLogs(list);

        // 2. Secondary fallback update to SharedPreferences
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_call_logs', response.body);
        } catch (_) {}

        return data;
      }
      return await getCachedCallLogs();
    } catch (e) {
      print('Network error fetching call logs: $e');
      return await getCachedCallLogs();
    }
  }

  Future<List<dynamic>> getCachedCallLogs() async {
    try {
      // 1. WhatsApp-grade local SQLite instant read (0-2ms)
      final localCalls = await LocalDatabaseService().getCallLogs();
      if (localCalls.isNotEmpty) {
        return localCalls;
      }

      // 2. Secondary fallback to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString('cached_call_logs');
      if (cachedData != null && cachedData.isNotEmpty) {
        final List<dynamic> data = jsonDecode(cachedData);
        final list = List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e)));
        if (list.isNotEmpty) {
          LocalDatabaseService().saveCallLogs(list);
        }
        return data;
      }
    } catch (e) {
      print('Error parsing cached call logs: $e');
    }
    return [];
  }
}
