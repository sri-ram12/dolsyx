import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
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
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppTheme.primaryColor, const Color(0xFF8B5CF6), const Color(0xFFEC4899)],
                ),
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.backgroundColor,
                child: Icon(Icons.smart_toy, color: AppTheme.primaryColor, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DOLSYX AI',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Always active • Interactive AI',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
                            color: isUser ? AppTheme.bubbleSender : AppTheme.bubbleReceiver,
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
                                    children: [
                                      Icon(Icons.smart_toy, color: AppTheme.primaryColor, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        'DOLSYX AI 🤖',
                                        style: TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              Text(
                                msg['text'],
                                style: TextStyle(color: isUser ? Colors.white : AppTheme.textPrimary, fontSize: 15, height: 1.3),
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
                                          color: AppTheme.surfaceColor,
                                          child: Center(
                                            child: CircularProgressIndicator(color: AppTheme.primaryColor),
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        height: 180,
                                        color: Colors.black26,
                                        child: Icon(Icons.broken_image, color: AppTheme.textSecondary, size: 40),
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
                                    style: TextStyle(color: isUser ? Colors.white70 : AppTheme.textSecondary, fontSize: 10),
                                  ),
                                  if (isUser) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.done_all, color: Colors.white, size: 14),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Interactive Action Buttons
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
                                      backgroundColor: AppTheme.surfaceColor,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(
                                          color: isConfirm ? AppTheme.primaryColor : AppTheme.textSecondary.withOpacity(0.3),
                                        ),
                                      ),
                                    ),
                                    onPressed: () => _sendPrompt(label),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: isConfirm ? AppTheme.primaryColor : AppTheme.textPrimary,
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

          // Thinking Indicator
          if (_isThinking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.surfaceColor,
              child: Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: AppTheme.primaryColor, strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text('DOLSYX AI is generating response...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ),
            ),

          // Message Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: AppTheme.surfaceColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onSubmitted: (val) => _sendPrompt(val),
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Type a message or ask to generate an image...',
                      hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                      filled: true,
                      fillColor: AppTheme.backgroundColor,
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
                  backgroundColor: AppTheme.primaryColor,
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
