import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import '../models/message.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final Function(Message)? onSwipeReply;
  final bool showReadReceipts;
  final VoidCallback? onTapCall;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onSwipeReply,
    this.showReadReceipts = true,
    this.onTapCall,
  });

  bool _isOnlyEmojis(String text) {
    if (text.trim().isEmpty) return false;
    final regex = RegExp(r'^[\p{Emoji_Presentation}\p{Extended_Pictographic}\s]+$', unicode: true);
    return regex.hasMatch(text.trim());
  }

  double _getEmojiFontSize(String text) {
    int count = text.characters.where((c) => c.trim().isNotEmpty).length;
    if (count == 1) return 48.0;
    if (count == 2) return 40.0;
    if (count == 3) return 32.0;
    return 22.0;
  }

  @override
  Widget build(BuildContext context) {
    final bool isOnlyImage = message.mediaUrl != null &&
        message.mediaUrl!.isNotEmpty &&
        message.mediaType == 'IMAGE' &&
        message.content.isEmpty;

    final imageSize = MediaQuery.of(context).size.width * 0.75;
    
    final bool emojiOnly = message.mediaUrl == null && _isOnlyEmojis(message.content);
    final double userFontSize = Provider.of<ThemeProvider>(context).currentFontSize;
    final double fontSize = emojiOnly ? _getEmojiFontSize(message.content) : userFontSize;

    final Color senderTextColor = AppTheme.bubbleSender.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final Color receiverTextColor = AppTheme.bubbleReceiver.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final Color textColor = isMe ? senderTextColor : receiverTextColor;
    final Color secondaryTextColor = textColor.withOpacity(0.7);

    if (message.isDeleted) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.bubbleSender.withOpacity(0.5) : AppTheme.bubbleReceiver.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
            bottomLeft: !isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: secondaryTextColor),
            const SizedBox(width: 6),
            Text(
              'This message was deleted',
              style: TextStyle(
                color: secondaryTextColor,
                fontStyle: FontStyle.italic,
                fontSize: userFontSize,
              ),
            ),
          ],
        ),
      );
    }

    if (message.mediaType == 'CALL_LOG') {
      return _buildCallLogBubble(context);
    }


    Widget bubbleContent = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: isOnlyImage
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isOnlyImage || emojiOnly ? Colors.transparent : (isMe ? AppTheme.bubbleSender : AppTheme.bubbleReceiver),
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                  bottomLeft: !isMe ? const Radius.circular(4) : const Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.isForwarded)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forward, size: 12, color: secondaryTextColor),
                          const SizedBox(width: 4),
                          Text(
                            'Forwarded',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message.parentMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(8),
                        border: Border(left: BorderSide(color: isMe ? Colors.white : AppTheme.primaryColor, width: 4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.parentMessage!['sender']?['username'] ?? 'User',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            message.parentMessage!['content'] ?? 'Message',
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryTextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
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
                      else if (message.mediaType == 'VIDEO')
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam, color: isMe ? Colors.white : AppTheme.textPrimary),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Video Attachment',
                                style: TextStyle(
                                  color: textColor,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        )
                      else if (message.mediaType == 'AUDIO')
                        AudioPlayWidget(
                          url: message.mediaUrl!,
                          color: isMe ? Colors.white : AppTheme.textPrimary,
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
                                  color: textColor,
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
                              color: textColor,
                              fontSize: fontSize,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('hh:mm a').format(message.createdAt.toLocal()),
                          style: TextStyle(
                            fontSize: 10,
                            color: secondaryTextColor,
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
                              
                              if (message.isPending) {
                                return const Icon(Icons.access_time, size: 15, color: Colors.white70);
                              } else if (isRead) {
                                return const Icon(Icons.done_all, size: 16, color: Colors.cyanAccent);
                              } else if (isDelivered) {
                                return const Icon(Icons.done_all, size: 16, color: Colors.white70);
                              } else {
                                return const Icon(Icons.check, size: 16, color: Colors.white70);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            if (message.reactions != null && message.reactions!.isNotEmpty)
              Positioned(
                bottom: -4,
                right: isMe ? 4 : null,
                left: !isMe ? 4 : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.backgroundColor, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...message.reactions!.map((r) => r['emoji']).toSet().map((emoji) => Text(
                        emoji,
                        style: const TextStyle(fontSize: 12),
                      )),
                      if (message.reactions!.length > 1) ...[
                        const SizedBox(width: 2),
                        Text(
                          message.reactions!.length.toString(),
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: onSwipeReply != null
          ? Dismissible(
              key: Key('dismiss_${message.id}'),
              direction: DismissDirection.startToEnd,
              onDismissed: (_) {},
              confirmDismiss: (direction) async {
                onSwipeReply!(message);
                return false; 
              },
              background: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 20),
                child: const Icon(Icons.reply, color: Colors.white, size: 28),
              ),
              child: bubbleContent,
            )
          : bubbleContent,
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
      child: GestureDetector(
        onTap: onTapCall,
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
      ),
    );
  }
}

class AudioPlayWidget extends StatefulWidget {
  final String url;
  final Color color;

  const AudioPlayWidget({super.key, required this.url, required this.color});

  @override
  State<AudioPlayWidget> createState() => _AudioPlayWidgetState();
}

class _AudioPlayWidgetState extends State<AudioPlayWidget> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _completeSub;

  @override
  void initState() {
    super.initState();
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.pause();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        final fullUrl = widget.url.startsWith('http') ? widget.url : 'https://dolsyx-app.onrender.com${widget.url}';
        await _player.play(UrlSource(fullUrl));
        if (mounted) setState(() => _isPlaying = true);
      }
    } catch (e) {
      print('Audio play error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: widget.color, size: 36),
          onPressed: _togglePlay,
        ),
        const SizedBox(width: 8),
        Text(
          _formatDuration(_position) + ' / ' + _formatDuration(_duration),
          style: TextStyle(color: widget.color, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
