import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class DolsyxAiService {
  final ApiService _apiService = ApiService();

  /// Primary AI query function - calls real backend AI Gateway
  Future<String> queryAiEngine(
    String prompt, {
    String? preset,
    String? conversationId,
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) return 'Please enter a prompt.';

    try {
      final token = await _apiService.getToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/ai/chat'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'prompt': cleanPrompt,
          'preset': preset?.toLowerCase(),
          'conversationId': conversationId,
        }),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Handle Image result
        if (data['type'] == 'image_result' || data['imageUrl'] != null) {
          return jsonEncode({
            'type': 'image_result',
            'text': data['reply'] ?? 'Here is your generated image ✨',
            'imageUrl': data['imageUrl'] ?? (data['media'] != null ? data['media']['url'] : null),
            'imagePrompt': data['imagePrompt'] ?? cleanPrompt,
            'conversationId': data['conversationId'],
          });
        }

        // Handle standard text reply
        if (data['reply'] != null && data['reply'].toString().trim().isNotEmpty) {
          return data['reply'].toString().trim();
        }
      } else {
        try {
          final err = jsonDecode(response.body);
          return err['error'] ?? err['message'] ?? 'DOLSYX AI server error (${response.statusCode})';
        } catch (_) {
          return 'DOLSYX AI server error (${response.statusCode})';
        }
      }
    } catch (e) {
      print('DOLSYX AI queryAiEngine error: $e');
      return 'DOLSYX AI encountered a connection issue. Please check your network and retry.';
    }

    return 'No response was generated. Please try again.';
  }

  /// Real-time Token-by-Token Live Streaming from Backend
  Stream<Map<String, dynamic>> streamAiResponse(
    String prompt, {
    String? preset,
    String? conversationId,
    http.Client? client,
  }) async* {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      yield {'type': 'error', 'error': 'Prompt cannot be empty'};
      return;
    }

    final activeClient = client ?? http.Client();

    try {
      final token = await _apiService.getToken();
      final request = http.Request('POST', Uri.parse('${ApiService.baseUrl}/ai/stream'));
      request.headers['Content-Type'] = 'application/json';
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.body = jsonEncode({
        'prompt': cleanPrompt,
        'preset': preset?.toLowerCase(),
        'conversationId': conversationId,
      });

      final streamedResponse = await activeClient.send(request);

      if (streamedResponse.statusCode != 200) {
        yield {'type': 'error', 'error': 'Streaming connection failed (HTTP ${streamedResponse.statusCode})'};
        return;
      }

      String buffer = '';
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
          final dataStr = trimmed.substring(5).trim();
          if (dataStr == '[DONE]') {
            yield {'type': 'done'};
            return;
          }

          try {
            final parsed = jsonDecode(dataStr);
            if (parsed is Map) {
              if (parsed['token'] != null) {
                yield {'type': 'token', 'token': parsed['token']};
              } else if (parsed['toolCall'] != null) {
                yield {'type': 'tool', 'tool': parsed['toolCall']['name'] ?? 'Tool'};
              } else if (parsed['complete'] == true) {
                yield {
                  'type': 'complete',
                  'fullText': parsed['fullText'],
                  'conversationId': parsed['metadata']?['conversationId'],
                };
              } else if (parsed['error'] != null) {
                yield {'type': 'error', 'error': parsed['error']};
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      yield {'type': 'error', 'error': e.toString()};
    } finally {
      if (client == null) {
        activeClient.close();
      }
    }
  }

  /// Feature: Smart AI Reply Suggestions powered by real backend context action
  Future<List<String>> getSmartReplySuggestions(String lastMessage) async {
    final clean = lastMessage.trim();
    if (clean.isEmpty) return ["Sounds good!", "Got it 👍", "Let me check"];

    try {
      final token = await _apiService.getToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/ai/context-action'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'action': 'generate_reply',
          'text': clean,
        }),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw = data['result']?.toString() ?? '';
        final lines = raw
            .split('\n')
            .map((l) => l.replaceAll(RegExp(r'^\d+[\.\)]\s*|"'), '').trim())
            .where((l) => l.isNotEmpty && l.length < 60)
            .take(3)
            .toList();

        if (lines.isNotEmpty) return lines;
      }
    } catch (_) {}

    return ["Sounds good!", "Got it 👍", "Let me check"];
  }

  /// Feature: Intent classification for search bar
  Future<Map<String, dynamic>> classifyQuery(String query) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/ai/classify'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': query.trim()}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return {'intent': 'TEXT_GENERATION', 'confidence': 0.8};
  }

  /// Feature: Chat Summarization Engine
  Future<String> summarizeChatHistory(List<String> messages, {String? conversationId, String? query}) async {
    if (messages.isEmpty && conversationId == null) return "No messages to summarize.";

    if (conversationId != null && conversationId.isNotEmpty) {
      try {
        final token = await _apiService.getToken();
        final response = await http.post(
          Uri.parse('${ApiService.baseUrl}/ai/summarize-chat'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'conversationId': conversationId,
            'query': query,
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['summary'] != null && data['summary'].toString().isNotEmpty) {
            return data['summary'].toString();
          }
        }
      } catch (_) {}
    }

    final snippet = messages.take(15).join('\n');
    return queryAiEngine('Summarize this conversation clearly:\n\n$snippet');
  }

  /// Context actions (explain, translate, rewrite, fix grammar)
  Future<String> performContextAction(String action, String text, {String? targetLanguage}) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/ai/context-action'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'action': action,
          'text': text,
          'targetLanguage': targetLanguage,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['result'] ?? text;
      }
    } catch (_) {}
    return text;
  }

  /// Conversation CRUD
  Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final token = await _apiService.getToken();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/ai/conversations'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['conversations'] as List<dynamic>?;
        return list?.map((c) => Map<String, dynamic>.from(c)).toList() ?? [];
      }
    } catch (_) {}
    return [];
  }

  Future<bool> deleteConversation(String conversationId) async {
    try {
      final token = await _apiService.getToken();
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/ai/conversations/$conversationId'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 6));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> sendFeedback(String messageId, String feedback, {String? comment}) async {
    try {
      final token = await _apiService.getToken();
      await http.post(
        Uri.parse('${ApiService.baseUrl}/ai/feedback'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'messageId': messageId,
          'feedback': feedback,
          'comment': comment,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
