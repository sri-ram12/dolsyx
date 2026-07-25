import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/contact_service.dart';
import '../services/chat_service.dart';
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
  List<dynamic> _contacts = [];
  List<dynamic> _filtered = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
    final contacts = await ContactService.getContacts(token);
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _filtered = contacts;
        _isLoading = false;
      });
    }
  }

  Future<void> _startChat(String userId, String displayName, String? avatarUrl) async {
    setState(() => _isLoading = true);
    final chat = await ChatService().createDirectChat(userId);
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

  void _onSearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _contacts.where((c) {
        final name = (c['savedName'] ?? c['contact']['username'] ?? '').toLowerCase();
        final email = (c['contact']['email'] ?? '').toLowerCase();
        return name.contains(q) || email.contains(q);
      }).toList();
    });
  }

  Future<void> _deleteContact(String contactId) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
    final ok = await ContactService.deleteContact(token, contactId);
    if (ok) _loadContacts();
  }

  Future<void> _toggleFavorite(String contactId, bool current) async {
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
    await ContactService.updateContact(token, contactId, isFavorite: !current);
    _loadContacts();
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
              _loadContacts();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                hintStyle: TextStyle(color: AppTheme.textSecondary),
                prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
                filled: true,
                fillColor: AppTheme.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Contact list
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
                            Text('No contacts yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              icon: const Icon(Icons.person_add),
                              label: const Text('Add Contact'),
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddContactScreen()));
                                _loadContacts();
                              },
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadContacts,
                        child: ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final c = _filtered[index];
                            final user = c['contact'];
                            final displayName = c['savedName'] ?? user['username'];
                            final isFav = c['isFavorite'] == true;

                            return Dismissible(
                              key: Key(c['id']),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: Colors.red,
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              onDismissed: (_) => _deleteContact(c['id']),
                              child: ListTile(
                                leading: GestureDetector(
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => OtherUserProfileScreen(user: user),
                                    ));
                                  },
                                  child: ColorAvatar(
                                    name: displayName,
                                    avatarUrl: user['avatarUrl'],
                                    radius: 22,
                                  ),
                                ),
                                title: Text(displayName, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                                subtitle: Text(user['email'] ?? user['username'] ?? '', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _toggleFavorite(c['id'], isFav),
                                      child: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : AppTheme.textSecondary, size: 22),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
                                  ],
                                ),
                                onTap: () => _startChat(user['id'], displayName, user['avatarUrl']),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddContactScreen()));
          _loadContacts();
        },
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }
}
