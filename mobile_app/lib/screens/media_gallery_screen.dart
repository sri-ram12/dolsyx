import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/message.dart';
import '../widgets/full_screen_image_view.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class MediaGalleryScreen extends StatefulWidget {
  final String title;
  final List<Message> messages;
  final String? conversationId;

  const MediaGalleryScreen({
    super.key,
    required this.title,
    required this.messages,
    this.conversationId,
  });

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  late List<Message> _messages;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _messages = List.from(widget.messages);
    if (_messages.isEmpty && widget.conversationId != null) {
      _fetchConversationMessages();
    }
  }

  Future<void> _fetchConversationMessages() async {
    setState(() => _isLoading = true);
    try {
      final fetched = await ChatService().getMessages(widget.conversationId!);
      if (mounted) {
        setState(() {
          _messages = fetched;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading media gallery messages: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getFileExtension(String? url, String? content) {
    final target = (url ?? content ?? '').toLowerCase();
    if (target.contains('.pdf')) return 'PDF';
    if (target.contains('.doc') || target.contains('.docx')) return 'DOC';
    if (target.contains('.xls') || target.contains('.xlsx') || target.contains('.csv')) return 'XLS';
    if (target.contains('.ppt') || target.contains('.pptx')) return 'PPT';
    if (target.contains('.zip') || target.contains('.rar') || target.contains('.7z') || target.contains('.tar')) return 'ZIP';
    if (target.contains('.txt')) return 'TXT';
    return 'FILE';
  }

  Color _getExtensionColor(String ext) {
    switch (ext) {
      case 'PDF':
        return Colors.redAccent;
      case 'DOC':
        return Colors.blueAccent;
      case 'XLS':
        return Colors.green;
      case 'PPT':
        return Colors.orangeAccent;
      case 'ZIP':
        return Colors.amber.shade800;
      default:
        return const Color(0xFF00A884);
    }
  }

  @override
  Widget build(BuildContext context) {
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+|www\.[^\s]+)', caseSensitive: false);

    // Filter media
    final mediaMessages = _messages.where((m) {
      final u = m.mediaUrl?.toLowerCase() ?? '';
      return (m.mediaType == 'IMAGE' ||
              m.mediaType == 'VIDEO' ||
              u.contains('.jpg') ||
              u.contains('.jpeg') ||
              u.contains('.png') ||
              u.contains('.mp4') ||
              u.contains('.mov') ||
              u.contains('.webp')) &&
          m.mediaType != 'STICKER';
    }).toList();

    // Filter docs
    final docMessages = _messages.where((m) {
      final u = m.mediaUrl?.toLowerCase() ?? '';
      return m.mediaType == 'DOCUMENT' ||
          m.mediaType == 'FILE' ||
          RegExp(r'\.(pdf|docx?|xlsx?|pptx?|txt|zip|rar|apk|csv)($|\?)', caseSensitive: false).hasMatch(u);
    }).toList();

    // Filter links
    final linkMessages = _messages.where((m) => urlRegex.hasMatch(m.content)).toList();

    // Filter audio
    final audioMessages = _messages.where((m) {
      final u = m.mediaUrl?.toLowerCase() ?? '';
      return m.mediaType == 'AUDIO' ||
          m.mediaType == 'VOICE' ||
          u.contains('.mp3') ||
          u.contains('.m4a') ||
          u.contains('.aac') ||
          u.contains('.wav') ||
          u.contains('.ogg');
    }).toList();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Text(
                'Media, links and docs',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          backgroundColor: AppTheme.surfaceColor,
          bottom: const TabBar(
            indicatorColor: Color(0xFF00A884),
            labelColor: Color(0xFF00A884),
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: 'Media'),
              Tab(text: 'Docs'),
              Tab(text: 'Links'),
              Tab(text: 'Audio'),
            ],
          ),
        ),
        backgroundColor: AppTheme.backgroundColor,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
            : TabBarView(
                physics: const BouncingScrollPhysics(),
                children: [
                  // 1. Media Grid (Photos & Videos)
                  mediaMessages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_library_outlined, size: 56, color: AppTheme.textSecondary),
                              const SizedBox(height: 12),
                              Text('No media shared yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                            ],
                          ),
                        )
                      : GridView.builder(
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          padding: const EdgeInsets.all(4),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 3,
                            mainAxisSpacing: 3,
                          ),
                          itemCount: mediaMessages.length,
                          itemBuilder: (context, index) {
                            final msg = mediaMessages[index];
                            final fullUrl = ApiService.getMediaUrl(msg.mediaUrl!);
                            final isVideo = msg.mediaType == 'VIDEO' ||
                                (msg.mediaUrl != null && (msg.mediaUrl!.contains('.mp4') || msg.mediaUrl!.contains('.mov')));

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FullScreenImageView(
                                      imageUrl: fullUrl,
                                      isChatMedia: true,
                                      senderName: msg.sender?['username'] ?? msg.sender?['name'] ?? 'Media',
                                      timestamp: msg.createdAt,
                                      message: msg,
                                    ),
                                  ),
                                );
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: fullUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(color: Colors.white10),
                                    errorWidget: (context, url, error) => Container(
                                      color: Colors.white10,
                                      child: const Icon(Icons.broken_image, color: Colors.grey),
                                    ),
                                  ),
                                  if (isVideo)
                                    Positioned(
                                      left: 6,
                                      bottom: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.videocam, color: Colors.white, size: 14),
                                            SizedBox(width: 4),
                                            Text('VIDEO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),

                  // 2. Docs List
                  docMessages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.description_outlined, size: 56, color: AppTheme.textSecondary),
                              const SizedBox(height: 12),
                              Text('No documents shared yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          padding: const EdgeInsets.all(12),
                          itemCount: docMessages.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, index) {
                            final msg = docMessages[index];
                            final ext = _getFileExtension(msg.mediaUrl, msg.content);
                            final color = _getExtensionColor(ext);
                            final name = msg.content.trim().isNotEmpty
                                ? msg.content.trim()
                                : (msg.mediaUrl != null ? msg.mediaUrl!.split('/').last : 'Document.$ext');

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: color.withOpacity(0.3)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  ext,
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Row(
                                children: [
                                  Text(
                                    msg.createdAt != null
                                        ? DateFormat('dd/MM/yyyy • hh:mm a').format(msg.createdAt!)
                                        : 'Recent',
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.download_rounded, color: Color(0xFF00A884)),
                              onTap: () async {
                                if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
                                  final fullUrl = ApiService.getMediaUrl(msg.mediaUrl!);
                                  final uri = Uri.tryParse(fullUrl);
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                }
                              },
                            );
                          },
                        ),

                  // 3. Links List
                  linkMessages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.link_outlined, size: 56, color: AppTheme.textSecondary),
                              const SizedBox(height: 12),
                              Text('No links shared yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          padding: const EdgeInsets.all(12),
                          itemCount: linkMessages.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, index) {
                            final msg = linkMessages[index];
                            final match = urlRegex.firstMatch(msg.content);
                            final linkUrl = match != null ? match.group(0)! : msg.content;
                            final effectiveUrl = linkUrl.startsWith('http') ? linkUrl : 'https://$linkUrl';
                            final domain = Uri.tryParse(effectiveUrl)?.host ?? 'Web Link';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A884).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.link, color: Color(0xFF00A884), size: 24),
                              ),
                              title: Text(
                                domain,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    msg.content,
                                    style: const TextStyle(color: Color(0xFF53BDEB), fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    msg.createdAt != null
                                        ? DateFormat('dd/MM/yyyy • hh:mm a').format(msg.createdAt!)
                                        : '',
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.open_in_new, color: Colors.white38, size: 20),
                              onTap: () async {
                                final uri = Uri.tryParse(effectiveUrl);
                                if (uri != null && await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                            );
                          },
                        ),

                  // 4. Audio List
                  audioMessages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.audiotrack_outlined, size: 56, color: AppTheme.textSecondary),
                              const SizedBox(height: 12),
                              Text('No audio shared yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                          padding: const EdgeInsets.all(12),
                          itemCount: audioMessages.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, index) {
                            final msg = audioMessages[index];
                            final senderName = msg.sender?['username'] ?? msg.sender?['name'] ?? 'Audio message';

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A884).withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF00A884), size: 28),
                              ),
                              title: Text(
                                senderName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              subtitle: Row(
                                children: [
                                  const Icon(Icons.mic, size: 14, color: Color(0xFF00A884)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Voice recording • ${msg.createdAt != null ? DateFormat('dd/MM/yyyy • hh:mm a').format(msg.createdAt!) : ''}',
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.volume_up, color: Colors.white38, size: 20),
                              onTap: () async {
                                if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
                                  final fullUrl = ApiService.getMediaUrl(msg.mediaUrl!);
                                  final uri = Uri.tryParse(fullUrl);
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                }
                              },
                            );
                          },
                        ),
                ],
              ),
      ),
    );
  }
}
