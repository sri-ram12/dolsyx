import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/dolsyx_ai_service.dart';
import '../services/chat_service.dart';
import '../models/chat.dart';
import '../widgets/full_screen_image_view.dart';
import 'ai_profile_screen.dart';
import 'chat_room_screen.dart';

class DolsyxAiScreen extends StatefulWidget {
  final String? initialPrompt;
  const DolsyxAiScreen({super.key, this.initialPrompt});

  @override
  State<DolsyxAiScreen> createState() => _DolsyxAiScreenState();
}

class _DolsyxAiScreenState extends State<DolsyxAiScreen> {
  final DolsyxAiService _aiService = DolsyxAiService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isThinking = false;
  String _userName = 'there';
  String _activePreset = 'Photorealistic';

  final List<String> _presets = ['Photorealistic', 'Cinematic', 'Anime', '3D', 'Cyberpunk', 'Minimalist'];

  final List<String> _quickPrompts = [
    'I want to write a message to a classmate',
    'I want to write a cover letter',
    'I want to write a message to a friend',
    'I need help finding a job',
    'I want to write a message to a coworker',
    'I want to plan an event',
    'I need help with my math homework',
    'I want to plan a wedding',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserName();
    if (widget.initialPrompt != null && widget.initialPrompt!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendPrompt(widget.initialPrompt!.trim());
      });
    }
  }

  Future<void> _loadUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUserStr = prefs.getString('cached_user_data');
      if (cachedUserStr != null) {
        final data = jsonDecode(cachedUserStr);
        final name = data['username'] ?? data['name'] ?? data['displayName'];
        if (name != null && name.toString().trim().isNotEmpty) {
          setState(() {
            _userName = name.toString().trim();
          });
        }
      }
    } catch (_) {}
  }

  void _shareToChat(String text, {String? imageUrl}) async {
    final chatService = ChatService();
    final chats = await chatService.getChats();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.send_rounded, color: Color(0xFF8B5CF6), size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'Send to DOLSYX Chat',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              if (chats.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No active chats found.', style: TextStyle(color: Colors.white54)),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: chats.length,
                    itemBuilder: (context, idx) {
                      final c = chats[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1E293B),
                          backgroundImage: c.avatarUrl != null && c.avatarUrl!.isNotEmpty
                              ? NetworkImage(c.avatarUrl!)
                              : null,
                          child: c.avatarUrl == null || c.avatarUrl!.isEmpty
                              ? Text(
                                  (c.name ?? 'C').substring(0, 1).toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        title: Text(c.name ?? 'Chat', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text(c.isGroup ? 'Group' : 'Direct message', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatRoomScreen(
                                conversationId: c.id,
                                chatName: c.name ?? 'Chat',
                                avatarUrl: c.avatarUrl,
                                initialText: imageUrl != null && imageUrl.isNotEmpty ? '$text\n$imageUrl' : text,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendPrompt(String promptText, {String? parentImageId}) async {
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

    final rawResponse = await _aiService.queryAiEngine(prompt, preset: _activePreset);

    if (mounted) {
      String replyText = rawResponse;
      String messageType = 'text';
      List<dynamic> options = [];
      String? imageUrl;

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
        title: GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AiProfileScreen()));
          },
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF3B82F6)],
                  ),
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.backgroundColor,
                  child: const Icon(Icons.blur_on_rounded, color: Color(0xFF8B5CF6), size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Meta AI',
                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, color: Color(0xFF3B82F6), size: 16),
                    ],
                  ),
                  Text(
                    'Tap for profile & settings',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // If no messages yet, show Meta AI Welcome Screen with dynamic logged-in user name
          if (_messages.isEmpty)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Text(
                      'Hi, $_userName',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Column(
                      children: _quickPrompts.map((prompt) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => _sendPrompt(prompt),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.assignment_outlined, color: AppTheme.textPrimary, size: 20),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      prompt,
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            )
          else
            // Messages Chat List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg['sender'] == 'user';
                  final imageUrl = msg['imageUrl'] as String?;

                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
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
                                if (imageUrl != null && imageUrl.isNotEmpty) ...[
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
                                        width: double.infinity,
                                        height: 340,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            height: 340,
                                            color: AppTheme.surfaceColor,
                                            child: Center(
                                              child: CircularProgressIndicator(color: AppTheme.primaryColor),
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) => Container(
                                          height: 220,
                                          color: Colors.black26,
                                          child: Icon(Icons.broken_image, color: AppTheme.textSecondary, size: 40),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                Text(
                                  msg['text'],
                                  style: TextStyle(color: isUser ? Colors.white : AppTheme.textPrimary, fontSize: 15, height: 1.4),
                                ),

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
                          if (!isUser) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: msg['text'] ?? ''));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Copied to clipboard!'), duration: Duration(seconds: 1)),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceColor,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.copy_rounded, size: 12, color: AppTheme.textSecondary),
                                        const SizedBox(width: 4),
                                        Text('Copy', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => _shareToChat(msg['text'] ?? '', imageUrl: imageUrl),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B5CF6).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.forward_to_inbox_rounded, size: 13, color: Color(0xFFC084FC)),
                                        SizedBox(width: 4),
                                        Text('Send to Chat', style: TextStyle(fontSize: 11, color: Color(0xFFC084FC), fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
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
                  Text('Meta AI is typing...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ),
            ),

          // Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: AppTheme.surfaceColor,
            child: Row(
              children: [
                Icon(Icons.sentiment_satisfied_alt, color: AppTheme.textSecondary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onSubmitted: (val) => _sendPrompt(val),
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Message',
                      hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Icon(Icons.attach_file, color: AppTheme.textSecondary, size: 22),
                const SizedBox(width: 12),
                Icon(Icons.camera_alt_outlined, color: AppTheme.textSecondary, size: 22),
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: AppTheme.primaryColor,
                  radius: 22,
                  child: IconButton(
                    icon: const Icon(Icons.mic, color: Colors.white, size: 20),
                    onPressed: () {
                      if (_messageController.text.trim().isNotEmpty) {
                        _sendPrompt(_messageController.text);
                      }
                    },
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
