import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../services/dolsyx_ai_service.dart';
import '../widgets/full_screen_image_view.dart';

class DolsyxAiScreen extends StatefulWidget {
  const DolsyxAiScreen({super.key});

  @override
  State<DolsyxAiScreen> createState() => _DolsyxAiScreenState();
}

class _DolsyxAiScreenState extends State<DolsyxAiScreen> {
  final DolsyxAiService _aiService = DolsyxAiService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'ai',
      'text': 'Hello! I am **DOLSYX AI**, your intelligent assistant. Ask me questions, generate images, write code, or draft emails!',
      'time': DateTime.now(),
      'type': 'text',
      'options': [],
      'imageUrl': null,
    }
  ];
  bool _isThinking = false;

  Future<void> _sendPrompt(String promptText) async {
    final prompt = promptText.trim();
    if (prompt.isEmpty || _isThinking) return;

    _messageController.clear();
    final userTime = DateTime.now();

    setState(() {
      _messages.add({
        'sender': 'user',
        'text': prompt,
        'time': userTime,
        'type': 'text',
        'options': [],
        'imageUrl': null,
      });
      _isThinking = true;
    });
    _scrollToBottom();

    final rawResponse = await _aiService.queryAiEngine(prompt);

    if (mounted) {
      String replyText = rawResponse;
      String messageType = 'text';
      List<dynamic> options = [];
      String? imageUrl;

      // Try parsing JSON payload from AI engine
      try {
        if (rawResponse.trim().startsWith('{') && rawResponse.trim().endsWith('}')) {
          final parsed = jsonDecode(rawResponse);
          replyText = parsed['text'] ?? rawResponse;
          messageType = parsed['type'] ?? 'text';
          options = parsed['options'] ?? [];
          imageUrl = parsed['imageUrl'];
        }
      } catch (_) {}

      setState(() {
        _isThinking = false;
        _messages.add({
          'sender': 'ai',
          'text': replyText,
          'time': DateTime.now(),
          'type': messageType,
          'options': options,
          'imageUrl': imageUrl,
        });
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2C34),
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF3B82F6)],
                ),
              ),
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF0B141A),
                child: Icon(Icons.smart_toy, color: Color(0xFFEC4899), size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'DOLSYX AI',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Always active • Interactive AI',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['sender'] == 'user';
                final options = msg['options'] as List<dynamic>? ?? [];
                final imageUrl = msg['imageUrl'] as String?;

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        // Main Message Bubble
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF005C4B) : const Color(0xFF202C33),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: Radius.circular(isUser ? 14 : 2),
                              bottomRight: Radius.circular(isUser ? 2 : 14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isUser)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.smart_toy, color: Color(0xFFEC4899), size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'DOLSYX AI 🤖',
                                        style: TextStyle(color: Color(0xFFEC4899), fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              Text(
                                msg['text'],
                                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
                              ),

                              // Embedded Image preview if present
                              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => FullScreenImageView(imageUrl: imageUrl)),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          height: 220,
                                          color: const Color(0xFF111B21),
                                          child: const Center(
                                            child: CircularProgressIndicator(color: Color(0xFFEC4899)),
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        height: 180,
                                        color: Colors.black26,
                                        child: const Center(
                                          child: Icon(Icons.broken_image, color: Colors.white38, size: 40),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    DateFormat('hh:mm a').format(msg['time']),
                                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                                  ),
                                  if (isUser) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.done_all, color: Color(0xFF53BDEB), size: 14),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Interactive Action Buttons (WhatsApp/MobileGPT style)
                        if (!isUser && options.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Column(
                            children: options.map((opt) {
                              final label = opt['label'] ?? 'Proceed';
                              final isConfirm = label.contains('Yes') || label.contains('Proceed');

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2A3942),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(
                                          color: isConfirm ? const Color(0xFF00A884).withOpacity(0.5) : Colors.white12,
                                        ),
                                      ),
                                    ),
                                    onPressed: () => _sendPrompt(label),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: isConfirm ? const Color(0xFF00A884) : const Color(0xFFEA80FC),
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Thinking / Generating Indicator
          if (_isThinking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF1F2C34),
              child: Row(
                children: const [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Color(0xFFEC4899), strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('DOLSYX AI is generating response...', style: TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ),
            ),

          // Message Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: const Color(0xFF1F2C34),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onSubmitted: (val) => _sendPrompt(val),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message or ask to generate an image...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFF2A3942),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF00A884),
                  radius: 22,
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    onPressed: () => _sendPrompt(_messageController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
