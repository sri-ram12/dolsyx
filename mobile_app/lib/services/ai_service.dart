import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class AIService {
  final ApiService _apiService = ApiService();

  Future<String> askAI(String prompt) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/ai/chat'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'prompt': prompt}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['reply'] ?? 'No response received.';
      }
    } catch (_) {}

    // Smart Client-Side Fallback Engine if offline
    final clean = prompt.toLowerCase().trim();
    if (clean.contains('hello') || clean.contains('hi')) {
      return 'Hello! I am DOLSYX AI. How can I assist you today?';
    } else if (clean.contains('code') || clean.contains('function')) {
      return 'Here is a clean code snippet:\n```dart\nvoid dolsyxTask() {\n  print("Executed via DOLSYX AI");\n}\n```';
    } else if (clean.contains('email') || clean.contains('draft')) {
      return 'Subject: Quick Update\n\nDear Team,\n\nI wanted to share the latest updates regarding our project roadmap.\n\nBest regards,\nDOLSYX AI';
    }
    return 'That is a great question about "$prompt". I am ready to assist you with research, drafting content, or brainstorming ideas!';
  }
}
