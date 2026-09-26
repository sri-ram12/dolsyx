import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
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
import '../screens/forward_message_screen.dart';
import 'full_screen_image_view.dart';
import 'animated_emoji.dart';
import '../utils/e2ee/e2ee_media_cache.dart';
import '../utils/e2ee/crypto_service.dart';
import '../utils/media_size_helper.dart';
import '../services/link_preview_service.dart';
import '../models/link_preview_data.dart';

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
    final trimmed = text.trim();
    if ((trimmed.startsWith('{') && (trimmed.contains('ciphertext') || trimmed.contains('e2ee'))) || (trimmed.contains(':') && trimmed.split(':').length == 3)) {
      // 0ms Synchronous Cache Hit: Render directly without FutureBuilder
      final cached = CryptoService.instance.getCachedDecryptedContent(trimmed);
      if (cached != null && cached != trimmed) {
        if (!cached.contains('ciphertext') && !cached.contains('conv_v1')) {
          return _buildMessageText(cached, textColor, fontSize);
        }
        if (cached.contains(':') && cached.split(':').length == 3) {
          return Text("Encrypted message", style: TextStyle(color: textColor.withOpacity(0.7), fontSize: fontSize, fontStyle: FontStyle.italic));
        }
        return Text(cached, style: TextStyle(color: textColor, fontSize: fontSize));
      }

      return FutureBuilder<String>(
        future: CryptoService.instance.decryptIncomingContent(
          content: trimmed,
          senderUserId: message.senderId,
          conversationId: message.conversationId,
        ),
        builder: (context, snapshot) {
          final resolvedText = snapshot.data ?? trimmed;
          if (resolvedText != trimmed && !resolvedText.contains('ciphertext') && !resolvedText.contains('conv_v1')) {
            CryptoService.instance.cachePlaintext(trimmed, resolvedText);
            return _buildMessageText(resolvedText, textColor, fontSize);
          }
          if (resolvedText.contains(':') && resolvedText.split(':').length == 3) {
            return Text("Encrypted message", style: TextStyle(color: textColor.withOpacity(0.7), fontSize: fontSize, fontStyle: FontStyle.italic));
          }
          return Text(resolvedText, style: TextStyle(color: textColor, fontSize: fontSize));
        },
      );
    }

    if (EmojiUtils.isOnlyEmojis(text)) {
      final emojiChars = text.trim().characters.toList();
      if (emojiChars.length == 1) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: AnimatedEmoji(
            emoji: emojiChars[0],
            size: 38.0,
            animateLoop: false,
          ),
        );
      } else if (emojiChars.length == 2) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Wrap(
            spacing: 5,
            alignment: WrapAlignment.center,
            children: emojiChars.map((e) => AnimatedEmoji(
              emoji: e,
              size: 28.0,
              animateLoop: false,
            )).toList(),
          ),
        );
      } else if (emojiChars.length <= 3) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Wrap(
            spacing: 4,
            alignment: WrapAlignment.center,
            children: emojiChars.map((e) => AnimatedEmoji(
              emoji: e,
              size: 22.0,
              animateLoop: false,
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
    return _RichLinkPreviewCard(url: url);
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
    final bool isSystem = message.mediaType == 'SYSTEM' ||
        message.senderId == 'system' ||
        message.content.startsWith('SYSTEM:') ||
        message.content.endsWith('left the group') ||
        message.content.contains(' added ') ||
        message.content.contains(' removed ') ||
        message.content.endsWith('joined the group') ||
        message.content.endsWith('created group');

    if (isSystem) {
      final cleanText = message.content.replaceFirst('SYSTEM:', '').trim();
      return RepaintBoundary(
        child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF182229),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            cleanText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8696A0),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ));
    }

    final bool isSticker = message.mediaType == 'STICKER';
    final bool isGif = message.mediaType == 'GIF';
    final bool isDoc = message.mediaType == 'DOCUMENT' || message.mediaType == 'FILE' || (message.mediaUrl != null && RegExp(r'\.(pdf|docx?|xlsx?|pptx?|txt|zip|rar|apk|csv)($|\?)', caseSensitive: false).hasMatch(message.mediaUrl!));

    final bool isOnlyImage = (message.mediaUrl != null &&
        message.mediaUrl!.isNotEmpty &&
        (message.mediaType == 'IMAGE' || message.mediaType == 'VIDEO' || isSticker || isGif) &&
        message.content.isEmpty) || message.mediaType == 'POLL';

    final bool isMediaMessage = (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) ||
        isDoc ||
        message.mediaType == 'IMAGE' ||
        message.mediaType == 'VIDEO' ||
        message.mediaType == 'AUDIO' ||
        message.mediaType == 'POLL' ||
        isSticker ||
        isGif ||
        _urlRegex.hasMatch(message.content);

    final imageSize = MediaQuery.of(context).size.width * 0.75;
    
    final bool emojiOnly = message.mediaUrl == null && EmojiUtils.isOnlyEmojis(message.content) && EmojiUtils.emojiCount(message.content) <= 3;
    final double userFontSize = Provider.of<ThemeProvider>(context).currentFontSize;
    final double fontSize = emojiOnly ? _getEmojiFontSize(message.content) : userFontSize;

    final Color senderTextColor = AppTheme.bubbleSender.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final Color receiverTextColor = AppTheme.bubbleReceiver.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final Color textColor = isMe ? senderTextColor : receiverTextColor;
    final Color secondaryTextColor = textColor.withOpacity(0.7);

    // Forward button for media / documents / polls / stickers / links (frame_0026s.jpg, frame_0223s.jpg)
    Widget? forwardButton;
    if (isMediaMessage && !message.isDeleted) {
      forwardButton = GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ForwardMessageScreen(messages: [message]),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
          ),
          child: Transform.flip(
            flipX: true,
            child: const Icon(
              Icons.reply,
              size: 18,
              color: Colors.white70,
            ),
          ),
        ),
      );
    }

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
      return _wrapSwipeable(context, deletedWidget);
    }

    if (message.mediaType == 'CALL_LOG') {
      return _wrapSwipeable(context, _buildCallLogBubble(context));
    }
    
    if (message.mediaType == 'LOCATION' || message.latitude != null) {
      return _wrapSwipeable(context, _buildLocationBubble(context));
    }

    Widget bubbleContent = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: isOnlyImage || isSticker || emojiOnly
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isOnlyImage || emojiOnly || isSticker ? Colors.transparent : (isMe ? AppTheme.bubbleSender : AppTheme.bubbleReceiver),
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
                        String rawContent = message.content;
                        final cached = CryptoService.instance.getCachedDecryptedContent(rawContent);
                        if (cached != null) rawContent = cached;
                        pollData = jsonDecode(rawContent);
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
                                    onTap: () async {
                                      setPollState(() {
                                        if (userVoted) {
                                          currentVotes.remove(myUserId);
                                        } else {
                                          if (pollData['allowMultiple'] != true) {
                                            for (var o in options) {
                                              ((o['votes'] as List<dynamic>?) ?? []).remove(myUserId);
                                            }
                                          }
                                          currentVotes.add(myUserId);
                                        }
                                        opt['votes'] = currentVotes;
                                      });
                                      if (authProvider.socketService.socket?.connected == true) {
                                        final updatedJson = jsonEncode(pollData);
                                        String? encryptedContent;
                                        try {
                                          encryptedContent = await CryptoService.instance.encryptConversationPayload(
                                            conversationId: message.conversationId,
                                            plaintext: updatedJson,
                                          );
                                          CryptoService.instance.cachePlaintext(encryptedContent, updatedJson);
                                        } catch (_) {}

                                        authProvider.socketService.socket!.emit('vote_poll', {
                                          'conversationId': message.conversationId,
                                          'messageId': message.id,
                                          'optionId': opt['id'],
                                          if (encryptedContent != null) 'encryptedContent': encryptedContent,
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
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$totalVotes total votes',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
                                ),
                                GestureDetector(
                                  onTap: () => _showPollVotesBottomSheet(ctx, question, options, totalVotes),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'View votes',
                                      style: TextStyle(color: Color(0xFF53BDEB), fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
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
                              child: (message.mediaUrl != null &&
                                      (message.mediaUrl!.startsWith('/data/') || message.mediaUrl!.startsWith('/storage/') || message.mediaUrl!.startsWith('file://')) &&
                                      File(message.mediaUrl!.replaceFirst('file://', '')).existsSync())
                                  ? Image.file(
                                      File(message.mediaUrl!),
                                      width: imageSize,
                                      fit: BoxFit.cover,
                                    )
                                  : (message.isE2EEMedia && message.mediaKey != null && message.mediaUrl != null)
                                      ? FutureBuilder<File?>(
                                          future: E2EEMediaCache.getOrDownloadDecryptedMedia(
                                            mediaUrl: message.mediaUrl!,
                                            mediaKey: message.mediaKey,
                                            nonce: message.nonce,
                                            mediaType: message.mediaType,
                                          ),
                                          builder: (ctx, snap) {
                                            if (snap.connectionState == ConnectionState.done && snap.data != null) {
                                              return Image.file(snap.data!, width: imageSize, fit: BoxFit.cover);
                                            }
                                            final isDone = snap.connectionState == ConnectionState.done;
                                            if (isDone && snap.data == null && message.mediaUrl != null && !message.mediaUrl!.endsWith('.enc')) {
                                              return CachedNetworkImage(
                                                imageUrl: ApiService.getMediaUrl(message.mediaUrl),
                                                width: imageSize,
                                                fit: BoxFit.cover,
                                                memCacheWidth: 600,
                                                memCacheHeight: 600,
                                              );
                                            }
                                            Widget placeholderContent;
                                            if (message.thumbnail != null && message.thumbnail!.isNotEmpty) {
                                              try {
                                                final thumbBytes = base64Decode(message.thumbnail!);
                                                placeholderContent = Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    ImageFiltered(
                                                      imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                                      child: Image.memory(
                                                        thumbBytes,
                                                        width: imageSize,
                                                        height: imageSize * 0.75,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                                    Container(color: Colors.black26),
                                                    Center(
                                                      child: isDone && snap.data == null
                                                          ? const Icon(Icons.broken_image_rounded, color: Colors.grey, size: 36)
                                                          : _MediaDownloadPill(
                                                              fileSize: message.fileSize,
                                                              mediaUrl: message.mediaUrl,
                                                              isDownloading: !isDone,
                                                            ),
                                                    ),
                                                  ],
                                                );
                                              } catch (_) {
                                                placeholderContent = Center(
                                                  child: isDone && snap.data == null
                                                      ? const Icon(Icons.broken_image_rounded, color: Colors.grey, size: 36)
                                                      : _MediaDownloadPill(
                                                          fileSize: message.fileSize,
                                                          mediaUrl: message.mediaUrl,
                                                          isDownloading: !isDone,
                                                        ),
                                                );
                                              }
                                            } else {
                                              placeholderContent = Center(
                                                child: isDone && snap.data == null
                                                    ? const Icon(Icons.broken_image_rounded, color: Colors.grey, size: 36)
                                                    : _MediaDownloadPill(
                                                        fileSize: message.fileSize,
                                                        mediaUrl: message.mediaUrl,
                                                        isDownloading: !isDone,
                                                      ),
                                              );
                                            }

                                            return Container(
                                              width: imageSize,
                                              height: imageSize * 0.75,
                                              color: Colors.black26,
                                              child: placeholderContent,
                                            );
                                          },
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
                                              child: _MediaDownloadPill(
                                                fileSize: message.fileSize,
                                                mediaUrl: message.mediaUrl,
                                                isDownloading: true,
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
                            // 🟢 WhatsApp In-Bubble Download/Upload Pill
                            if (message.isPending)
                              _MediaDownloadPill(
                                fileSize: message.fileSize,
                                mediaUrl: message.mediaUrl,
                                isDownloading: true,
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
                              if (message.isViewOnce) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (ctx) => ViewOnceScreen(
                                      message: message,
                                      onViewed: (_) {},
                                    ),
                                  ),
                                );
                              } else {
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
                                  // 🟢 WhatsApp In-Bubble Download / Buffering / Play Action
                                  if (message.isPending)
                                    _MediaDownloadPill(
                                      fileSize: message.fileSize,
                                      mediaUrl: message.mediaUrl,
                                      isDownloading: true,
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
                                  // Bottom Left Video Duration & Size Pill
                                  Positioned(
                                    bottom: 6,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.65),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.videocam_rounded, color: Colors.white70, size: 12),
                                          const SizedBox(width: 4),
                                          Text(
                                            (message.formattedFileSize.isNotEmpty
                                                ? 'VIDEO • ${message.formattedFileSize}'
                                                : (MediaSizeHelper.getCachedSize(message.mediaUrl) != null
                                                    ? 'VIDEO • ${MediaSizeHelper.formatBytes(MediaSizeHelper.getCachedSize(message.mediaUrl))}'
                                                    : 'VIDEO')),
                                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
                      else if (message.mediaType == 'STICKER')
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: CachedNetworkImage(
                            imageUrl: ApiService.getMediaUrl(message.mediaUrl!),
                            width: 140,
                            height: 140,
                            fit: BoxFit.contain,
                            placeholder: (_, __) => const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                              ),
                            ),
                            errorWidget: (_, __, ___) => const Icon(Icons.sticky_note_2_outlined, color: Colors.white60, size: 48),
                          ),
                        )
                      else if (message.mediaType == 'GIF')
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            alignment: Alignment.bottomLeft,
                            children: [
                              CachedNetworkImage(
                                imageUrl: ApiService.getMediaUrl(message.mediaUrl!),
                                width: 220,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  height: 140,
                                  width: 220,
                                  color: Colors.black26,
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                                ),
                                errorWidget: (_, __, ___) => const Icon(Icons.gif_box, color: Colors.white60, size: 48),
                              ),
                              Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.65),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('GIF', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        )
                      else if (message.mediaType == 'AUDIO' || message.mediaType == 'VOICE')
                        AudioPlayWidget(
                          url: message.mediaUrl!,
                          color: isMe ? Colors.white : AppTheme.textPrimary,
                          isPending: message.isPending,
                          mediaKey: message.mediaKey,
                          nonce: message.nonce,
                          isMe: isMe,
                        )
                      else 
                        _buildDocumentCard(context, textColor, secondaryTextColor),
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

    return _wrapSwipeable(context, RepaintBoundary(child: bubbleContent), forwardButton: forwardButton);
  }

  Widget _buildDocumentCard(BuildContext context, Color textColor, Color secondaryTextColor) {
    final fileName = message.content.trim().isNotEmpty
        ? message.content.trim()
        : (message.mediaUrl != null ? message.mediaUrl!.split('/').last.split('?').first : 'Document');
    final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : 'DOC';
    
    Color badgeColor = Colors.blueAccent;
    IconData badgeIcon = Icons.description;
    if (ext == 'PDF') {
      badgeColor = const Color(0xFFE53935);
      badgeIcon = Icons.picture_as_pdf_rounded;
    } else if (ext.contains('DOC')) {
      badgeColor = const Color(0xFF2B579A);
      badgeIcon = Icons.article_rounded;
    } else if (ext.contains('XLS')) {
      badgeColor = const Color(0xFF217346);
      badgeIcon = Icons.table_chart_rounded;
    } else if (ext.contains('PPT')) {
      badgeColor = const Color(0xFFD24726);
      badgeIcon = Icons.slideshow_rounded;
    } else if (ext == 'ZIP' || ext == 'RAR') {
      badgeColor = const Color(0xFF8E24AA);
      badgeIcon = Icons.folder_zip_rounded;
    }

    return GestureDetector(
      onTap: () async {
        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) {
          if (message.isE2EEMedia && message.mediaKey != null) {
            final decrypted = await E2EEMediaCache.getOrDownloadDecryptedMedia(
              mediaUrl: message.mediaUrl!,
              mediaKey: message.mediaKey,
              nonce: message.nonce,
            );
            if (decrypted != null) {
              try {
                await launchUrl(Uri.file(decrypted.path), mode: LaunchMode.externalApplication);
                return;
              } catch (_) {}
            }
          }
          final fullUrl = ApiService.getMediaUrl(message.mediaUrl!);
          final uri = Uri.tryParse(fullUrl);
          if (uri != null) {
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {
              try {
                await launchUrl(uri, mode: LaunchMode.platformDefault);
              } catch (_) {}
            }
          }
        }
      },
      child: Container(
        width: 250,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF005C4B).withOpacity(0.8) : const Color(0xFF202C33),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 52,
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: badgeColor.withOpacity(0.5)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(badgeIcon, color: badgeColor, size: 28),
                  Positioned(
                    bottom: 2,
                    child: Text(
                      ext.length > 4 ? ext.substring(0, 4) : ext,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        (message.formattedFileSize.isNotEmpty
                            ? '${message.formattedFileSize} • '
                            : (MediaSizeHelper.getCachedSize(message.mediaUrl) != null
                                ? '${MediaSizeHelper.formatBytes(MediaSizeHelper.getCachedSize(message.mediaUrl))} • '
                                : '')) + '$ext Document',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '• Tap to open',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _MediaDownloadPill(
              fileSize: message.fileSize,
              mediaUrl: message.mediaUrl,
              isDownloading: message.isPending,
            ),
          ],
        ),
      ),
    );
  }

  void _showPollVotesBottomSheet(BuildContext context, String question, List<dynamic> options, int totalVotes) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Poll votes',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$totalVotes votes',
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                question,
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(color: Colors.white24, height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 16),
                  itemBuilder: (context, idx) {
                    final opt = options[idx];
                    final optText = opt['text'] ?? 'Option ${idx + 1}';
                    final votes = (opt['votes'] as List<dynamic>?) ?? [];
                    final pct = totalVotes > 0 ? (votes.length / totalVotes) : 0.0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              optText,
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${votes.length} vote${votes.length == 1 ? '' : 's'} (${(pct * 100).toInt()}%)',
                              style: const TextStyle(color: Color(0xFF53BDEB), fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            backgroundColor: Colors.white12,
                            color: const Color(0xFF00A884),
                          ),
                        ),
                        if (votes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: votes.map((v) {
                              final voterStr = v.toString();
                              final display = voterStr.length > 8 ? voterStr.substring(0, 8) : voterStr;
                              return Chip(
                                avatar: CircleAvatar(
                                  backgroundColor: AppTheme.primaryColor,
                                  child: Text(display.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white)),
                                ),
                                label: Text(display, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                backgroundColor: const Color(0xFF2A3942),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _wrapSwipeable(BuildContext context, Widget child, {Widget? forwardButton}) {
    Widget content = child;
    if (forwardButton != null) {
      if (isMe) {
        content = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            forwardButton,
            const SizedBox(width: 8),
            child,
          ],
        );
      } else {
        content = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            child,
            const SizedBox(width: 8),
            forwardButton,
          ],
        );
      }
    }

    return RepaintBoundary(
      child: Align(
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
                child: content,
              )
            : content,
      ),
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
      ).timeout(const Duration(seconds: 15));

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
  final String? mediaKey;
  final String? nonce;
  final bool isMe;

  const AudioPlayWidget({
    super.key,
    required this.url,
    required this.color,
    this.isPending = false,
    this.mediaKey,
    this.nonce,
    this.isMe = false,
  });

  @override
  State<AudioPlayWidget> createState() => _AudioPlayWidgetState();
}

