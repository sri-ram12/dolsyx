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
  final Set<String> _selectedCallIds = {};

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

  Future<void> _deleteSelectedCalls(bool forEveryone) async {
    for (String callId in _selectedCallIds) {
      await _chatService.deleteMessage(callId, forEveryone);
    }
    setState(() {
      _selectedCallIds.clear();
    });
    _fetchCalls();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'];

    Widget content;
    if (_isLoading) {
      content = Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    } else if (_callLogs.isEmpty) {
      content = Center(
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
    } else {
      content = RefreshIndicator(
        onRefresh: _fetchCalls,
        child: ListView.builder(
          itemCount: _callLogs.length,
          itemBuilder: (context, index) {
            final log = _callLogs[index];
            final String logId = log['id'];
            final isSelected = _selectedCallIds.contains(logId);
            final isCaller = log['senderId'] == currentUserId;
            
            // Get the other participant
            final participants = log['conversation']['participants'] as List<dynamic>;
            final otherParticipant = participants.firstWhere(
              (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
              orElse: () => null,
            );
            
            if (otherParticipant == null) return const SizedBox.shrink();
            
            final otherUser = otherParticipant['user'];
            
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

            return Container(
              color: isSelected ? AppTheme.primaryColor.withAlpha(50) : Colors.transparent,
              child: ListTile(
                onLongPress: () {
                  setState(() {
                    if (isSelected) {
                      _selectedCallIds.remove(logId);
                    } else {
                      _selectedCallIds.add(logId);
                    }
                  });
                },
                onTap: () {
                  if (_selectedCallIds.isNotEmpty) {
                    setState(() {
                      if (isSelected) {
                        _selectedCallIds.remove(logId);
                      } else {
                        _selectedCallIds.add(logId);
                      }
                    });
                  }
                },
                leading: otherUser['avatarUrl'] != null
                    ? CircleAvatar(
                        backgroundColor: AppTheme.surfaceColor,
                        backgroundImage: otherUser['avatarUrl'].toString().startsWith('http')
                            ? NetworkImage(otherUser['avatarUrl'])
                            : NetworkImage('https://dolsyx-app.onrender.com${otherUser['avatarUrl']}'),
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
                trailing: _selectedCallIds.isEmpty
                    ? Row(
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
                      )
                    : null,
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _selectedCallIds.isNotEmpty
          ? AppBar(
              backgroundColor: AppTheme.surfaceColor,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectedCallIds.clear();
                  });
                },
              ),
              title: Text('${_selectedCallIds.length} Selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete for Me',
                  onPressed: () {
                    _deleteSelectedCalls(false);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  tooltip: 'Delete for Everyone',
                  onPressed: () {
                    _deleteSelectedCalls(true);
                  },
                ),
              ],
            )
          : null,
      body: content,
    );
  }
}
