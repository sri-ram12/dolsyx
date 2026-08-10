import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chat_service.dart';
import '../services/dolsyx_ai_service.dart';
import '../theme/app_theme.dart';
import 'chat_room_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ChatService _chatService = ChatService();
  final DolsyxAiService _dolsyxAiService = DolsyxAiService();
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  bool _isAiThinking = false;

  void _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isLoading = true);
    final results = await _chatService.searchUsers(cleanQuery);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  void _askAiInSearch(String prompt) async {
    if (prompt.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _isAiThinking = true);

    final aiAnswer = await _dolsyxAiService.queryAiEngine(prompt);

    if (mounted) {
      setState(() => _isAiThinking = false);
      _showAiAnswerBottomSheet(prompt, aiAnswer);
    }
  }

  void _showAiAnswerBottomSheet(String question, String answer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final followUpController = TextEditingController();
        String currentAnswer = answer;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF3B82F6)],
                          ),
                        ),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'DOLSYX AI Answer',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: currentAnswer));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('AI Answer copied to clipboard!'), backgroundColor: Color(0xFF6366F1)),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '❓ "$question"',
                      style: const TextStyle(color: Color(0xFFEC4899), fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                    child: SingleChildScrollView(
                      child: Text(
                        currentAnswer,
                        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: followUpController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Ask a follow-up question...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: Color(0xFF6366F1)),
                        onPressed: () async {
                          final text = followUpController.text.trim();
                          if (text.isEmpty) return;
                          followUpController.clear();
                          setModalState(() {
                            currentAnswer = 'DOLSYX AI is thinking...';
                          });
                          final reply = await _dolsyxAiService.queryAiEngine(text);
                          setModalState(() {
                            currentAnswer = reply;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _startChat(String userId) async {
    setState(() => _isLoading = true);
    final chat = await _chatService.createDirectChat(userId);
    setState(() => _isLoading = false);

    if (chat != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            conversationId: chat.id,
            chatName: chat.name ?? 'Chat',
            avatarUrl: chat.avatarUrl,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start chat')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final queryText = _searchController.text.trim();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Ask DOLSYX AI or search...',
            border: InputBorder.none,
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: Container(
              padding: const EdgeInsets.all(10),
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF3B82F6)],
                ).createShader(bounds),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              ),
            ),
          ),
          onChanged: (val) {
            setState(() {});
            _performSearch(val);
          },
        ),
      ),
      body: Column(
        children: [
          if (_isAiThinking)
            const LinearProgressIndicator(color: Color(0xFFEC4899), backgroundColor: Color(0xFF1E293B)),

          // 🤖 Top Search Result: Meta AI Search Bar Chip
          if (queryText.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEC4899).withOpacity(0.4)),
              ),
              child: ListTile(
                onTap: () => _askAiInSearch(queryText),
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFF3B82F6)],
                    ),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                ),
                title: Row(
                  children: [
                    const Text('Ask DOLSYX AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEC4899).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Meta AI Style', style: TextStyle(color: Color(0xFFEC4899), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                subtitle: Text(
                  '"$queryText"',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 16),
              ),
            ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CONTACTS & USERS',
                style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          queryText.isEmpty ? 'Type to ask DOLSYX AI or search contacts' : 'No contacts found for "$queryText"',
                          style: const TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF1E293B),
                              backgroundImage: user['avatarUrl'] != null 
                                  ? (user['avatarUrl'].toString().startsWith('http') 
                                      ? NetworkImage(user['avatarUrl']) 
                                      : NetworkImage('https://dolsyx-app.onrender.com${user['avatarUrl']}')) 
                                  : null,
                              child: user['avatarUrl'] == null
                                  ? const Icon(Icons.person, color: Colors.white70)
                                  : null,
                            ),
                            title: Text(
                              user['username'] ?? 'Unknown User',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              user['email'] ?? '',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            onTap: () => _startChat(user['id']),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