class _AudioPlayWidgetState extends State<AudioPlayWidget> {
  static AudioPlayer? _activeGlobalPlayer;
  static _AudioPlayWidgetState? _activeState;

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _completeSub;
  late final List<double> _waveformBars;

  @override
  void initState() {
    super.initState();
    _waveformBars = _generateWaveform(widget.url);
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

  /// Generates 30 smooth deterministic normalized amplitude bars (0.15 to 1.0)
  List<double> _generateWaveform(String seedStr) {
    int hash = seedStr.hashCode.abs();
    final bars = <double>[];
    for (int i = 0; i < 30; i++) {
      hash = (hash * 1103515245 + 12345) & 0x7fffffff;
      final val = 0.2 + ((hash % 100) / 100.0) * 0.8;
      bars.add(val);
    }
    return bars;
  }

  @override
  void dispose() {
    if (_activeGlobalPlayer == _player) {
      _activeGlobalPlayer = null;
      _activeState = null;
    }
    _durationSub?.cancel();
    _positionSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _pauseIfPlaying() {
    if (_isPlaying) {
      _player.pause();
      if (mounted) setState(() => _isPlaying = false);
    }
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
        // Stop any currently playing voice note in the app (WhatsApp single-playback behavior)
        if (_activeGlobalPlayer != null && _activeGlobalPlayer != _player) {
          _activeState?._pauseIfPlaying();
        }
        _activeGlobalPlayer = _player;
        _activeState = this;

        Source source;
        if (widget.mediaKey != null && widget.nonce != null) {
          final decryptedFile = await E2EEMediaCache.getOrDownloadDecryptedMedia(
            mediaUrl: widget.url,
            mediaKey: widget.mediaKey,
            nonce: widget.nonce,
          );
          if (decryptedFile != null) {
            source = DeviceFileSource(decryptedFile.path);
          } else {
            source = UrlSource(ApiService.getMediaUrl(widget.url));
          }
        } else if (!widget.url.startsWith('http') &&
            !widget.url.startsWith('/uploads') &&
            (widget.url.startsWith('/data/') || widget.url.startsWith('/storage/') || widget.url.startsWith('file://')) &&
            File(widget.url.replaceFirst('file://', '')).existsSync()) {
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

  void _seekByFraction(double fraction) {
    if (_duration.inMilliseconds <= 0) return;
    final clamped = fraction.clamp(0.0, 1.0);
    final targetMs = (_duration.inMilliseconds * clamped).round();
    _player.seek(Duration(milliseconds: targetMs));
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final playedColor = widget.isMe ? Colors.white : const Color(0xFF00A884);
    final unplayedColor = widget.isMe ? Colors.white38 : Colors.grey.shade600;

    return Container(
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Play / Pause / Loading Button
          if (widget.isPending)
            Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A884)),
                  ),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: widget.isMe
                      ? Colors.white.withValues(alpha: 0.2)
                      : const Color(0xFF00A884).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: widget.isMe ? Colors.white : const Color(0xFF00A884),
                  size: 26,
                ),
              ),
            ),

