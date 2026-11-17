import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/contact_service.dart';
import '../services/chat_service.dart';
import '../services/event_bus.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import 'add_contact_screen.dart';
import 'chat_room_screen.dart';
import 'other_user_profile_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ChatService _chatService = ChatService();
  List<dynamic> _contacts = [];
  List<dynamic> _nonContacts = [];
  List<dynamic> _filtered = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL'; // ALL, CONTACTS, NON_CONTACTS, FAVOURITES, UNREAD
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _contactEventSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_applyFilterAndSearch);
    _contactEventSub = AppEventBus().onContactUpdated.listen((_) {
      if (mounted) _loadData(silent: true);
    });
  }

  @override
  void dispose() {
    _contactEventSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && _contacts.isEmpty) {
      setState(() => _isLoading = true);
    }
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
    final contacts = await ContactService.getContacts(token);

    // Fetch non-contacts from active chats
    List<dynamic> nonContactsList = [];
    try {
      final chats = await _chatService.getChats();
      final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ??
          Provider.of<AuthProvider>(context, listen: false).user?['_id'];
      final contactUserIds = contacts.map((c) => (c['contact']?['id'] ?? c['contact']?['_id'])?.toString()).toSet();

      for (final chat in chats) {
        if (!chat.isGroup && chat.participants != null) {
          for (final p in chat.participants!) {
            final u = p['user'];
            if (u != null) {
              final uid = (u['id'] ?? u['_id'])?.toString();
              if (uid != null && uid != currentUserId?.toString() && !contactUserIds.contains(uid)) {
                if (!nonContactsList.any((nc) => (nc['id'] ?? nc['_id'])?.toString() == uid)) {
                  nonContactsList.add({
                    'id': uid,
                    'contact': u,
                    'isNonContact': true,
                    'savedName': u['username'] ?? 'User',
                    'unreadCount': chat.unreadCount,
                  });
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _contacts = contacts;
        _nonContacts = nonContactsList;
        _isLoading = false;
      });
      _applyFilterAndSearch();
    }
  }

  void _applyFilterAndSearch() {
    final q = _searchController.text.trim().toLowerCase();

    List<dynamic> pool = [];
    if (_selectedFilter == 'ALL') {
      pool = [..._contacts, ..._nonContacts];
    } else if (_selectedFilter == 'CONTACTS') {
      pool = _contacts;
    } else if (_selectedFilter == 'NON_CONTACTS') {
      pool = _nonContacts;
    } else if (_selectedFilter == 'FAVOURITES') {
      pool = _contacts.where((c) => c['isFavorite'] == true).toList();
    } else if (_selectedFilter == 'UNREAD') {
      pool = [..._contacts, ..._nonContacts].where((c) => (c['unreadCount'] ?? 0) > 0).toList();
    }

    if (q.isEmpty) {
      setState(() => _filtered = pool);
    } else {
      setState(() {
        _filtered = pool.where((c) {
          final user = c['contact'] ?? c;
          final name = (c['savedName'] ?? user['username'] ?? '').toString().toLowerCase();
          final email = (user['email'] ?? '').toString().toLowerCase();
          return name.contains(q) || email.contains(q);
        }).toList();
      });
    }
  }

  Future<void> _startChat(String userId, String displayName, String? avatarUrl) async {
    setState(() => _isLoading = true);
    final chat = await _chatService.createDirectChat(userId);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (chat != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            conversationId: chat.id,
            chatName: displayName,
            avatarUrl: avatarUrl,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start chat')),
      );
    }
  }

  Future<void> _confirmDeleteContact(dynamic contactItem) async {
    final displayName = contactItem['savedName'] ?? contactItem['contact']?['username'] ?? 'this contact';
    final contactId = (contactItem['id'] ?? contactItem['contact']?['id'] ?? contactItem['contact']?['_id'] ?? '').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete $displayName?', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to remove $displayName from your saved contacts?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
      
      // ⚡ 0ms WhatsApp-grade instant optimistic update
      setState(() {
        _contacts.removeWhere((c) => (c['id']?.toString() == contactId || c['contact']?['id']?.toString() == contactId || c['contact']?['_id']?.toString() == contactId));
        _nonContacts.removeWhere((c) => (c['id']?.toString() == contactId || c['contact']?['id']?.toString() == contactId || c['contact']?['_id']?.toString() == contactId));
        _applyFilterAndSearch();
      });
      AppEventBus().emitContactUpdated();

      ContactService.deleteContact(token, contactId).then((ok) {
        if (!ok && mounted) {
          _loadData(silent: true);
        }
      }).catchError((_) {
        if (mounted) _loadData(silent: true);
      });
    }
  }

  Future<void> _toggleFavorite(String contactId, bool current) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
    setState(() {
      for (final c in _contacts) {
        if (c['id']?.toString() == contactId || c['contact']?['id']?.toString() == contactId) {
          c['isFavorite'] = !current;
        }
      }
      _applyFilterAndSearch();
    });
    AppEventBus().emitContactUpdated();
    ContactService.updateContact(token, contactId, isFavorite: !current).then((ok) {
      if (!ok && mounted) _loadData(silent: true);
    }).catchError((_) {
      if (mounted) _loadData(silent: true);
    });
  }

  Widget _buildFilterChip(String filterKey, String label, IconData icon) {
    final isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedFilter = filterKey);
        _applyFilterAndSearch();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.surfaceColor.withOpacity(0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Contacts', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Contact',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddContactScreen()));
              _loadData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search input
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
                prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
                filled: true,
                fillColor: AppTheme.surfaceColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Filter Pills (Pic 1 Style)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                _buildFilterChip('ALL', 'All', Icons.people_alt_outlined),
                _buildFilterChip('CONTACTS', 'Contacts', Icons.person_outline),
                _buildFilterChip('NON_CONTACTS', 'Non-contacts', Icons.person_off_outlined),
                _buildFilterChip('FAVOURITES', 'Favourites', Icons.star_outline),
                _buildFilterChip('UNREAD', 'Unread', Icons.mark_chat_unread_outlined),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Contact List
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.contacts_outlined, size: 64, color: AppTheme.textSecondary),
                            const SizedBox(height: 16),
                            Text('No contacts found', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              icon: const Icon(Icons.person_add),
                              label: const Text('Add Contact'),
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddContactScreen()));
                                _loadData();
                              },
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final c = _filtered[index];
                          final user = c['contact'] ?? c;
                          final displayName = c['savedName'] ?? user['username'] ?? 'User';
                          final isFav = c['isFavorite'] == true;
                          final isNonContact = c['isNonContact'] == true;
                          final userId = (user['id'] ?? user['_id'] ?? '').toString();

                          return ListTile(
                            leading: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OtherUserProfileScreen(user: user),
                                  ),
                                ).then((_) => _loadData());
                              },
                              child: ColorAvatar(
                                name: displayName,
                                avatarUrl: user['avatarUrl'],
                                radius: 22,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
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
                              user['email'] ?? user['username'] ?? '',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isNonContact)
                                  IconButton(
                                    icon: Icon(
                                      isFav ? Icons.star : Icons.star_border,
                                      color: isFav ? Colors.amber : AppTheme.textSecondary,
                                      size: 22,
                                    ),
                                    tooltip: isFav ? 'Remove Favourite' : 'Add to Favourite',
                                    onPressed: () => _toggleFavorite(c['id'].toString(), isFav),
                                  ),
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
                                  onSelected: (action) {
                                    if (action == 'view_info') {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => OtherUserProfileScreen(user: user),
                                        ),
                                      ).then((_) => _loadData());
                                    } else if (action == 'delete') {
                                      _confirmDeleteContact(c);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'view_info',
                                      child: Row(
                                        children: [
                                          Icon(Icons.info_outline, size: 18),
                                          SizedBox(width: 8),
                                          Text('View Info'),
                                        ],
                                      ),
                                    ),
                                    if (!isNonContact)
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                            SizedBox(width: 8),
                                            Text('Delete Contact', style: TextStyle(color: Colors.redAccent)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            onTap: () => _startChat(userId, displayName, user['avatarUrl']),
                            onLongPress: !isNonContact ? () => _confirmDeleteContact(c) : null,
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddContactScreen()));
          _loadData();
        },
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }
}
