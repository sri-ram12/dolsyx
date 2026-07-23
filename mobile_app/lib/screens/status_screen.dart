import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/status.dart';
import '../services/status_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'status_view_screen.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final StatusService _statusService = StatusService();
  List<StatusModel> _statuses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStatuses();
  }

  Future<void> _fetchStatuses() async {
    setState(() => _isLoading = true);
    final statuses = await _statusService.getStatuses();
    if (mounted) {
      setState(() {
        _statuses = statuses;
        _isLoading = false;
      });
    }
  }

  Future<void> _addStatus() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      
      if (pickedFile != null) {
        setState(() => _isLoading = true);
        final uploadResponse = await _statusService.uploadStatusMedia(pickedFile.path);
        
        if (uploadResponse != null && uploadResponse['fileUrl'] != null) {
          final success = await _statusService.createStatus(
            uploadResponse['fileUrl'], 
            'IMAGE', 
            ''
          );
          if (success) {
            _fetchStatuses(); // Refresh list
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to post status')));
              setState(() => _isLoading = false);
            }
          }
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      print('Error adding status: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _viewStatus(StatusModel status) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatusViewScreen(status: status),
      ),
    ).then((_) => _fetchStatuses()); // Refresh on return in case viewed status is marked
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<AuthProvider>(context).user;
    final currentUserId = currentUser?['id'];

    // Group statuses by user
    final Map<String, List<StatusModel>> groupedStatuses = {};
    for (var status in _statuses) {
      if (!groupedStatuses.containsKey(status.userId)) {
        groupedStatuses[status.userId] = [];
      }
      groupedStatuses[status.userId]!.add(status);
    }

    final myStatuses = groupedStatuses[currentUserId] ?? [];
    groupedStatuses.remove(currentUserId);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.camera_alt, color: Colors.white),
        onPressed: () {
          _addStatus();
        },
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : RefreshIndicator(
              color: AppTheme.primaryColor,
              onRefresh: _fetchStatuses,
              child: ListView(
                children: [
                  // My Status Section
                  ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: AppTheme.surfaceColor,
                          backgroundImage: myStatuses.isNotEmpty
                              ? NetworkImage('https://dolsyx-app.onrender.com${myStatuses.last.mediaUrl}')
                              : null,
                          child: myStatuses.isEmpty
                              ? const Icon(Icons.person, color: AppTheme.textSecondary)
                              : null,
                        ),
                        if (myStatuses.isEmpty)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add, size: 14, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    title: const Text('My Status', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      myStatuses.isEmpty ? 'Tap to add status update' : '${myStatuses.length} updates',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    onTap: myStatuses.isEmpty
                        ? _addStatus
                        : () => _viewStatus(myStatuses.first), // A real app would iterate through them
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text('Recent updates', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                  ),
                  // Other Users' Statuses
                  if (groupedStatuses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No recent updates.', style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  ...groupedStatuses.entries.map((entry) {
                    final statuses = entry.value;
                    final latest = statuses.last;
                    final user = latest.user ?? {};
                    final avatarUrl = user['avatarUrl'];

                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primaryColor, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.surfaceColor,
                          backgroundImage: avatarUrl != null && avatarUrl.startsWith('http')
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: (avatarUrl == null || !avatarUrl.startsWith('http'))
                              ? const Icon(Icons.person, color: AppTheme.textSecondary)
                              : null,
                        ),
                      ),
                      title: Text(user['username'] ?? 'User', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                      subtitle: Text(_formatTime(latest.createdAt), style: const TextStyle(color: AppTheme.textSecondary)),
                      onTap: () => _viewStatus(statuses.first),
                    );
                  }).toList(),
                ],
              ),
            ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return 'Yesterday';
    }
  }
}
