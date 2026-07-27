import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/group_service.dart';
import '../services/contact_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final GroupService _groupService = GroupService();
  final ContactService _contactService = ContactService();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  
  List<dynamic> _contacts = [];
  List<dynamic> _filteredContacts = [];
  final List<String> _selectedUserIds = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }
  
  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    final token = Provider.of<AuthProvider>(context, listen: false).token ?? '';
    final contacts = await ContactService.getContacts(token);
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _filteredContacts = contacts;
        _isLoading = false;
      });
    }
  }
  
  void _filterContacts(String query) {
    setState(() {
      _searchQuery = query;
      _filteredContacts = _contacts.where((c) {
        final user = c['contact'];
        if (user == null) return false;
        final name = (c['savedName'] ?? user['username'] ?? '').toLowerCase();
        return name.contains(query.toLowerCase());
      }).toList();
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name and select at least one member')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final group = await _groupService.createGroup(name, _descController.text.trim(), null, _selectedUserIds);
    if (mounted) {
      setState(() => _isLoading = false);
      if (group != null) {
        Navigator.pop(context); // Go back to chat list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to create group')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group'),
        actions: [
          if (_isLoading)
            Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppTheme.primaryColor)),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _createGroup,
            )
        ],
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Group Name', hintText: 'Enter group name'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Description (Optional)'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Select Members', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              decoration: const InputDecoration(labelText: 'Search Contacts', prefixIcon: Icon(Icons.search)),
              onChanged: _filterContacts,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredContacts.length,
              itemBuilder: (context, index) {
                final contactObj = _filteredContacts[index];
                final user = contactObj['contact'];
                if (user == null) return const SizedBox.shrink();
                
                final userId = user['id'] ?? user['_id'];
                final isSelected = _selectedUserIds.contains(userId);
                final displayName = contactObj['savedName'] ?? user['username'] ?? 'Unknown';
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user['avatarUrl'] != null && user['avatarUrl'].startsWith('http')
                        ? NetworkImage(user['avatarUrl'])
                        : null,
                    child: user['avatarUrl'] == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(displayName, style: TextStyle(color: AppTheme.textPrimary)),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedUserIds.add(userId);
                        } else {
                          _selectedUserIds.remove(userId);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
