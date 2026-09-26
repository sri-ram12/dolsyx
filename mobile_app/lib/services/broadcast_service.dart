import 'dart:convert';
import 'api_service.dart';

/// Phase 18 – Broadcast List service.
/// Communicates with /api/chats/broadcasts endpoints.
class BroadcastService {
  final ApiService _api = ApiService();

  // ── Create ──────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> createBroadcastList({
    required String name,
    required List<String> recipientIds,
  }) async {
    try {
      final token = await _api.getToken();
      if (token == null) return null;

      final response = await ApiService.client.post(
        Uri.parse('${ApiService.baseUrl}/chats/broadcasts'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'name': name, 'recipientIds': recipientIds}),
      );

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('[BroadcastService] createBroadcastList failed: ${response.body}');
    } catch (e) {
      print('[BroadcastService] createBroadcastList error: $e');
    }
    return null;
  }

  // ── Fetch ───────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getBroadcastLists() async {
    try {
      final token = await _api.getToken();
      if (token == null) return [];

      final response = await ApiService.client.get(
        Uri.parse('${ApiService.baseUrl}/chats/broadcasts'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('[BroadcastService] getBroadcastLists error: $e');
    }
    return [];
  }

  // ── Send ────────────────────────────────────────────────────────────────────
  Future<bool> sendBroadcast({
    required String broadcastId,
    String? content,
    String? mediaUrl,
    String? mediaType,
  }) async {
    try {
      final token = await _api.getToken();
      if (token == null) return false;

      final response = await ApiService.client.post(
        Uri.parse('${ApiService.baseUrl}/chats/broadcasts/$broadcastId/send'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          if (content != null) 'content': content,
          if (mediaUrl != null) 'mediaUrl': mediaUrl,
          if (mediaType != null) 'mediaType': mediaType,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('[BroadcastService] sendBroadcast error: $e');
      return false;
    }
  }

  // ── Manage Recipients ───────────────────────────────────────────────────────
  Future<bool> updateRecipients({
    required String broadcastId,
    List<String>? addIds,
    List<String>? removeIds,
  }) async {
    try {
      final token = await _api.getToken();
      if (token == null) return false;

      final response = await ApiService.client.patch(
        Uri.parse('${ApiService.baseUrl}/chats/broadcasts/$broadcastId/recipients'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          if (addIds != null) 'addIds': addIds,
          if (removeIds != null) 'removeIds': removeIds,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('[BroadcastService] updateRecipients error: $e');
      return false;
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────────────
  Future<bool> deleteBroadcastList(String broadcastId) async {
    try {
      final token = await _api.getToken();
      if (token == null) return false;

      final response = await ApiService.client.delete(
        Uri.parse('${ApiService.baseUrl}/chats/broadcasts/$broadcastId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      return response.statusCode == 200;
    } catch (e) {
      print('[BroadcastService] deleteBroadcastList error: $e');
      return false;
    }
  }
}
