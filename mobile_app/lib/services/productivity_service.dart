import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class ProductivityService {
  final ApiService _apiService = ApiService();

  Future<List<dynamic>> getNotes() async {
    try {
      final token = await _apiService.getToken();
      final response = await ApiService.client.get(
        Uri.parse('${ApiService.baseUrl}/productivity/notes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (e) {
      print('Get notes error: $e');
    }
    return [];
  }

  Future<bool> createNote(String title, String content, String color) async {
    try {
      final token = await _apiService.getToken();
      final response = await ApiService.client.post(
        Uri.parse('${ApiService.baseUrl}/productivity/notes'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'title': title, 'content': content, 'color': color}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Create note error: $e');
      return false;
    }
  }

  Future<List<dynamic>> getTasks() async {
    try {
      final token = await _apiService.getToken();
      final response = await ApiService.client.get(
        Uri.parse('${ApiService.baseUrl}/productivity/tasks'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (e) {
      print('Get tasks error: $e');
    }
    return [];
  }

  Future<bool> createTask(String title, String description, DateTime? dueDate) async {
    try {
      final token = await _apiService.getToken();
      final response = await ApiService.client.post(
        Uri.parse('${ApiService.baseUrl}/productivity/tasks'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'title': title,
          'description': description,
          'dueDate': dueDate?.toIso8601String(),
        }),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Create task error: $e');
      return false;
    }
  }

  Future<bool> updateTaskStatus(String taskId, String status) async {
    try {
      final token = await _apiService.getToken();
      final response = await ApiService.client.put(
        Uri.parse('${ApiService.baseUrl}/productivity/tasks/$taskId'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'status': status}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Update task error: $e');
      return false;
    }
  }
}
