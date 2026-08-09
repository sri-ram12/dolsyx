import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import '../models/message.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/view_once_screen.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool isGroup;
  final Function(Message)? onSwipeReply;
  final bool showReadReceipts;
  final Function(bool isVideo)? onTapCall;
  final String? searchQuery;
  final Function(String)? onViewOnceOpened;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isGroup = false,
    this.onSwipeReply,
    this.showReadReceipts = true,
    this.onTapCall,
    this.searchQuery,
    this.onViewOnceOpened,
  });

  Widget _buildMessageText(String text, Color textColor, double fontSize) {
    final query = searchQuery?.trim() ?? '';
    if (query.isEmpty) {
      return Text(text, style: TextStyle(color: textColor, fontSize: fontSize));
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final List<TextSpan> spans = [];
    int start = 0;
    int index;
    while ((index = lowerText.indexOf(lowerQuery, start)) != -1) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: TextStyle(color: textColor, fontSize: fontSize)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          backgroundColor: const Color(0xFFFFD700),
        ),
      ));
      start = index + query.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: TextStyle(color: textColor, fontSize: fontSize)));
    }
    return RichText(text: TextSpan(children: spans));
  }

  bool _isOnlyEmojis(String text) {
    if (text.trim().isEmpty) return false;
    final regex = RegExp(r'^(?:[\u2700-\u27BF]|[\uE000-\uF8FF]|\uD83C[\uDC00-\uDFFF]|\uD83D[\uDC00-\uDFFF]|[\u2011-\u26FF]|\uD83E[\uDD10-\uDDFF]|\s)+$');
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
    final bool isOnlyImage = (message.mediaUrl != null &&
        message.mediaUrl!.isNotEmpty &&
        (message.mediaType == 'IMAGE' || message.mediaType == 'VIDEO') &&
        message.content.isEmpty) || message.mediaType == 'POLL';

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
    
    if (message.mediaType == 'LOCATION' || message.latitude != null) {
      return _buildLocationBubble(context);
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
                  if (isGroup && !isMe && message.sender != null && message.sender!['username'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        message.sender!['username'],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
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
                  if (message.isViewOnce)
                    GestureDetector(
                      onTap: () {
                        if (message.isViewed || message.mediaUrl == null) return;
                        if (!isMe) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => ViewOnceScreen(
                                message: message,
                                onViewed: (msgId) {
                                  if (onViewOnceOpened != null) {
                                    onViewOnceOpened!(msgId);
                                  }
                                },
                              ),
                            ),
                          );
                        } else {
                          // Sender cannot view it again
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('You cannot view your own view once media')),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: message.isViewed ? Colors.grey : AppTheme.primaryColor, width: 2),
                              ),
                              child: Text(
                                '1',
                                style: TextStyle(
                                  color: message.isViewed ? Colors.grey : AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              message.isViewed ? 'Opened' : (message.mediaType == 'VIDEO' ? 'View Once Video' : 'View Once Photo'),
                              style: TextStyle(
                                color: message.isViewed ? secondaryTextColor : textColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  // 🟢 Location Message rendering
                  else if (message.mediaType == 'LOCATION' || message.latitude != null)
                    Container(
                      width: 220,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.white10 : Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                message.isLiveLocation ? Icons.my_location : Icons.location_on,
                                color: Colors.redAccent,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  message.isLiveLocation ? 'Live Location' : (message.locationTitle ?? 'Location Share'),
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Lat: ${message.latitude?.toStringAsFixed(4) ?? '0'}, Long: ${message.longitude?.toStringAsFixed(4) ?? '0'}',
                            style: TextStyle(color: secondaryTextColor, fontSize: 12),
                          ),
                          if (message.isLiveLocation && message.liveExpiresAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              message.isLiveEnded ? 'Live sharing ended' : 'Sharing live location',
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ],
                      ),
                    )
                  // 🟢 Poll Message rendering (Pic 1 style)
                  else if (message.mediaType == 'POLL' || message.content.contains('"question":') || message.content.contains('"mediaType":"POLL"'))
                    Builder(builder: (ctx) {
                      Map<String, dynamic> pollData = {};
                      try {
                        pollData = jsonDecode(message.content);
                      } catch (_) {}
                      final question = pollData['question'] ?? 'Poll';
                      final List<dynamic> options = (pollData['options'] as List<dynamic>?) ?? [];
                      final authProvider = Provider.of<AuthProvider>(ctx, listen: false);
                      final myUserId = authProvider.user?['id'] ?? 'user';
                      
                      final totalVotes = options.fold<int>(0, (sum, opt) => sum + (((opt['votes'] as List<dynamic>?)?.length) ?? 0));

                      return Container(
                        width: 270,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF005C4B), // WhatsApp dark green poll background
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              question,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 12),
                            ...options.map((opt) {
                              final text = opt['text'] ?? '';

                              return StatefulBuilder(
                                builder: (context, setPollState) {
                                  final currentVotes = (opt['votes'] as List<dynamic>?) ?? [];
                                  final userVoted = currentVotes.contains(myUserId);
                                  final currentPct = totalVotes > 0 ? (currentVotes.length / totalVotes) : 0.0;

                                  return GestureDetector(
                                    onTap: () {
                                      setPollState(() {
                                        if (userVoted) {
                                          currentVotes.remove(myUserId);
                                        } else {
                                          currentVotes.add(myUserId);
                                        }
                                        opt['votes'] = currentVotes;
                                      });
                                      if (authProvider.socketService.socket?.connected == true) {
                                        authProvider.socketService.socket!.emit('vote_poll', {
                                          'conversationId': message.conversationId,
                                          'messageId': message.id,
                                          'optionId': opt['id'],
                                        });
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 12.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                userVoted ? Icons.check_circle : Icons.radio_button_unchecked,
                                                color: userVoted ? Colors.lightBlueAccent : Colors.white60,
                                                size: 22,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  text,
                                                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                                                ),
                                              ),
                                              if (currentVotes.isNotEmpty)
                                                Text('${currentVotes.length}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: currentPct,
                                              minHeight: 6,
                                              backgroundColor: Colors.white24,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            }),
                            const SizedBox(height: 4),
                            Text(
                              '$totalVotes total votes',
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      );
                    })
                  else if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) ...[
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
                        GestureDetector(
                          onTap: () {
                            if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => ViewOnceScreen(
                                    message: message,
                                    onViewed: (_) {},
                                  ),
                                ),
                              );
                            }
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(isOnlyImage ? 16 : 8).copyWith(
                              bottomRight: (isMe && isOnlyImage) ? const Radius.circular(4) : null,
                              bottomLeft: (!isMe && isOnlyImage) ? const Radius.circular(4) : null,
                            ),
                            child: Container(
                              width: imageSize,
                              height: 160,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                border: Border.all(color: Colors.white.withOpacity(0.3), width: 0.8),
                                borderRadius: BorderRadius.circular(isOnlyImage ? 16 : 8).copyWith(
                                  bottomRight: (isMe && isOnlyImage) ? const Radius.circular(4) : null,
                                  bottomLeft: (!isMe && isOnlyImage) ? const Radius.circular(4) : null,
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Colors.black54, Colors.black87],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryColor.withOpacity(0.9),
                                          shape: BoxShape.circle,
                                          boxShadow: const [
                                            BoxShadow(color: Colors.black45, blurRadius: 8),
                                          ],
                                        ),
                                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Tap to play video',
                                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
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
                  if (message.content.isNotEmpty && message.mediaType != 'CALL_LOG' && message.mediaType != 'POLL' && message.mediaType != 'LOCATION')
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: _buildMessageText(message.content, textColor, fontSize),
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

  Widget _buildLocationBubble(BuildContext context) {
    double? lat = message.latitude;
    double? lng = message.longitude;
    String locTitle = message.locationTitle ?? (message.isLiveLocation ? 'Sharing live location' : 'Location');
    bool isLive = message.isLiveLocation;
    DateTime? liveExpires = message.liveExpiresAt;

    if ((lat == null || lng == null) && message.content.startsWith('{') && message.content.endsWith('}')) {
      try {
        final decoded = jsonDecode(message.content);
        lat = (decoded['latitude'] as num?)?.toDouble() ?? 12.9716;
        lng = (decoded['longitude'] as num?)?.toDouble() ?? 77.5946;
        locTitle = decoded['locationTitle'] ?? (decoded['isLiveLocation'] == true ? 'Sharing live location' : 'Location');
        isLive = decoded['isLiveLocation'] == true;
        if (decoded['liveExpiresAt'] != null) {
          liveExpires = DateTime.tryParse(decoded['liveExpiresAt'].toString());
        }
      } catch (_) {}
    }

    final double finalLat = lat ?? 12.9716;
    final double finalLng = lng ?? 77.5946;

    void openMapApp() async {
      final Uri mapUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$finalLat,$finalLng');
      if (await canLaunchUrl(mapUri)) {
        await launchUrl(mapUri, mode: LaunchMode.externalApplication);
      }
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: openMapApp,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          width: 260,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isMe ? AppTheme.bubbleSender : AppTheme.bubbleReceiver,
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
              bottomLeft: !isMe ? const Radius.circular(4) : const Radius.circular(16),
            ),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Street Map Preview Image with Red Pin Marker (Matching Image 1)
              SizedBox(
                height: 140,
                width: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Image.network(
                        'https://static-maps.yandex.ru/1.x/?lang=en_US&ll=$finalLng,$finalLat&z=15&l=map&pt=$finalLng,$finalLat,pm2rdm',
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          color: const Color(0xFF1E293B),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on, size: 42, color: Colors.redAccent),
                                const SizedBox(height: 4),
                                Text(
                                  '${finalLat.toStringAsFixed(4)}, ${finalLng.toStringAsFixed(4)}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Red Pin Marker Container
                    Positioned(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 6)],
                        ),
                        child: const Icon(Icons.location_on, size: 28, color: Colors.redAccent),
                      ),
                    ),
                    // Route tracing pill badge
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.directions, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text('Trace Route', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 2. Title & Address details (Matching Image 1 & Image 2)
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isLive ? Icons.my_location : Icons.location_on,
                          color: isLive ? Colors.green : Colors.redAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            locTitle,
                            style: TextStyle(
                              color: isMe ? (AppTheme.bubbleSender.computeLuminance() > 0.5 ? Colors.black87 : Colors.white) : (AppTheme.bubbleReceiver.computeLuminance() > 0.5 ? Colors.black87 : Colors.white),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'GPS: ${finalLat.toStringAsFixed(4)}, ${finalLng.toStringAsFixed(4)} • Tap to trace location',
                      style: TextStyle(
                        color: isMe ? (AppTheme.bubbleSender.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70) : (AppTheme.bubbleReceiver.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((isLive || message.isLiveLocation) && liveExpires != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Expires: ${DateFormat('h:mm a').format(liveExpires.toLocal())}',
                        style: TextStyle(
                          color: isMe ? (AppTheme.bubbleSender.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70) : (AppTheme.bubbleReceiver.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('hh:mm a').format(message.createdAt.toLocal()),
                          style: TextStyle(
                            fontSize: 10,
                            color: isMe ? (AppTheme.bubbleSender.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70) : (AppTheme.bubbleReceiver.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70),
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
      child: GestureDetector(
        onTap: () => onTapCall?.call(isVideo),
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
