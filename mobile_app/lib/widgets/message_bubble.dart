import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
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
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import '../screens/view_once_screen.dart';
import 'full_screen_image_view.dart';
import 'animated_emoji.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool isGroup;
  final Function(Message)? onSwipeReply;
  final bool showReadReceipts;
  final Function(bool isVideo)? onTapCall;
  final String? searchQuery;
  final Function(String)? onViewOnceOpened;
  final Function(String)? onTapReplyReference;

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
    this.onTapReplyReference,
  });

  static final RegExp _urlRegex = RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);

  Widget _buildMessageText(String text, Color textColor, double fontSize) {
    if (EmojiUtils.isOnlyEmojis(text)) {
      final emojiChars = text.trim().characters.toList();
      if (emojiChars.length == 1) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: AnimatedEmoji(
            emoji: emojiChars[0],
            size: 38.0,
            animateLoop: true,
          ),
        );
      } else if (emojiChars.length <= 3) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Wrap(
            spacing: 6,
            alignment: WrapAlignment.center,
            children: emojiChars.map((e) => AnimatedEmoji(
              emoji: e,
              size: 28.0,
              animateLoop: true,
            )).toList(),
          ),
        );
      }
    }

    final matches = _urlRegex.allMatches(text);

    if (matches.isEmpty) {
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

    final firstUrlMatch = matches.first.group(0)!;
    final formattedUrl = firstUrlMatch.startsWith('http') ? firstUrlMatch : 'https://$firstUrlMatch';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(
          TextSpan(
            children: _buildSpansWithLinks(text, textColor, fontSize, formattedUrl),
          ),
        ),
        const SizedBox(height: 8),
        _buildLinkPreviewCard(formattedUrl),
      ],
    );
  }

  List<InlineSpan> _buildSpansWithLinks(String text, Color textColor, double fontSize, String targetUrl) {
    final urlRegex = RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
    final List<InlineSpan> spans = [];
    int start = 0;

    for (final match in urlRegex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: TextStyle(color: textColor, fontSize: fontSize)));
      }
      final urlText = match.group(0)!;
      final uriStr = urlText.startsWith('http') ? urlText : 'https://$urlText';
      spans.add(
        WidgetSpan(
          child: GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(uriStr);
              if (uri != null) {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {
                  try {
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  } catch (_) {}
                }
              }
            },
            child: Text(
              urlText,
              style: TextStyle(
                color: const Color(0xFF60A5FA),
                fontSize: fontSize,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: TextStyle(color: textColor, fontSize: fontSize)));
    }
    return spans;
  }

  Widget _buildLinkPreviewCard(String url) {
    Uri? uri = Uri.tryParse(url);
    final host = uri?.host.replaceAll('www.', '') ?? 'Link';

    IconData icon = Icons.language;
    String badgeTitle = 'Web Link';
    Color badgeColor = const Color(0xFF3B82F6);

    if (host.contains('facebook.com') || host.contains('fb.watch') || host.contains('fb.me') || host.contains('fb.com')) {
      icon = Icons.facebook;
      badgeTitle = 'Facebook Link';
      badgeColor = const Color(0xFF1877F2);
    } else if (host.contains('youtube.com') || host.contains('youtu.be')) {
      icon = Icons.play_circle_fill_rounded;
      badgeTitle = 'YouTube Video';
      badgeColor = Colors.redAccent;
    } else if (host.contains('instagram.com')) {
      icon = Icons.camera_alt_rounded;
      badgeTitle = 'Instagram Link';
      badgeColor = const Color(0xFFE4405F);
    } else if (host.contains('maps.google.com') || host.contains('goo.gl')) {
      icon = Icons.map_rounded;
      badgeTitle = 'Google Maps Location';
      badgeColor = Colors.green;
    } else if (host.contains('zoom.us') || host.contains('teams.microsoft.com') || host.contains('meet.google.com')) {
      icon = Icons.video_call_rounded;
      badgeTitle = 'Meeting Link';
      badgeColor = Colors.deepPurpleAccent;
    } else if (url.endsWith('.pdf') || url.contains('drive.google.com') || url.contains('dropbox.com')) {
      icon = Icons.picture_as_pdf_rounded;
      badgeTitle = 'Document / File';
      badgeColor = Colors.orangeAccent;
    }

    return GestureDetector(
      onTap: () async {
        final targetUri = uri ?? Uri.tryParse(url);
        if (targetUri != null) {
          try {
            await launchUrl(targetUri, mode: LaunchMode.externalApplication);
          } catch (_) {
            try {
              await launchUrl(targetUri, mode: LaunchMode.platformDefault);
            } catch (_) {}
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: badgeColor.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: badgeColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    badgeTitle,
                    style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    host.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    url,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  double _getEmojiFontSize(String text) {
    int count = text.characters.where((c) => c.trim().isNotEmpty).length;
    if (count == 1) return 38.0;
    if (count == 2) return 28.0;
    if (count == 3) return 24.0;
    return 18.0;
  }

  @override
  Widget build(BuildContext context) {
    final bool isOnlyImage = (message.mediaUrl != null &&
        message.mediaUrl!.isNotEmpty &&
        (message.mediaType == 'IMAGE' || message.mediaType == 'VIDEO') &&
        message.content.isEmpty) || message.mediaType == 'POLL';

    final imageSize = MediaQuery.of(context).size.width * 0.75;
    
    final bool emojiOnly = message.mediaUrl == null && EmojiUtils.isOnlyEmojis(message.content) && EmojiUtils.emojiCount(message.content) <= 3;
    final double userFontSize = Provider.of<ThemeProvider>(context).currentFontSize;
    final double fontSize = emojiOnly ? _getEmojiFontSize(message.content) : userFontSize;

    final Color senderTextColor = AppTheme.bubbleSender.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final Color receiverTextColor = AppTheme.bubbleReceiver.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final Color textColor = isMe ? senderTextColor : receiverTextColor;
    final Color secondaryTextColor = textColor.withOpacity(0.7);

    if (message.isDeleted) {
      final deletedWidget = Container(
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
      return _wrapSwipeable(deletedWidget);
    }

    if (message.mediaType == 'CALL_LOG') {
      return _wrapSwipeable(_buildCallLogBubble(context));
    }
    
    if (message.mediaType == 'LOCATION' || message.latitude != null) {
      return _wrapSwipeable(_buildLocationBubble(context));
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
                    GestureDetector(
                      onTap: () {
                        final parentId = (message.parentMessage!['id'] ?? message.parentMessage!['_id'])?.toString();
                        if (parentId != null && onTapReplyReference != null) {
                          onTapReplyReference!(parentId);
                        }
                      },
                      child: Container(
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
                              _getQuotedSenderName(message.parentMessage),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getQuotedContentText(message.parentMessage),
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
                      GestureDetector(
                        onTap: () {
                          if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => FullScreenImageView(
                                  imageUrl: message.mediaUrl!,
                                  isChatMedia: true,
                                  senderName: isMe ? 'You' : (message.sender?['username'] ?? message.sender?['name'] ?? 'Contact'),
                                  timestamp: message.createdAt,
                                  message: message,
                                ),
                              ),
                            );
                          }
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(isOnlyImage ? 16 : 8).copyWith(
                                bottomRight: (isMe && isOnlyImage) ? const Radius.circular(4) : null,
                                bottomLeft: (!isMe && isOnlyImage) ? const Radius.circular(4) : null,
                              ),
                              child: message.mediaUrl != null && !message.mediaUrl!.startsWith('http') && File(message.mediaUrl!).existsSync()
                                  ? Image.file(
                                      File(message.mediaUrl!),
                                      width: imageSize,
                                      fit: BoxFit.cover,
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: ApiService.getMediaUrl(message.mediaUrl),
                                      width: imageSize,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 600,
                                      memCacheHeight: 600,
                                      placeholder: (context, url) => Container(
                                        width: imageSize,
                                        height: imageSize * 0.75,
                                        color: Colors.black26,
                                        child: Center(
                                          child: SizedBox(
                                            width: 32,
                                            height: 32,
                                            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryColor),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        width: imageSize,
                                        height: 140,
                                        color: Colors.black26,
                                        child: const Icon(Icons.broken_image_rounded, size: 44, color: Colors.grey),
                                      ),
                                    ),
                            ),
                            // 🟢 WhatsApp In-Bubble Circular Buffering Indicator
                            if (message.isPending)
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.8,
                                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                                      ),
                                    ),
                                    const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                                  ],
                                ),
                              ),
                            if (isOnlyImage)
                              Positioned(
                                bottom: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: _buildReadReceiptInfo(Colors.white),
                                ),
                              ),
                          ],
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
                              height: 180,
                              decoration: BoxDecoration(
                                color: const Color(0xFF182229),
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
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [Colors.black38, Colors.black87],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 🟢 WhatsApp In-Bubble Buffering / Play Action
                                  if (message.isPending)
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox(
                                            width: 44,
                                            height: 44,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.8,
                                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                                            ),
                                          ),
                                          const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                                        ],
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white70, width: 1.5),
                                      ),
                                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                                    ),
                                  // Bottom Left Video Duration Pill
                                  Positioned(
                                    bottom: 6,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.65),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.videocam_rounded, color: Colors.white70, size: 12),
                                          SizedBox(width: 4),
                                          Text(
                                            'VIDEO',
                                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isOnlyImage)
                                    Positioned(
                                      bottom: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.55),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: _buildReadReceiptInfo(Colors.white),
                                      ),
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
                          isPending: message.isPending,
                        )
                      else 
                        GestureDetector(
                          onTap: () {
                            if (message.mediaUrl != null) {
                              final fullUrl = ApiService.getMediaUrl(message.mediaUrl!);
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: AppTheme.backgroundColor,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                builder: (ctx) => Container(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.description_rounded, size: 48, color: AppTheme.primaryColor),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Document Attachment Preview',
                                        style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        fullUrl,
                                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 24),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                        },
                                        icon: const Icon(Icons.close),
                                        label: const Text('Close Document Preview'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryColor,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.insert_drive_file, color: isMe ? Colors.white : AppTheme.textPrimary),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'File Attachment (Tap to Preview)',
                                  style: TextStyle(
                                    color: textColor,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    if (message.content.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (!isOnlyImage && message.mediaType != 'CALL_LOG' && message.mediaType != 'POLL' && message.mediaType != 'LOCATION')
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (message.content.isNotEmpty)
                            Flexible(
                              child: _buildMessageText(message.content, textColor, fontSize),
                            ),
                          const SizedBox(width: 8),
                          _buildReadReceiptInfo(textColor, isEmojiOnly: emojiOnly),
                        ],
                      ),
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
                      ...message.reactions!
                          .where((r) => r is Map && r['emoji'] != null)
                          .map((r) => r['emoji'].toString())
                          .toSet()
                          .map((emoji) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                                child: AnimatedEmoji(
                                  emoji: emoji,
                                  size: 14,
                                  animateLoop: false,
                                ),
                              )),
                      if (message.reactions!.length > 1) ...[
                        const SizedBox(width: 3),
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

    return _wrapSwipeable(bubbleContent);
  }

  Widget _wrapSwipeable(Widget child) {
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
              child: child,
            )
          : child,
    );
  }

  Widget _buildReadReceiptInfo(Color textColor, {bool isEmojiOnly = false}) {
    final effectiveColor = isEmojiOnly ? Colors.white70 : textColor.withOpacity(0.8);
    final rowContent = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${message.isEdited ? "edited • " : ""}${DateFormat('hh:mm a').format(message.createdAt.toLocal())}',
          style: TextStyle(
            fontSize: 10,
            color: effectiveColor,
            fontStyle: message.isEdited ? FontStyle.italic : FontStyle.normal,
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
                return Icon(Icons.access_time, size: 15, color: effectiveColor);
              } else if (isRead) {
                return const Icon(Icons.done_all, size: 16, color: Colors.cyanAccent);
              } else if (isDelivered) {
                return Icon(Icons.done_all, size: 16, color: effectiveColor);
              } else {
                return Icon(Icons.check, size: 16, color: effectiveColor);
              }
            },
          ),
        ],
      ],
    );

    if (isEmojiOnly) {
      return Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(10),
        ),
        child: rowContent,
      );
    }
    return rowContent;
  }

  String _getQuotedSenderName(dynamic parent) {
    if (parent == null) return 'User';
    if (parent is Map) {
      final sender = parent['sender'];
      if (sender is Map) {
        return (sender['username'] ?? sender['name'] ?? 'User').toString();
      }
      if (parent['senderName'] != null) {
        return parent['senderName'].toString();
      }
    }
    return 'User';
  }

  String _getQuotedContentText(dynamic parent) {
    if (parent == null) return 'Message';
    if (parent is Map) {
      if (parent['isDeleted'] == true || parent['content'] == 'This message was deleted') {
        return 'This message was deleted';
      }
      final mediaType = parent['mediaType'] ?? 'TEXT';
      final mediaUrl = parent['mediaUrl'];
      final content = (parent['content'] ?? '').toString();

      if (mediaType == 'CALL_LOG') {
        if (content.toLowerCase().contains('missed')) {
          return '📞 Missed call';
        } else if (content.toLowerCase().contains('declined')) {
          return '📞 Declined call';
        } else if (mediaUrl == 'VIDEO_CALL' || content.toLowerCase().contains('video')) {
          return '🎥 Video call';
        } else {
          return '📞 Voice call';
        }
      }
      if (mediaType == 'IMAGE') return '📷 Photo';
      if (mediaType == 'VIDEO') return '🎥 Video';
      if (mediaType == 'AUDIO') return '🎵 Voice message';
      if (mediaType == 'LOCATION') return '📍 Location';
      if (mediaType == 'POLL') return '📊 Poll';
      if (mediaType == 'DOCUMENT' || mediaType == 'FILE') return '📄 Document';
      if (mediaType == 'STICKER') return '😊 Sticker';

      if (content.isNotEmpty) return content;
    }
    return 'Message';
  }

  static final Map<String, String> _placeNameCache = {};

  Future<String> _reverseGeocode(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
    if (_placeNameCache.containsKey(key)) {
      return _placeNameCache[key]!;
    }
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1'),
        headers: {'User-Agent': 'DolsyxApp/1.0 (Mobile Client)'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'];
        if (address != null && address is Map) {
          final List<String> parts = [];
          final road = address['road'] ?? address['pedestrian'] ?? address['suburb'];
          final area = address['suburb'] ?? address['neighbourhood'] ?? address['city_district'];
          final city = address['city'] ?? address['town'] ?? address['village'] ?? address['county'];
          final state = address['state'];

          if (road != null) parts.add(road.toString());
          if (area != null && area.toString() != road.toString()) parts.add(area.toString());
          if (city != null) parts.add(city.toString());
          if (state != null && parts.length < 3) parts.add(state.toString());

          if (parts.isNotEmpty) {
            final result = parts.join(', ');
            _placeNameCache[key] = result;
            return result;
          }
        }
        if (data['display_name'] != null) {
          final String name = data['display_name'].toString();
          _placeNameCache[key] = name;
          return name;
        }
      }
    } catch (_) {}
    return 'Coordinates: ${lat.toStringAsFixed(4)}°, ${lng.toStringAsFixed(4)}°';
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

    String senderName = isMe ? 'You' : 'User';
    if (message.sender != null) {
      senderName = message.sender!['username'] ?? message.sender!['name'] ?? message.sender!['savedName'] ?? senderName;
    }

    void openMapApp() async {
      final String encodedName = Uri.encodeComponent("$senderName's Location");
      final Uri googleMapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$finalLat,$finalLng');
      final Uri geoUri = Uri.parse('geo:$finalLat,$finalLng?q=$finalLat,$finalLng($encodedName)');

      try {
        if (await canLaunchUrl(geoUri)) {
          await launchUrl(geoUri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}

      try {
        if (await canLaunchUrl(googleMapsUri)) {
          await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
        } else {
          await launchUrl(googleMapsUri, mode: LaunchMode.platformDefault);
        }
      } catch (_) {
        await launchUrl(googleMapsUri, mode: LaunchMode.externalNonBrowserApplication);
      }
    }

    return GestureDetector(
        onTap: openMapApp,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          width: 270,
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
              // 1. Street Map Preview Image with Sender Name Overlay & Red Pin Marker
              SizedBox(
                height: 150,
                width: 270,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Image.network(
                        'https://static-maps.yandex.ru/1.x/?lang=en_US&ll=$finalLng,$finalLat&z=16&l=map&pt=$finalLng,$finalLat,pm2rdm',
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
                                  '${finalLat.toStringAsFixed(6)}, ${finalLng.toStringAsFixed(6)}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Top Sender Name Banner Overlay
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        color: Colors.black.withOpacity(0.7),
                        child: Row(
                          children: [
                            Icon(
                              isLive ? Icons.my_location : Icons.person_pin_circle,
                              color: isLive ? Colors.greenAccent : Colors.redAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "$senderName's Location",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isLive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Center Red Pin Marker Container with User Name Badge
                    Positioned(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                            ),
                            child: Text(
                              senderName,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Icon(Icons.location_on, size: 32, color: Colors.redAccent),
                        ],
                      ),
                    ),
                    // Route tracing pill badge at bottom left
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.near_me, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text('Track GPS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 2. Title & Address details with Reverse Geocoding
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String>(
                      future: _reverseGeocode(finalLat, finalLng),
                      builder: (context, snapshot) {
                        final String displayPlace = snapshot.data ?? (locTitle.isNotEmpty && locTitle != 'Location' && locTitle != 'Current Location' ? locTitle : 'Fetching place name...');
                        return Row(
                          children: [
                            Icon(
                              isLive ? Icons.my_location : Icons.location_on,
                              color: isLive ? Colors.green : Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                displayPlace,
                                style: TextStyle(
                                  color: isMe ? (AppTheme.bubbleSender.computeLuminance() > 0.5 ? Colors.black87 : Colors.white) : (AppTheme.bubbleReceiver.computeLuminance() > 0.5 ? Colors.black87 : Colors.white),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'GPS: ${finalLat.toStringAsFixed(6)}°, ${finalLng.toStringAsFixed(6)}°',
                      style: TextStyle(
                        color: isMe ? (AppTheme.bubbleSender.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70) : (AppTheme.bubbleReceiver.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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

    String subtitleText = 'Tap to call back';
    if (message.content.startsWith('connected:')) {
      final int sec = int.tryParse(message.content.split(':')[1]) ?? 0;
      if (sec > 0) {
        final int mins = sec ~/ 60;
        final int secs = sec % 60;
        final String durStr = mins > 0 ? '$mins min $secs sec' : '$secs sec';
        subtitleText = '$durStr • Tap to call back';
      }
    }

    return GestureDetector(
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
                    subtitleText,
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

class AudioPlayWidget extends StatefulWidget {
  final String url;
  final Color color;
  final bool isPending;

  const AudioPlayWidget({
    super.key,
    required this.url,
    required this.color,
    this.isPending = false,
  });

  @override
  State<AudioPlayWidget> createState() => _AudioPlayWidgetState();
}

class _AudioPlayWidgetState extends State<AudioPlayWidget> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
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

  void _toggleSpeed() async {
    double nextSpeed = 1.0;
    if (_playbackSpeed == 1.0) {
      nextSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }
    setState(() => _playbackSpeed = nextSpeed);
    try {
      await _player.setPlaybackRate(nextSpeed);
    } catch (_) {}
  }

  void _togglePlay() async {
    if (widget.isPending) return;
    try {
      if (_isPlaying) {
        await _player.pause();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        Source source;
        if (!widget.url.startsWith('http') && File(widget.url).existsSync()) {
          source = DeviceFileSource(widget.url);
        } else {
          final fullUrl = ApiService.getMediaUrl(widget.url);
          source = UrlSource(fullUrl);
        }
        await _player.play(source);
        await _player.setPlaybackRate(_playbackSpeed);
        if (mounted) setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Audio play error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isPending)
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  ),
                ),
                const Icon(Icons.close_rounded, color: Colors.white, size: 16),
              ],
            ),
          )
        else
          IconButton(
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: widget.color, size: 36),
            onPressed: _togglePlay,
          ),
        const SizedBox(width: 8),
        Text(
          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
          style: TextStyle(color: widget.color, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _toggleSpeed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _playbackSpeed == 1.0 ? '1x' : (_playbackSpeed == 1.5 ? '1.5x' : '2x'),
              style: TextStyle(color: widget.color, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
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
