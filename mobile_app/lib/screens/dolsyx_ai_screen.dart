import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/ai_service.dart';

class DolsyxAiScreen extends StatefulWidget {
  const DolsyxAiScreen({super.key});

  @override
  State<DolsyxAiScreen> createState() => _DolsyxAiScreenState();
}

class _DolsyxAiScreenState extends State<DolsyxAiScreen> {
  final AIService _aiService = AIService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'ai',
      'text': 'Hi! I am **DOLSYX AI**, your personal AI assistant. How can I help you today?',
      'time': DateTime.now(),
    }
  ];
  bool _isTyping = false;

  final List<String> _quickPrompts = [
    '💡 Brainstorm ideas',
    '📧 Draft an email',
    '💻 Write code',
    '📋 Summarize text',
  ];

  Future<void> _sendPrompt(String promptText) async {
    final prompt = promptText.trim();
    if (prompt.isEmpty || _isTyping) return;

    _messageController.clear();
    setState(() {
      _messages.add({
        'sender': 'user',
        'text': prompt,
        'time': DateTime.now(),
      });
      _isTyping = true;
    });
    _scrollToBottom();

    final aiReply = await _aiService.askAI(prompt);

    if (mounted) {
      setState(() {
        _isTyping = false;
        _messages.add({
          'sender': 'ai',
          'text': aiReply,
          'time': DateTime.now(),
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
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
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
                backgroundColor: Color(0xFF0F172A),
                child: Icon(Icons.auto_awesome, color: Color(0xFFEC4899), size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'DOLSYX AI',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Always active • Meta AI style',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Quick Prompt Chips
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _quickPrompts.length,
              itemBuilder: (context, index) {
                final prompt = _quickPrompts[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Colors.white12),
                    label: Text(prompt, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    onPressed: () => _sendPrompt(prompt.substring(2).trim()),
                  ),
                );
              },
            ),
          ),
          const Divider(color: Colors.white12, height: 1),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['sender'] == 'user';

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF4338CA) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      border: isUser ? null : Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isUser)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.auto_awesome, color: Color(0xFFEC4899), size: 14),
                              SizedBox(width: 4),
                              Text('DOLSYX AI', style: TextStyle(color: Color(0xFFEC4899), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        if (!isUser) const SizedBox(height: 4),
                        Text(
                          msg['text'],
                          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            DateFormat('hh:mm a').format(msg['time']),
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Typing Indicator
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: const [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Color(0xFFEC4899), strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('DOLSYX AI is thinking...', style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ),
            ),

          // Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onSubmitted: (val) => _sendPrompt(val),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ask DOLSYX AI anything...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