          // Waveform + Timer Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Interactive Waveform
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        final frac = details.localPosition.dx / width;
                        _seekByFraction(frac);
                      },
                      onHorizontalDragUpdate: (details) {
                        final frac = details.localPosition.dx / width;
                        _seekByFraction(frac);
                      },
                      child: Container(
                        height: 28,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(_waveformBars.length, (idx) {
                            final barFrac = (idx + 1) / _waveformBars.length;
                            final isPlayed = progress >= barFrac;
                            final height = 4.0 + (_waveformBars[idx] * 20.0);

                            return Container(
                              width: 2.6,
                              height: height,
                              decoration: BoxDecoration(
                                color: isPlayed ? playedColor : unplayedColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),

                // Timer & Speed Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isPlaying
                          ? _formatDuration(_position)
                          : (_duration > Duration.zero ? _formatDuration(_duration) : _formatDuration(_position)),
                      style: TextStyle(
                        color: widget.isMe ? Colors.white70 : Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: _toggleSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: widget.isMe
                              ? Colors.white.withValues(alpha: 0.2)
                              : const Color(0xFF00A884).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _playbackSpeed == 1.0 ? '1x' : (_playbackSpeed == 1.5 ? '1.5x' : '2x'),
                          style: TextStyle(
                            color: widget.isMe ? Colors.white : const Color(0xFF00A884),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // Small Mic Badge on right
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: widget.isMe
                  ? Colors.white.withValues(alpha: 0.15)
                  : const Color(0xFF00A884).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic_rounded,
              size: 13,
              color: widget.isMe ? Colors.white70 : const Color(0xFF00A884),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// WhatsApp-style Media Download Pill matching reference design:
/// Grey capsule pill with a white down arrow and bold white KB/MB size text.
class _MediaDownloadPill extends StatefulWidget {
  final int? fileSize;
  final String? mediaUrl;
  final bool isDownloading;
  final VoidCallback? onTap;

  const _MediaDownloadPill({
    this.fileSize,
    this.mediaUrl,
    this.isDownloading = false,
    this.onTap,
  });

  @override
  State<_MediaDownloadPill> createState() => _MediaDownloadPillState();
}

class _MediaDownloadPillState extends State<_MediaDownloadPill> {
  int? _resolvedSize;

  @override
  void initState() {
    super.initState();
    _resolvedSize = widget.fileSize ?? MediaSizeHelper.getCachedSize(widget.mediaUrl);
    if (_resolvedSize == null && widget.mediaUrl != null) {
      MediaSizeHelper.resolveFileSize(widget.mediaUrl, onResolved: () {
        if (mounted) {
          setState(() {
            _resolvedSize = MediaSizeHelper.getCachedSize(widget.mediaUrl);
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _MediaDownloadPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fileSize != oldWidget.fileSize || widget.mediaUrl != oldWidget.mediaUrl) {
      _resolvedSize = widget.fileSize ?? MediaSizeHelper.getCachedSize(widget.mediaUrl);
      if (_resolvedSize == null && widget.mediaUrl != null) {
        MediaSizeHelper.resolveFileSize(widget.mediaUrl, onResolved: () {
          if (mounted) {
            setState(() {
              _resolvedSize = MediaSizeHelper.getCachedSize(widget.mediaUrl);
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeText = MediaSizeHelper.formatBytes(_resolvedSize);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xB34A4A4A),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.isDownloading) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              if (sizeText.isNotEmpty) const SizedBox(width: 7),
            ] else ...[
              const Icon(
                Icons.arrow_downward_rounded,
                color: Colors.white,
                size: 18,
              ),
              if (sizeText.isNotEmpty) const SizedBox(width: 7),
            ],
            if (sizeText.isNotEmpty)
              Text(
                sizeText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-grade OpenGraph Rich Link Preview Card (Phase 10)
class _RichLinkPreviewCard extends StatefulWidget {
  final String url;
  const _RichLinkPreviewCard({required this.url});

  @override
  State<_RichLinkPreviewCard> createState() => _RichLinkPreviewCardState();
}

class _RichLinkPreviewCardState extends State<_RichLinkPreviewCard> {
  LinkPreviewData? _previewData;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(covariant _RichLinkPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    final data = await LinkPreviewService().fetchPreview(widget.url);
    if (mounted) {
      setState(() => _previewData = data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.url);
    final host = _previewData?.domain.isNotEmpty == true
        ? _previewData!.domain
        : (uri?.host.replaceAll('www.', '') ?? 'Link');
    final title = _previewData?.title ?? host;
    final description = _previewData?.description;
    final imageUrl = _previewData?.imageUrl;

    return GestureDetector(
      onTap: () async {
        final targetUri = uri ?? Uri.tryParse(widget.url);
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
        constraints: const BoxConstraints(maxWidth: 320),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF00A884).withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                height: 130,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 90,
                  color: Colors.black26,
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A884)),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.language_rounded, color: Color(0xFF00A884), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          host.toUpperCase(),
                          style: const TextStyle(color: Color(0xFF00A884), fontSize: 10, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

