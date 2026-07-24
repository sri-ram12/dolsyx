import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/status.dart';
import '../services/status_service.dart';
import '../services/socket_service.dart';
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
  List<UserStatusGroup> _groups = [];
  bool _isLoading = true;
  StreamSubscription? _statusSubscription;
  bool _showMuted = false;

  @override
  void initState() {
    super.initState();
    _fetchStatuses();
    
    // Listen to real-time status updates
    final socketService = Provider.of<SocketService>(context, listen: false);
    _statusSubscription = socketService.onStatusStream.listen((event) {
      if (mounted) _fetchStatuses();
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchStatuses() async {
    final groups = await _statusService.getStatuses();
    if (mounted) {
      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    }
  }

  Future<void> _addStatus(String type) async {
    if (type == 'TEXT') {
      // Show dialog to add text status
      _showTextStatusDialog();
      return;
    }

    try {
      final picker = ImagePicker();
      final pickedFile = type == 'IMAGE' 
          ? await picker.pickImage(source: ImageSource.gallery, imageQuality: 70)
          : await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 90));
      
      if (pickedFile != null) {
        setState(() => _isLoading = true);
        final uploadResponse = await _statusService.uploadStatusMedia(pickedFile.path);
        
        if (uploadResponse != null && uploadResponse['fileUrl'] != null) {
          final success = await _statusService.createStatus(
            uploadResponse['fileUrl'], 
            type, 
            ''
          );
          if (success) {
            _fetchStatuses();
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

  void _showTextStatusDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Add Text Status', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: 'Type a status...', hintStyle: TextStyle(color: AppTheme.textSecondary)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context);
                setState(() => _isLoading = true);
                final success = await _statusService.createStatus('', 'TEXT', controller.text);
                if (success) _fetchStatuses();
                else setState(() => _isLoading = false);
              }
            },
            child: Text('Post'),
          ),
        ],
      ),
    );
  }

  void _viewStatus(UserStatusGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatusViewScreen(group: group),
      ),
    ).then((_) => _fetchStatuses());
  }

  void _toggleMute(UserStatusGroup group) async {
    final isMuted = group.isMuted;
    final contactId = group.user['id'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(isMuted ? 'Unmute ${group.user['username']}?' : 'Mute ${group.user['username']}?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          isMuted ? 'New status updates from ${group.user['username']} will appear under recent updates.' 
                  : 'New status updates from ${group.user['username']} won\'t appear under recent updates anymore.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              bool success = isMuted ? await _statusService.unmuteStatus(contactId) : await _statusService.muteStatus(contactId);
              if (success) _fetchStatuses();
              else setState(() => _isLoading = false);
            },
            child: Text(isMuted ? 'Unmute' : 'Mute'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<AuthProvider>(context).user;
    final currentUserId = currentUser?['id'];

    UserStatusGroup? myGroup;
    List<UserStatusGroup> recentUpdates = [];
    List<UserStatusGroup> viewedUpdates = [];
    List<UserStatusGroup> mutedUpdates = [];

    for (var group in _groups) {
      if (group.user['id'] == currentUserId) {
        myGroup = group;
      } else if (group.isMuted) {
        mutedUpdates.add(group);
      } else if (group.hasUnread) {
        recentUpdates.add(group);
      } else {
        viewedUpdates.add(group);
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "textFAB",
            mini: true,
            backgroundColor: AppTheme.surfaceColor,
            child: Icon(Icons.edit, color: AppTheme.primaryColor),
            onPressed: () => _addStatus('TEXT'),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "cameraFAB",
            backgroundColor: AppTheme.primaryColor,
            child: Icon(Icons.camera_alt, color: Colors.white),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: AppTheme.surfaceColor,
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(Icons.image, color: AppTheme.primaryColor),
                      title: Text('Photo', style: TextStyle(color: AppTheme.textPrimary)),
                      onTap: () { Navigator.pop(context); _addStatus('IMAGE'); },
                    ),
                    ListTile(
                      leading: Icon(Icons.videocam, color: AppTheme.primaryColor),
                      title: Text('Video', style: TextStyle(color: AppTheme.textPrimary)),
                      onTap: () { Navigator.pop(context); _addStatus('VIDEO'); },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : RefreshIndicator(
              color: AppTheme.primaryColor,
              onRefresh: _fetchStatuses,
              child: ListView(
                children: [
                  // My Status
                  ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: AppTheme.surfaceColor,
                          backgroundImage: (myGroup != null && myGroup.statuses.isNotEmpty && myGroup.statuses.last.mediaUrl.isNotEmpty)
                              ? NetworkImage(myGroup.statuses.last.mediaUrl.startsWith('http') ? myGroup.statuses.last.mediaUrl : 'https://dolsyx-app.onrender.com${myGroup.statuses.last.mediaUrl}')
                              : null,
                          child: (myGroup == null || myGroup.statuses.isEmpty || myGroup.statuses.last.mediaUrl.isEmpty)
                              ? Icon(Icons.person, color: AppTheme.textSecondary)
                              : null,
                        ),
                        if (myGroup == null || myGroup.statuses.isEmpty)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
                              child: Icon(Icons.add, size: 14, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    title: Text('My Status', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      (myGroup == null || myGroup.statuses.isEmpty) ? 'Tap to add status update' : _formatTime(myGroup.statuses.last.createdAt),
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    onTap: () {
                      if (myGroup == null || myGroup.statuses.isEmpty) {
                        _addStatus('IMAGE');
                      } else {
                        _viewStatus(myGroup);
                      }
                    },
                  ),
                  
                  if (recentUpdates.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text('Recent updates', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                    ),
                  ...recentUpdates.map((group) => _buildStatusTile(group)),
                  
                  if (viewedUpdates.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text('Viewed updates', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                    ),
                  ...viewedUpdates.map((group) => _buildStatusTile(group)),

                  if (mutedUpdates.isNotEmpty) ...[
                    InkWell(
                      onTap: () => setState(() => _showMuted = !_showMuted),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Muted updates', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                            Icon(_showMuted ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppTheme.textSecondary),
                          ],
                        ),
                      ),
                    ),
                    if (_showMuted)
                      ...mutedUpdates.map((group) => _buildStatusTile(group)),
                  ],
                  
                  const SizedBox(height: 80), // Padding for FAB
                ],
              ),
            ),
    );
  }

  Widget _buildStatusTile(UserStatusGroup group) {
    final latest = group.statuses.last;
    final user = group.user;
    final avatarUrl = user['avatarUrl'];
    
    // Status rings: green for unread, grey for read. If muted, always grey.
    final borderColor = group.isMuted ? Colors.grey : (group.hasUnread ? AppTheme.primaryColor : Colors.grey);

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 2),
        ),
        child: CircleAvatar(
          radius: 24,
          backgroundColor: AppTheme.surfaceColor,
          backgroundImage: avatarUrl != null && avatarUrl.startsWith('http')
              ? NetworkImage(avatarUrl)
              : null,
          child: (avatarUrl == null || !avatarUrl.startsWith('http'))
              ? Icon(Icons.person, color: AppTheme.textSecondary)
              : null,
        ),
      ),
      title: Text(user['username'] ?? 'User', style: TextStyle(color: group.isMuted ? AppTheme.textSecondary : AppTheme.textPrimary, fontWeight: FontWeight.bold)),
      subtitle: Text(_formatTime(latest.createdAt), style: TextStyle(color: AppTheme.textSecondary)),
      onTap: () => _viewStatus(group),
      onLongPress: () => _toggleMute(group),
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
