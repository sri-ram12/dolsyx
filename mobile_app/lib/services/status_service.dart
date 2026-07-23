import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/status.dart';
import 'api_service.dart';

class StatusService {
  final ApiService _apiService = ApiService();

  Future<List<StatusModel>> getStatuses() async {
    try {
      final token = await _apiService.getToken();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/status'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => StatusModel.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error getting statuses: $e');
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

      final streamedResponse = await request.send();
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

  Future<bool> createStatus(String mediaUrl, String mediaType, String content) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'mediaUrl': mediaUrl,
          'mediaType': mediaType,
          'content': content,
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
      await http.post(
        Uri.parse('${ApiService.baseUrl}/status/$statusId/view'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      print('Error viewing status: $e');
    }
  }
}
