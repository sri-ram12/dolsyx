import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOnlyImage = message.mediaUrl != null &&
        message.mediaUrl!.isNotEmpty &&
        message.mediaType == 'IMAGE' &&
        message.content.isEmpty;

    final imageSize = MediaQuery.of(context).size.width * 0.75;

    if (message.mediaType == 'CALL_LOG') {
      return _buildCallLogBubble(context);
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: isOnlyImage
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isOnlyImage ? Colors.transparent : (isMe ? AppTheme.primaryColor : AppTheme.surfaceColor),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
            bottomLeft: !isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) ...[
              if (message.mediaType == 'IMAGE')
                ClipRRect(
                  borderRadius: BorderRadius.circular(isOnlyImage ? 16 : 8).copyWith(
                    bottomRight: (isMe && isOnlyImage) ? const Radius.circular(4) : null,
                    bottomLeft: (!isMe && isOnlyImage) ? const Radius.circular(4) : null,
                  ),
                  child: CachedNetworkImage(
                    imageUrl: message.mediaUrl!.startsWith('http')
                        ? message.mediaUrl!
                        : 'https://dolsyx-app.onrender.com${message.mediaUrl}',
                    width: imageSize,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Container(
                      width: imageSize,
                      height: imageSize,
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                  ),
                )
              // Removed inline call log handling because it's handled at the root
              else 
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insert_drive_file, color: isMe ? Colors.white : AppTheme.textPrimary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'File Attachment',
                        style: TextStyle(
                          color: isMe ? Colors.white : AppTheme.textPrimary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              if (message.content.isNotEmpty) const SizedBox(height: 8),
            ],
            if (message.content.isNotEmpty && message.mediaType != 'CALL_LOG')
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: isMe ? Colors.white : AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('hh:mm a').format(message.createdAt.toLocal()),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white70 : AppTheme.textSecondary,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Builder(
                      builder: (context) {
                        bool isRead = false;
                        bool isDelivered = false;
                        if (message.receipts != null && message.receipts!.isNotEmpty) {
                          if (message.receipts!.any((r) => r['status'] == 'READ')) {
                            isRead = true;
                          } else if (message.receipts!.any((r) => r['status'] == 'DELIVERED')) {
                            isDelivered = true;
                          }
                        }
                        
                        if (isRead) {
                          return const Icon(Icons.done_all, size: 14, color: Colors.blue);
                        } else if (isDelivered) {
                          return const Icon(Icons.done_all, size: 14, color: Colors.white70);
                        } else {
                          return const Icon(Icons.check, size: 14, color: Colors.white70);
                        }
                      },
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallLogBubble(BuildContext context) {
    final bool isVideo = message.mediaUrl == 'video';
    final bool isMissed = message.content == 'missed' || message.content == 'declined';
    
    IconData iconData;
    Color iconColor;
    if (isMissed) {
      iconData = isMe ? Icons.call_made : Icons.call_missed;
      iconColor = Colors.redAccent;
    } else {
      iconData = isMe ? Icons.call_made : Icons.call_received;
      iconColor = Colors.green;
    }

    String title = isMissed 
        ? 'Missed ${isVideo ? "video" : "voice"} call'
        : (message.content == 'declined' ? 'Declined ${isVideo ? "video" : "voice"} call' : '${isVideo ? "Video" : "Voice"} call');

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor, // Always surface color for call logs
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: iconColor.withOpacity(0.15),
              radius: 20,
              child: Icon(
                isVideo ? Icons.videocam : Icons.phone,
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconData, color: iconColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      title,
                      style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to call back',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Text(
              DateFormat('h:mm a').format(message.createdAt.toLocal()),
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
