import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/status.dart';
import 'api_service.dart';

class StatusService {
  final ApiService _apiService = ApiService();

  Future<List<UserStatusGroup>> getStatuses() async {
    try {
      final token = await _apiService.getToken();
      if (token != null) {
        final response = await ApiService.client.get(
          Uri.parse('${ApiService.baseUrl}/status'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        );

        if (response.statusCode == 200) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_statuses_v1', response.body);
          final List<dynamic> data = jsonDecode(response.body);
          return data.map((json) => UserStatusGroup.fromJson(json)).toList();
        }
      }
    } catch (e) {
      print('Error getting statuses: $e');
    }
    return await getCachedStatuses();
  }

  Future<List<UserStatusGroup>> getCachedStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString('cached_statuses_v1');
      if (cachedData != null) {
        final List<dynamic> data = jsonDecode(cachedData);
        return data.map((json) => UserStatusGroup.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error reading cached statuses: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> uploadStatusMedia(String filePath) async {
    try {
      final token = await _apiService.getToken();
      if (token == null) return null;

      final request = http.MultipartRequest('POST', Uri.parse('${ApiService.baseUrl}/status/upload'));
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await ApiService.client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        print('Status upload failed: ${response.body}');
      }
    } catch (e) {
      print('Error uploading status media: $e');
    }
    return null;
  }

  Future<bool> createStatus(String mediaUrl, String mediaType, String content, {String? bgColor}) async {
    try {
      final token = await _apiService.getToken();
      final response = await ApiService.client.post(
        Uri.parse('${ApiService.baseUrl}/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'mediaUrl': mediaUrl.isNotEmpty ? mediaUrl : null,
          'mediaType': mediaType,
          'caption': content.isNotEmpty ? content : null,
          'content': content,
          'bgColor': bgColor ?? '#075E54',
        }),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error creating status: $e');
      return false;
    }
  }

  Future<void> viewStatus(String statusId) async {
    try {
      final token = await _apiService.getToken();
      await ApiService.client.post(
        Uri.parse('${ApiService.baseUrl}/status/$statusId/view'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      print('Error viewing status: $e');
    }
  }

  Future<bool> muteStatus(String contactId) async {
    try {
      final token = await _apiService.getToken();
      final response = await ApiService.client.post(
        Uri.parse('${ApiService.baseUrl}/status/mute'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'contactId': contactId}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error muting status: $e');
      return false;
    }
  }

  Future<bool> unmuteStatus(String contactId) async {
    try {
      final token = await _apiService.getToken();
      final response = await ApiService.client.post(
        Uri.parse('${ApiService.baseUrl}/status/unmute'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'contactId': contactId}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error unmuting status: $e');
      return false;
    }
  }

  Future<bool> deleteStatus(String statusId) async {
    try {
      final token = await _apiService.getToken();
      final response = await ApiService.client.delete(
        Uri.parse('${ApiService.baseUrl}/status/$statusId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting status: $e');
      return false;
    }
  }
}
