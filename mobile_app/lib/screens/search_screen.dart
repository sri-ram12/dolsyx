import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../services/dolsyx_ai_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import '../widgets/full_screen_image_view.dart';
import 'chat_room_screen.dart';
import 'locked_chats_screen.dart';

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
  List<Chat> _allChats = [];
  List<dynamic> _savedContacts = [];
  List<Map<String, dynamic>> _recentSearches = [];
  String _activeFilter = ''; // '', 'UNREAD', 'PHOTOS', 'VIDEOS', 'LINKS', 'GIFS', 'AUDIO', 'DOCS', 'POLLS', 'CONTACTS', 'NON_CONTACTS', 'FAVOURITES'
  String? _secretChatCode;

  bool _isLoading = false;
  bool _isAiThinking = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
    final prefs = await SharedPreferences.getInstance();

    // Load recent searches
    final savedRecentJson = prefs.getString('recent_searches_list');
    List<Map<String, dynamic>> loadedRecent = [];
    if (savedRecentJson != null) {
      try {
        final parsed = jsonDecode(savedRecentJson);
        if (parsed is List) {
          loadedRecent = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {}
    }

    // Load chats
    final chats = await _chatService.getChats();
    final contacts = await ContactService.getContacts(token);

    if (loadedRecent.isEmpty && chats.isNotEmpty) {
      // Default recent contacts from top chats
      for (final chat in chats.take(6)) {
        loadedRecent.add({
          'id': chat.id,
          'name': chat.name ?? 'Chat',
          'avatarUrl': chat.avatarUrl,
          'isGroup': chat.isGroup,
        });
      }
    }

    final secretCode = prefs.getString('secret_chat_code');

    if (mounted) {
      setState(() {
        _recentSearches = loadedRecent;
        _allChats = chats;
        _savedContacts = contacts;
        _secretChatCode = secretCode;
      });
    }
  }

  Future<void> _saveRecentSearch(String id, String name, String? avatarUrl, bool isGroup) async {
    final prefs = await SharedPreferences.getInstance();
    _recentSearches.removeWhere((item) => item['id'] == id || item['name'] == name);
    _recentSearches.insert(0, {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'isGroup': isGroup,
    });
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.sublist(0, 10);
    }
    await prefs.setString('recent_searches_list', jsonEncode(_recentSearches));
    if (mounted) setState(() {});
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches_list');
    setState(() => _recentSearches = []);
  }

  void _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty && _activeFilter.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isLoading = true);

    if (_activeFilter.isNotEmpty) {
      _filterByActivePill(cleanQuery);
      return;
    }

    final results = await _chatService.searchUsers(cleanQuery);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  void _filterByActivePill(String query) {
    final q = query.toLowerCase();
    List<dynamic> filtered = [];
    final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ??
        Provider.of<AuthProvider>(context, listen: false).user?['_id'];
    final contactIds = _savedContacts.map((c) => (c['contact']?['id'] ?? c['contact']?['_id'])?.toString()).toSet();

    switch (_activeFilter) {
      case 'UNREAD':
        filtered = _allChats.where((c) => c.unreadCount > 0 && (q.isEmpty || (c.name ?? '').toLowerCase().contains(q))).map((c) => {
          'type': 'chat',
          'chat': c,
          'id': c.id,
          'username': c.name ?? 'Chat',
          'avatarUrl': c.avatarUrl,
          'subtitle': '${c.unreadCount} unread message${c.unreadCount > 1 ? 's' : ''}',
        }).toList();
        break;

      case 'PHOTOS':
      case 'VIDEOS':
      case 'LINKS':
      case 'DOCS':
      case 'AUDIO':
      case 'POLLS':
      case 'GIFS':
        final targetType = _activeFilter == 'PHOTOS'
            ? 'IMAGE'
            : _activeFilter == 'VIDEOS'
                ? 'VIDEO'
                : _activeFilter == 'DOCS'
                    ? 'DOCUMENT'
                    : _activeFilter == 'AUDIO'
                        ? 'AUDIO'
                        : _activeFilter == 'POLLS'
                            ? 'POLL'
                            : _activeFilter;

        for (final chat in _allChats) {
          final lastMsg = chat.lastMessage;
          if (lastMsg != null) {
            final mType = (lastMsg['mediaType'] ?? '').toString().toUpperCase();
            final content = (lastMsg['content'] ?? '').toString();
            final isMatch = (_activeFilter == 'LINKS' && content.contains('http')) ||
                (_activeFilter == 'GIFS' && (mType == 'GIF' || content.contains('.gif'))) ||
                mType == targetType;

            if (isMatch && (q.isEmpty || (chat.name ?? '').toLowerCase().contains(q) || content.toLowerCase().contains(q))) {
              filtered.add({
                'type': 'chat',
                'chat': chat,
                'id': chat.id,
                'username': chat.name ?? 'Chat',
                'avatarUrl': chat.avatarUrl,
                'subtitle': content.isNotEmpty ? content : 'Shared ${_activeFilter.toLowerCase()}',
              });
            }
          }
        }
        break;

      case 'CONTACTS':
        filtered = _savedContacts.where((c) {
          final user = c['contact'] ?? {};
          final name = (c['savedName'] ?? user['username'] ?? '').toString().toLowerCase();
          final email = (user['email'] ?? '').toString().toLowerCase();
          return q.isEmpty || name.contains(q) || email.contains(q);
        }).map((c) {
          final user = c['contact'] ?? {};
          return {
            'id': user['id'] ?? user['_id'],
            'username': c['savedName'] ?? user['username'] ?? 'Contact',
            'email': user['email'] ?? '',
            'avatarUrl': user['avatarUrl'],
            'isContact': true,
          };
        }).toList();
        break;

      case 'NON_CONTACTS':
        final nonContacts = <String, Map<String, dynamic>>{};
        for (final chat in _allChats) {
          if (!chat.isGroup && chat.participants != null) {
            for (final p in chat.participants!) {
              final u = p['user'];
              if (u != null) {
                final uid = (u['id'] ?? u['_id'])?.toString();
                if (uid != null && uid != currentUserId?.toString() && !contactIds.contains(uid)) {
                  final name = (u['username'] ?? 'User').toString();
                  if (q.isEmpty || name.toLowerCase().contains(q)) {
                    nonContacts[uid] = {
                      'id': uid,
                      'username': name,
                      'email': u['email'] ?? '',
                      'avatarUrl': u['avatarUrl'],
                      'isNonContact': true,
                    };
                  }
                }
              }
            }
          }
        }
        filtered = nonContacts.values.toList();
        break;

      case 'FAVOURITES':
        filtered = _savedContacts.where((c) => c['isFavorite'] == true).where((c) {
          final user = c['contact'] ?? {};
          final name = (c['savedName'] ?? user['username'] ?? '').toString().toLowerCase();
          return q.isEmpty || name.contains(q);
        }).map((c) {
          final user = c['contact'] ?? {};
          return {
            'id': user['id'] ?? user['_id'],
            'username': c['savedName'] ?? user['username'] ?? 'Favorite',
            'email': user['email'] ?? '',
            'avatarUrl': user['avatarUrl'],
            'isFavorite': true,
          };
        }).toList();
        break;

      default:
        break;
    }

    if (mounted) {
      setState(() {
        _searchResults = filtered;
        _isLoading = false;
      });
    }
  }

  void _onFilterPillTapped(String filterKey) {
    setState(() {
      if (_activeFilter == filterKey) {
        _activeFilter = '';
      } else {
        _activeFilter = filterKey;
      }
    });
    _performSearch(_searchController.text);
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

  void _startChat(String userId, String displayName, String? avatarUrl) async {
    setState(() => _isLoading = true);
    final chat = await _chatService.createDirectChat(userId);
    setState(() => _isLoading = false);

    if (chat != null && mounted) {
      _saveRecentSearch(chat.id, displayName, avatarUrl, false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            conversationId: chat.id,
            chatName: displayName,
            avatarUrl: avatarUrl,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start chat')),
      );
    }
  }

  void _openExistingChat(Chat chat) {
    _saveRecentSearch(chat.id, chat.name ?? 'Chat', chat.avatarUrl, chat.isGroup);
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
  }

  Widget _buildFilterPill(String filterKey, String label, IconData icon) {
    final isSelected = _activeFilter == filterKey;
    return GestureDetector(
      onTap: () => _onFilterPillTapped(filterKey),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent searches',
                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              GestureDetector(
                onTap: _clearRecentSearches,
                child: const Text(
                  'Clear all',
                  style: TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 95,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _recentSearches.length,
            itemBuilder: (context, index) {
              final item = _recentSearches[index];
              final name = item['name'] ?? 'User';
              final avatarUrl = item['avatarUrl'];
              final id = item['id'];

              return GestureDetector(
                onTap: () {
                  final existing = _allChats.where((c) => c.id == id).toList();
                  if (existing.isNotEmpty) {
                    _openExistingChat(existing.first);
                  } else {
                    _startChat(id, name, avatarUrl);
                  }
                },
                child: Container(
                  width: 76,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      ColorAvatar(
                        name: name,
                        avatarUrl: avatarUrl,
                        radius: 26,
                        fontSize: 16,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
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
            hintText: 'Ask DOLSYX AI or Search',
            border: InputBorder.none,
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 16),
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
          // Filter Chips Row (Pic 1 Style)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFilterPill('UNREAD', 'Unread', Icons.mark_chat_unread_outlined),
                _buildFilterPill('PHOTOS', 'Photos', Icons.image_outlined),
                _buildFilterPill('VIDEOS', 'Videos', Icons.videocam_outlined),
                _buildFilterPill('LINKS', 'Links', Icons.link_rounded),
                _buildFilterPill('GIFS', 'GIFs', Icons.gif_box_outlined),
                _buildFilterPill('AUDIO', 'Audio', Icons.mic_none_outlined),
                _buildFilterPill('DOCS', 'Documents', Icons.description_outlined),
                _buildFilterPill('POLLS', 'Polls', Icons.poll_outlined),
                _buildFilterPill('CONTACTS', 'Contacts', Icons.person_outline),
                _buildFilterPill('NON_CONTACTS', 'Non-contacts', Icons.person_off_outlined),
                _buildFilterPill('FAVOURITES', 'Favourites', Icons.star_outline),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (_isAiThinking)
            const LinearProgressIndicator(color: Color(0xFFEC4899), backgroundColor: Color(0xFF1E293B)),

          // 🤖 Top Search Result: Meta AI Search Bar Chip
          if (queryText.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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

          // Recent Searches Section (Pic 1 Style)
          if (queryText.isEmpty && _activeFilter.isEmpty)
            _buildRecentSearches(),

          if (queryText.isNotEmpty || _activeFilter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _activeFilter.isNotEmpty ? 'RESULTS FOR $_activeFilter' : 'CONTACTS & USERS',
                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
                : Column(
                    children: [
                      if (_secretChatCode != null && _secretChatCode!.isNotEmpty && queryText.trim() == _secretChatCode!.trim())
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F2C34),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF00A884).withOpacity(0.5)),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF00A884),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                            ),
                            title: const Text('Locked chats', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: const Text('Secret code matched • Tap to open', style: TextStyle(color: Color(0xFF00A884), fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LockedChatsScreen(
                                    initialLockedChats: _allChats.where((c) => c.isLocked).toList(),
                                    onRefresh: _loadInitialData,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      Expanded(
                        child: (queryText.isNotEmpty || _activeFilter.isNotEmpty)
                            ? (_searchResults.isEmpty
                                ? (_secretChatCode != null && _secretChatCode!.isNotEmpty && queryText.trim() == _secretChatCode!.trim()
                                    ? const SizedBox.shrink()
                                    : Center(
                                        child: Text(
                                          'No results found for ${_activeFilter.isNotEmpty ? _activeFilter : '"$queryText"'}',
                                          style: const TextStyle(color: Colors.white38),
                                        )))
                                : ListView.builder(
                                    itemCount: _searchResults.length,
                                    itemBuilder: (context, index) {
                                      final item = _searchResults[index];
                                      final isChat = item['type'] == 'chat';
                                      final displayName = item['username'] ?? item['name'] ?? 'User';
                                      final avatarUrl = item['avatarUrl'];
                                      final subtitle = item['subtitle'] ?? item['email'] ?? '';
                                      final id = item['id'];
                                      final isNonContact = item['isNonContact'] == true;
                                      final isFavorite = item['isFavorite'] == true;

                                      return ListTile(
                                        leading: ColorAvatar(
                                          name: displayName,
                                          avatarUrl: avatarUrl,
                                          radius: 22,
                                        ),
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                displayName,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isFavorite)
                                              const Icon(Icons.star, color: Colors.amber, size: 16),
                                            if (isNonContact)
                                              Container(
                                                margin: const EdgeInsets.only(left: 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text('Non-contact', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                          ],
                                        ),
                                        subtitle: Text(
                                          subtitle,
                                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () {
                                          if (isChat && item['chat'] != null) {
                                            _openExistingChat(item['chat'] as Chat);
                                          } else {
                                            _startChat(id.toString(), displayName, avatarUrl);
                                          }
                                        },
                                      );
                                    },
                                  ))
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
