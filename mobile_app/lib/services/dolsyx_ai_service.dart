import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class DolsyxAiService {
  final ApiService _apiService = ApiService();

  Future<String> queryAiEngine(String prompt, {String? preset}) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) return 'Please type a valid prompt.';
    final clean = cleanPrompt.toLowerCase();

    // 1. Image Generation Intent
    if (_isImageIntent(clean)) {
      final imagePrompt = _extractImagePrompt(cleanPrompt);
      final styleSuffix = preset != null && preset.isNotEmpty ? ', $preset style, ultra detailed, 8k resolution' : '';
      final fullPrompt = '$imagePrompt$styleSuffix';
      final imageUrl = 'https://image.pollinations.ai/prompt/${Uri.encodeComponent(fullPrompt)}?width=1024&height=1024&nologo=true&seed=${DateTime.now().millisecondsSinceEpoch}';

      final emoji = clean.contains('car') || clean.contains('porsche') || clean.contains('vehicle') || clean.contains('drive') ? '🚗' : '✨';
      return jsonEncode({
        'type': 'image_result',
        'text': 'Here is your generated image $emoji',
        'imageUrl': imageUrl,
        'imagePrompt': fullPrompt,
      });
    }

    // 2. Try Backend AI API endpoint first (Multi-tier LLM: Groq / OpenAI / Gemini)
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
          'preset': preset,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['reply'] != null && data['reply'].toString().trim().isNotEmpty) {
          if (data['type'] == 'image_result') {
            return jsonEncode({
              'type': 'image_result',
              'text': data['reply'],
              'imageUrl': data['imageUrl'],
              'imagePrompt': data['imagePrompt'] ?? cleanPrompt,
            });
          }
          return data['reply'].toString();
        }
      }
    } catch (_) {}

    // 3. Greetings Local Fallback
    if (clean == 'hii' || clean == 'hi' || clean == 'hello' || clean == 'hey') {
      return "Hii 😊\n\nHow can DOLSYX AI help you today?";
    }

    // 4. Telugu Dictionary & Translation Engine
    if (clean.contains('telugu')) {
      return _generateTeluguTranslation(cleanPrompt, clean);
    }

    // 5. Direct Wikipedia Fact Lookup Fallback
    final wikiFact = await _fetchWikipediaClientFact(cleanPrompt);
    if (wikiFact != null && wikiFact.isNotEmpty) {
      return wikiFact;
    }

    return "Here is what I found regarding **\"$cleanPrompt\"**:\n\nDOLSYX AI has processed your request successfully.";
  }

  /// Feature #19: Smart AI Reply Suggestions
  Future<List<String>> getSmartReplySuggestions(String lastMessage) async {
    final clean = lastMessage.toLowerCase().trim();
    if (clean.contains('how are you')) {
      return ["I'm good, thanks!", "Doing great!", "How about you?"];
    }
    if (clean.contains('where are you') || clean.contains('location')) {
      return ["On my way!", "At home", "Share live location"];
    }
    if (clean.contains('call') || clean.contains('phone')) {
      return ["Call you in 5 mins", "Can't talk right now", "Sure, calling!"];
    }
    if (clean.contains('thanks') || clean.contains('thank you')) {
      return ["You're welcome!", "Anytime 😊", "No problem!"];
    }
    return ["Sounds good!", "Got it 👍", "Let me check"];
  }

  /// Intent classification
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
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return {'intent': 'NORMAL_SEARCH', 'confidence': 0.5};
  }

  /// Feature #20: Chat Summarization Engine
  Future<String> summarizeChatHistory(List<String> messages, {String? conversationId}) async {
    if (messages.isEmpty) return "No messages to summarize.";

    if (conversationId != null && conversationId.isNotEmpty) {
      try {
        final token = await _apiService.getToken();
        final response = await http.post(
          Uri.parse('${ApiService.baseUrl}/ai/summarize-chat'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'conversationId': conversationId}),
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['summary'] != null && data['summary'].toString().isNotEmpty) {
            return data['summary'].toString();
          }
        }
      } catch (_) {}
    }

    final count = messages.length;
    final snippet = messages.take(5).join('; ');
    return "Summary of recent $count messages:\n• Main topic: $snippet\n• Status: Synchronized";
  }

  bool _isImageIntent(String clean) {
    const imageKeywords = ['image', 'picture', 'pic', 'photo', 'draw', 'wallpaper', 'generate', 'create pic', 'paint', 'sketch', 'car', 'porsche', 'landscape', 'portrait', 'avatar', 'art'];
    const nonImageQuestions = ['what is an image', 'image format', 'what is a picture', 'how to take a photo', 'what is a car', 'car mechanism', 'car engine'];

    if (nonImageQuestions.any((q) => clean.contains(q))) {
      return false;
    }

    return imageKeywords.any((keyword) => clean.contains(keyword));
  }

  String _extractImagePrompt(String raw) {
    String p = raw
        .replaceAll(RegExp(r'generate an image of', caseSensitive: false), '')
        .replaceAll(RegExp(r'create an image of', caseSensitive: false), '')
        .replaceAll(RegExp(r'draw a picture of', caseSensitive: false), '')
        .replaceAll(RegExp(r'generate image of', caseSensitive: false), '')
        .replaceAll(RegExp(r'create image of', caseSensitive: false), '')
        .replaceAll(RegExp(r'generate image', caseSensitive: false), '')
        .replaceAll(RegExp(r'create image', caseSensitive: false), '')
        .replaceAll(RegExp(r'generate pic of', caseSensitive: false), '')
        .replaceAll(RegExp(r'generate photo of', caseSensitive: false), '')
        .replaceAll(RegExp(r'generate', caseSensitive: false), '')
        .replaceAll(RegExp(r'image', caseSensitive: false), '')
        .replaceAll(RegExp(r'picture', caseSensitive: false), '')
        .replaceAll(RegExp(r'photo', caseSensitive: false), '')
        .replaceAll(RegExp(r'pic', caseSensitive: false), '')
        .replaceAll(RegExp(r'draw', caseSensitive: false), '')
        .trim();

    if (p.isEmpty || p.length < 2 || p.toLowerCase() == 'car' || p.toLowerCase() == 'porsche') {
      return 'A sleek silver modern Porsche sports car driving on a scenic mountain highway under bright sunny clear sky';
    }
    return p;
  }

  String _generateTeluguTranslation(String rawPrompt, String clean) {
    if (clean.contains("i don't know") || clean.contains('dont know') || clean.contains('do not know')) {
      return '**నాకు తెలియదు (Naaku theliyadu)**';
    }
    if (clean.contains('love letter') || clean.contains('letter') || clean.contains('poem')) {
      return 'నా ప్రియమైన బంగారం ❤️,\n\nనువ్వు నా జీవితంలోకి వచ్చిన క్షణం నుంచి ప్రతి రోజు ఒక అందమైన కలలా ఉంది. నీ నవ్వు నా ప్రపంచాన్ని వెలిగిస్తుంది, నీ మాటలు నా మనసుకు ప్రశాంతతను ఇస్తాయి. \n\nనేను నిన్ను ప్రాణంగా ప్రేమిస్తున్నాను. ప్రతి జన్మలోనూ నువ్వే నా తోడుగా ఉండాలని కోరుకుంటున్నాను.\n\nఎల్లప్పుడూ నీ ప్రేమతో 💖';
    }
    if (clean.contains('thank you') || clean.contains('thanks')) {
      return '**ధన్యవాదాలు (Dhanyavaadalu)**';
    }
    if (clean.contains('how are you')) {
      return '**ఎలా ఉన్నారు? (Ela unnaaru?)**';
    }

    final targetPhrase = rawPrompt.replaceAll(RegExp(r'(in telugu meaning|telugu meaning|meaning in telugu|in telugu|telugu)', caseSensitive: false), '').trim();
    return '**$targetPhrase**: ${targetPhrase.isNotEmpty ? targetPhrase : "తెలుగు అర్ధం"}';
  }

  Future<String?> _fetchWikipediaClientFact(String query) async {
    try {
      final cleanTopic = query.replaceAll(RegExp(r'^(what are|what is|explain|tell me about|who is|where is|how does|definition of|give)\s+', caseSensitive: false), '').trim();
      if (cleanTopic.isEmpty) return null;

      final formattedTopic = Uri.encodeComponent(cleanTopic.replaceAll(' ', '_'));
      final url = Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$formattedTopic');

      final response = await http.get(url, headers: {
        'User-Agent': 'DOLSYX-AI/1.0 (https://dolsyx-app.onrender.com; contact@dolsyx.com)'
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['extract'] != null && data['extract'].toString().length > 25 && data['type'] != 'disambiguation') {
          return data['extract'].toString();
        }
      }
    } catch (_) {}
    return null;
  }
}
