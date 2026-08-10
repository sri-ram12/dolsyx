import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import '../providers/auth_provider.dart';
import 'chat_room_screen.dart';
import 'call_screen.dart';

class CallInfoScreen extends StatelessWidget {
  final Map<String, dynamic> log;
  final Map<String, dynamic> otherUser;

  const CallInfoScreen({
    super.key,
    required this.log,
    required this.otherUser,
  });

  String _formatCallDuration(dynamic logContent, dynamic rawDuration) {
    if (logContent == 'missed' || logContent == 'declined') {
      return 'Missed';
    }
    int durationSec = 0;
    final contentStr = logContent?.toString() ?? '';
    if (contentStr.startsWith('connected:')) {
      final parts = contentStr.split(':');
      if (parts.length > 1) {
        durationSec = int.tryParse(parts[1]) ?? 0;
      }
    }
    if (durationSec <= 0 && rawDuration != null) {
      durationSec = int.tryParse(rawDuration.toString()) ?? 0;
    }
    if (durationSec <= 0) return 'Connected';

    final int minutes = durationSec ~/ 60;
    final int seconds = durationSec % 60;
    if (minutes > 0) {
      return '$minutes min ${seconds > 0 ? '$seconds sec' : ''}'.trim();
    }
    return '$seconds sec';
  }

  @override
  Widget build(BuildContext context) {
    final name = otherUser['username'] ?? 'User';
    final email = otherUser['email'] ?? otherUser['phone'] ?? '+91 63007 21822';
    final avatarUrl = otherUser['avatarUrl'];
    final userId = (otherUser['id'] ?? otherUser['_id'] ?? '').toString();

    final isVideo = log['mediaUrl'] == 'video';
    final isMissed = log['content'] == 'missed' || log['content'] == 'declined';
    final durationText = _formatCallDuration(log['content'], log['duration']);

    DateTime? createdAt;
    try {
      if (log['createdAt'] != null) {
        createdAt = DateTime.tryParse(log['createdAt'].toString());
      }
    } catch (_) {}

    final dateStr = createdAt != null ? DateFormat('EEEE, MMM d').format(createdAt) : 'Yesterday';
    final timeStr = createdAt != null ? DateFormat('h:mm a').format(createdAt) : '5:21 PM';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Sleek WhatsApp Dark Navy Background
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Call info',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF1E293B),
            onSelected: (val) {},
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'remove', child: Text('Remove from call log', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'block', child: Text('Block user', style: TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Profile Circle Avatar Header
            Center(
              child: CircleAvatar(
                radius: 60,
                backgroundColor: const Color(0xFF4C1D95), // Vibrant purple tone like Screenshot 2
                backgroundImage: avatarUrl != null && avatarUrl.toString().isNotEmpty
                    ? NetworkImage(avatarUrl.toString().startsWith('http') ? avatarUrl : 'https://dolsyx-app.onrender.com$avatarUrl')
                    : null,
                child: avatarUrl == null || avatarUrl.toString().isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Color(0xFFF472B6), fontSize: 48, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            // Name & Phone/Email
            Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              email,
              style: const TextStyle(color: Colors.white60, fontSize: 15),
            ),
            const SizedBox(height: 24),

            // Action Row: Message | Audio | Video (Pill Buttons)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Message',
                  onTap: () {
                    final conversationId = log['conversationId'] ?? log['conversation']?['id'] ?? '';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(
                          conversationId: conversationId,
                          chatName: name,
                          avatarUrl: avatarUrl,
                          remoteUserId: userId,
                          remoteUser: otherUser,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 24),
                _buildActionButton(
                  context,
                  icon: Icons.phone_outlined,
                  label: 'Audio',
                  onTap: () {
                    final conversationId = log['conversationId'] ?? log['conversation']?['id'] ?? '';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CallScreen(
                          conversationId: conversationId,
                          remoteUserId: userId,
                          remoteUserName: name,
                          remoteAvatarUrl: avatarUrl,
                          isAudioOnly: true,
                          isIncoming: false,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 24),
                _buildActionButton(
                  context,
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  onTap: () {
                    final conversationId = log['conversationId'] ?? log['conversation']?['id'] ?? '';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CallScreen(
                          conversationId: conversationId,
                          remoteUserId: userId,
                          remoteUserName: name,
                          remoteAvatarUrl: avatarUrl,
                          isAudioOnly: false,
                          isIncoming: false,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(color: Colors.white12, height: 1),

            // Call Timeline History Section (Matching Screenshot 2)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.call_missed_outgoing_rounded,
                        color: isMissed ? Colors.redAccent : Colors.greenAccent,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMissed ? 'Missed' : (isVideo ? 'Video call • $durationText' : 'Voice call • $durationText'),
                              style: TextStyle(
                                color: isMissed ? Colors.redAccent : Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timeStr,
                              style: const TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
