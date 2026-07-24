import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/chat_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/color_avatar.dart';
import '../call_screen.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  final ChatService _chatService = ChatService();
  List<dynamic> _callLogs = [];
  bool _isLoading = true;
  StreamSubscription? _profileSubscription;

  @override
  void initState() {
    super.initState();
    _fetchCalls();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      _profileSubscription = authProvider.socketService.profileUpdates.stream.listen((event) {
        if (mounted) {
          _fetchCalls();
        }
      });
    });
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchCalls() async {
    final calls = await _chatService.getCallLogs();
    if (mounted) {
      setState(() {
        _callLogs = calls;
        _isLoading = false;
      });
    }
  }

  void _startCall(Map<String, dynamic> user, bool isAudioOnly, String conversationId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          conversationId: conversationId,
          remoteUserId: user['id'],
          remoteUserName: user['username'],
          remoteAvatarUrl: user['avatarUrl'],
          isAudioOnly: isAudioOnly,
          isIncoming: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }

    if (_callLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No recent calls.\nStart a call from any chat room!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'];

    return RefreshIndicator(
      onRefresh: _fetchCalls,
      child: ListView.builder(
        itemCount: _callLogs.length,
        itemBuilder: (context, index) {
          final log = _callLogs[index];
          final isCaller = log['senderId'] == currentUserId;
          
          // Get the other participant
          final participants = log['conversation']['participants'] as List<dynamic>;
          final otherParticipant = participants.firstWhere(
            (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
            orElse: () => null,
          );
          
          if (otherParticipant == null) return const SizedBox.shrink();
          
          final otherUser = otherParticipant['user'];
          final isVideo = log['mediaUrl'] == 'video';
          
          // Determine status
          final isMissed = log['content'] == 'missed' || log['content'] == 'declined';
          
          IconData iconData;
          Color iconColor;
          
          if (isMissed) {
            iconData = isCaller ? Icons.call_made : Icons.call_missed;
            iconColor = Colors.red;
          } else {
            iconData = isCaller ? Icons.call_made : Icons.call_received;
            iconColor = Colors.green;
          }

          return ListTile(
            leading: otherUser['avatarUrl'] != null
                ? CircleAvatar(
                    backgroundColor: AppTheme.surfaceColor,
                    backgroundImage: NetworkImage(otherUser['avatarUrl']),
                  )
                : ColorAvatar(
                    name: otherUser['username'] ?? '?',
                    radius: 20.0,
                  ),
            title: Text(
              otherUser['username'],
              style: TextStyle(
                color: isMissed ? Colors.red : AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Row(
              children: [
                Icon(iconData, size: 16, color: iconColor),
                const SizedBox(width: 4),
                Text(
                  DateFormat('MM/dd/yyyy, hh:mm a').format(DateTime.parse(log['createdAt']).toLocal()),
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.call, color: AppTheme.primaryColor),
                  onPressed: () => _startCall(otherUser, true, log['conversationId']),
                ),
                IconButton(
                  icon: Icon(Icons.videocam, color: AppTheme.primaryColor),
                  onPressed: () => _startCall(otherUser, false, log['conversationId']),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
