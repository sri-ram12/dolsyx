import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/contact_service.dart';
import '../widgets/theme_check_badge.dart';

class StatusPrivacyScreen extends StatefulWidget {
  const StatusPrivacyScreen({super.key});

  @override
  State<StatusPrivacyScreen> createState() => _StatusPrivacyScreenState();
}

class _StatusPrivacyScreenState extends State<StatusPrivacyScreen> {
  String _privacyType = 'MY_CONTACTS'; // MY_CONTACTS, EXCEPT, ONLY_SHARE
  List<String> _selectedUserIds = [];
  List<dynamic> _contacts = [];
  List<dynamic> _filteredContacts = [];
  bool _isLoadingContacts = true;
  bool _isSaving = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _fetchContacts();
  }

  void _loadCurrentSettings() {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      setState(() {
        _privacyType = user['statusPrivacyType'] ?? 'MY_CONTACTS';
        final rawList = user['statusPrivacyList'];
        if (rawList != null) {
          try {
            final parsed = jsonDecode(rawList.toString());
            if (parsed is List) {
              _selectedUserIds = List<String>.from(parsed.map((e) => e.toString()));
            }
          } catch (_) {}
        }
      });
    }
  }

  Future<void> _fetchContacts() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    try {
      final list = await ContactService.getContacts(token);
      if (mounted) {
        setState(() {
          _contacts = list;
          _filteredContacts = list;
          _isLoadingContacts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingContacts = false);
      }
    }
  }

  void _filterContacts(String query) {
    if (query.trim().isEmpty) {
      setState(() => _filteredContacts = _contacts);
      return;
    }
    final q = query.trim().toLowerCase();
    setState(() {
      _filteredContacts = _contacts.where((c) {
        final contactObj = c['contact'] ?? {};
        final username = (contactObj['username'] ?? c['savedName'] ?? '').toString().toLowerCase();
        final email = (contactObj['email'] ?? c['savedEmail'] ?? '').toString().toLowerCase();
        return username.contains(q) || email.contains(q);
      }).toList();
    });
  }

  Future<void> _savePrivacySettings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    if (token == null) return;

    setState(() => _isSaving = true);
    try {
      final payload = {
        'statusPrivacyType': _privacyType,
        'statusPrivacyList': jsonEncode(_selectedUserIds),
      };

      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/auth/profile'),
        headers: ApiService.authHeaders(token),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        authProvider.updateUser(data['user']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Status privacy settings saved'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
        Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save status privacy settings')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error saving settings')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status Privacy'),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, color: Colors.cyanAccent),
            onPressed: _isSaving ? null : _savePrivacySettings,
          ),
        ],
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          // Option Cards
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.surfaceColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Who can see my status updates',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                RadioListTile<String>(
                  title: Text('My Contacts', style: TextStyle(color: AppTheme.textPrimary)),
                  subtitle: Text(
                    'Visible to all saved email contacts',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  value: 'MY_CONTACTS',
                  groupValue: _privacyType,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (val) {
                    if (val != null) setState(() => _privacyType = val);
                  },
                ),
                RadioListTile<String>(
                  title: Text('My Contacts Except...', style: TextStyle(color: AppTheme.textPrimary)),
                  subtitle: Text(
                    _privacyType == 'EXCEPT' && _selectedUserIds.isNotEmpty
                        ? '${_selectedUserIds.length} contact(s) excluded'
                        : 'Exclude specific email contacts from viewing',
                    style: TextStyle(
                      color: _privacyType == 'EXCEPT' && _selectedUserIds.isNotEmpty
                          ? Colors.redAccent
                          : AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  value: 'EXCEPT',
                  groupValue: _privacyType,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (val) {
                    if (val != null) setState(() => _privacyType = val);
                  },
                ),
                RadioListTile<String>(
                  title: Text('Only Share With...', style: TextStyle(color: AppTheme.textPrimary)),
                  subtitle: Text(
                    _privacyType == 'ONLY_SHARE' && _selectedUserIds.isNotEmpty
                        ? '${_selectedUserIds.length} contact(s) selected'
                        : 'Only visible to explicitly selected email contacts',
                    style: TextStyle(
                      color: _privacyType == 'ONLY_SHARE' && _selectedUserIds.isNotEmpty
                          ? Colors.greenAccent
                          : AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  value: 'ONLY_SHARE',
                  groupValue: _privacyType,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (val) {
                    if (val != null) setState(() => _privacyType = val);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.grey),

          // Contact Selection Section (Shown when EXCEPT or ONLY_SHARE is active)
          if (_privacyType != 'MY_CONTACTS') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TextField(
                controller: _searchController,
                onChanged: _filterContacts,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search contacts by username or email...',
                  hintStyle: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.surfaceColor,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _privacyType == 'EXCEPT' ? 'Select Contacts to Exclude' : 'Select Contacts to Share With',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_selectedUserIds.length} selected',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoadingContacts
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredContacts.isEmpty
                      ? Center(
                          child: Text(
                            'No DOLSYX contacts found',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredContacts.length,
                          itemBuilder: (ctx, idx) {
                            final c = _filteredContacts[idx];
                            final contactObj = c['contact'] ?? {};
                            final targetUserId = (contactObj['id'] ?? c['contactId'])?.toString() ?? '';
                            final username = (contactObj['username'] ?? c['savedName'] ?? 'Contact').toString();
                            final email = (contactObj['email'] ?? c['savedEmail'] ?? '').toString();
                            final avatarUrl = contactObj['avatarUrl']?.toString();

                            final bool isSelected = _selectedUserIds.contains(targetUserId);

                            return ListTile(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedUserIds.remove(targetUserId);
                                  } else {
                                    _selectedUserIds.add(targetUserId);
                                  }
                                });
                              },
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
                                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                    ? NetworkImage(ApiService.getMediaUrl(avatarUrl))
                                    : null,
                                child: avatarUrl == null || avatarUrl.isEmpty
                                    ? Text(
                                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                                        style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              title: Text(username, style: TextStyle(color: AppTheme.textPrimary, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600)),
                              subtitle: Text(email, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              trailing: ThemeCheckBadge(
                                isSelected: isSelected,
                                size: 22,
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedUserIds.remove(targetUserId);
                                    } else {
                                      _selectedUserIds.add(targetUserId);
                                    }
                                  });
                                },
                              ),
                            );
                          },
                        ),
            ),
          ] else
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary.withOpacity(0.4)),
                    const SizedBox(height: 16),
                    Text(
                      'Your status will be visible to all your saved DOLSYX email contacts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.save, color: Colors.white),
        label: const Text('Save Privacy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: _isSaving ? null : _savePrivacySettings,
      ),
    );
  }
}
