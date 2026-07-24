import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import 'chat_room_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;

  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isLoading = true);
    final results = await _chatService.searchUsers(query);
    setState(() {
      _searchResults = results;
      _isLoading = false;
    });
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
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search for users...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: AppTheme.textSecondary),
          ),
          onChanged: _performSearch,
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _searchResults.isEmpty
              ? Center(
                  child: Text(
                    'Search for a username to start chatting',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.surfaceColor,
                        backgroundImage: user['avatarUrl'] != null 
                            ? (user['avatarUrl'].toString().startsWith('http') 
                                ? NetworkImage(user['avatarUrl']) 
                                : NetworkImage('https://dolsyx-app.onrender.com${user['avatarUrl']}')) 
                            : null,
                        child: user['avatarUrl'] == null
                            ? Icon(Icons.person, color: AppTheme.textSecondary)
                            : null,
                      ),
                      title: Text(
                        user['username'] ?? 'Unknown User',
                        style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        user['email'] ?? '',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      onTap: () => _startChat(user['id']),
                    );
                  },
                ),
    );
  }
}
