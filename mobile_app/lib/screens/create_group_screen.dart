import 'package:flutter/material.dart';
import '../services/group_service.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final GroupService _groupService = GroupService();
  final ChatService _chatService = ChatService();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  
  List<dynamic> _users = [];
  final List<String> _selectedUserIds = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchUsers('');
  }

  Future<void> _searchUsers(String query) async {
    final users = await _chatService.searchUsers(query);
    if (mounted) {
      setState(() {
        _users = users;
      });
    }
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
            const Padding(
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
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Select Members', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              decoration: const InputDecoration(labelText: 'Search Users', prefixIcon: Icon(Icons.search)),
              onChanged: _searchUsers,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                final isSelected = _selectedUserIds.contains(user['_id']);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user['avatarUrl'] != null && user['avatarUrl'].startsWith('http')
                        ? NetworkImage(user['avatarUrl'])
                        : null,
                    child: user['avatarUrl'] == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(user['username'], style: const TextStyle(color: AppTheme.textPrimary)),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedUserIds.add(user['_id']);
                        } else {
                          _selectedUserIds.remove(user['_id']);
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
