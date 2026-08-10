import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/chat_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/color_avatar.dart';
import '../call_screen.dart';
import '../call_info_screen.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  static VoidCallback? clearAllCallsGlobal;

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
    CallsTab.clearAllCallsGlobal = _confirmClearAll;
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
    if (CallsTab.clearAllCallsGlobal == _confirmClearAll) {
      CallsTab.clearAllCallsGlobal = null;
    }
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
    if (CallScreen.isCallActiveNotifier.value) {
      final state = CallScreen.activeCallState;
      if (state != null && state.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: 'CallScreen'),
            builder: (_) => CallScreen(
              conversationId: CallScreen.activeConversationId ?? conversationId,
              remoteUserId: state.widget.remoteUserId,
              remoteUserName: state.widget.remoteUserName,
              remoteAvatarUrl: state.widget.remoteAvatarUrl,
              isAudioOnly: state.widget.isAudioOnly,
              isIncoming: false,
            ),
          ),
        );
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'CallScreen'),
        builder: (_) => CallScreen(
          conversationId: conversationId,
          remoteUserId: user['id'] ?? user['_id'],
          remoteUserName: user['username'] ?? 'User',
          remoteAvatarUrl: user['avatarUrl'],
          isAudioOnly: isAudioOnly,
          isIncoming: false,
        ),
      ),
    );
  }

  Future<void> _deleteSingleCall(String callId) async {
    final backup = List<dynamic>.from(_callLogs);
    setState(() {
      _callLogs.removeWhere((log) => log['id'] == callId);
    });
    final success = await _chatService.deleteCallLog(callId);
    if (!success && mounted) {
      setState(() => _callLogs = backup);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to delete call log. Check connection.'),
          action: SnackBarAction(label: 'Retry', onPressed: () => _deleteSingleCall(callId)),
        ),
      );
    }
  }

  Future<void> _deleteSelectedCalls() async {
    final ids = List<String>.from(_selectedCallIds);
    setState(() {
      _callLogs.removeWhere((log) => ids.contains(log['id']));
      _selectedCallIds.clear();
    });
    final success = await _chatService.deleteBulkCallLogs(ids);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete selected call logs')),
      );
      _fetchCalls();
    }
  }

  Future<void> _clearAllCalls() async {
    setState(() {
      _callLogs.clear();
      _selectedCallIds.clear();
    });
    final success = await _chatService.clearCallLogs();
    if (!success && mounted) {
      _fetchCalls();
    }
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Clear all call logs?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('This will delete all call logs from your history.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _clearAllCalls();
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatCallDuration(dynamic logContent, dynamic rawDuration) {
    if (logContent == 'missed' || logContent == 'declined') {
      return 'Missed';
    }
    int durationSec = 0;
    final contentStr = logContent?.toString() ?? '';
    if (contentStr.startsWith('connected:')) {
      durationSec = int.tryParse(contentStr.split(':')[1]) ?? 0;
    } else if (rawDuration != null) {
      durationSec = (rawDuration as num).toInt();
    }

    if (durationSec <= 0) {
      return '0 sec';
    }

    final int mins = durationSec ~/ 60;
    final int secs = durationSec % 60;
    if (mins > 0) {
      return '$mins min $secs sec';
    }
    return '$secs sec';
  }

  void _showCallDetails(Map<String, dynamic> log, Map<String, dynamic> otherUser) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallInfoScreen(log: log, otherUser: otherUser),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _selectedCallIds.isNotEmpty
          ? AppBar(
              backgroundColor: AppTheme.surfaceColor,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectedCallIds.clear();
                  });
                },
              ),
              title: Text(
                '${_selectedCallIds.length} Selected',
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  tooltip: 'Delete Selected',
                  onPressed: _deleteSelectedCalls,
                ),
              ],
            )
          : null,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _callLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.call_end_outlined, size: 64, color: AppTheme.textSecondary),
                      const SizedBox(height: 16),
                      Text(
                        'No recent call logs',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchCalls,
                  child: ListView.builder(
                    itemCount: _callLogs.length,
                    itemBuilder: (context, index) {
                      final log = _callLogs[index];
                      final String logId = log['id'];
                      final isSelected = _selectedCallIds.contains(logId);
                      final isCaller = log['senderId'] == currentUserId;

                      final participants = log['conversation']?['participants'] as List<dynamic>? ?? [];
                      final otherParticipant = participants.firstWhere(
                        (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
                        orElse: () => null,
                      );

                      if (otherParticipant == null) return const SizedBox.shrink();

                      final otherUser = otherParticipant['user'];
                      final isMissed = log['content'] == 'missed' || log['content'] == 'declined';
                      final isVideo = log['mediaUrl'] == 'video';

                      IconData iconData;
                      Color iconColor;

                      if (isMissed) {
                        iconData = isCaller ? Icons.call_made : Icons.call_missed;
                        iconColor = Colors.red;
                      } else {
                        iconData = isCaller ? Icons.call_made : Icons.call_received;
                        iconColor = Colors.green;
                      }

                      IconData typeIcon = isVideo ? Icons.videocam : Icons.call;

                      return Container(
                        color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.15) : Colors.transparent,
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
                            } else {
                              _showCallDetails(log, otherUser);
                            }
                          },
                          leading: otherUser['avatarUrl'] != null && otherUser['avatarUrl'].toString().isNotEmpty
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
                            otherUser['username'] ?? 'User',
                            style: TextStyle(
                              color: isMissed ? Colors.red : AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Icon(iconData, size: 16, color: iconColor),
                              const SizedBox(width: 4),
                              Icon(typeIcon, size: 14, color: AppTheme.textSecondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${DateFormat('MMM d, h:mm a').format(DateTime.parse(log['createdAt']).toLocal())} • ${_formatCallDuration(log['content'], log['duration'])}',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          trailing: _selectedCallIds.isEmpty
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.call, color: AppTheme.primaryColor, size: 22),
                                      onPressed: () => _startCall(otherUser, true, log['conversationId']),
                                      tooltip: 'Audio Call',
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.videocam, color: AppTheme.primaryColor, size: 22),
                                      onPressed: () => _startCall(otherUser, false, log['conversationId']),
                                      tooltip: 'Video Call',
                                    ),
                                  ],
                                )
                              : Checkbox(
                                  value: isSelected,
                                  activeColor: AppTheme.primaryColor,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedCallIds.add(logId);
                                      } else {
                                        _selectedCallIds.remove(logId);
                                      }
                                    });
                                  },
                                ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
