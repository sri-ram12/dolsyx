import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';

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
              else if (message.mediaType == 'CALL')
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      message.mediaUrl == 'video' ? Icons.videocam : Icons.phone, 
                      color: message.content == 'missed' || message.content == 'declined' 
                          ? Colors.redAccent 
                          : (isMe ? Colors.white : AppTheme.textPrimary)
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message.content == 'missed' ? 'Missed ${message.mediaUrl == "video" ? "Video" : "Voice"} Call' :
                        message.content == 'declined' ? 'Declined ${message.mediaUrl == "video" ? "Video" : "Voice"} Call' :
                        '\${message.mediaUrl == "video" ? "Video" : "Voice"} Call \${message.content.startsWith("connected:") ? "Ended" : ""}',
                        style: TextStyle(
                          color: message.content == 'missed' || message.content == 'declined'
                              ? Colors.redAccent
                              : (isMe ? Colors.white : AppTheme.textPrimary),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                )
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
            if (message.content.isNotEmpty && message.mediaType != 'CALL')
              Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : AppTheme.textPrimary,
                  fontSize: 15,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
