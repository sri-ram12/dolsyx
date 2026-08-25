import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/message.dart';
import '../widgets/full_screen_image_view.dart';
import '../services/api_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

class MediaGalleryScreen extends StatelessWidget {
  final String title;
  final List<Message> messages;

  const MediaGalleryScreen({
    super.key,
    required this.title,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+|www\.[^\s]+)', caseSensitive: false);
    final mediaMessages = messages.where((m) => m.mediaUrl != null && m.mediaUrl!.trim().isNotEmpty && (m.mediaType == 'IMAGE' || m.mediaType == 'VIDEO' || m.mediaUrl!.contains('.jpg') || m.mediaUrl!.contains('.png') || m.mediaUrl!.contains('.mp4') || m.mediaUrl!.contains('.webp'))).toList();
    final docMessages = messages.where((m) => m.mediaType == 'DOCUMENT' || m.mediaType == 'FILE' || (m.mediaUrl != null && RegExp(r'\.(pdf|docx?|xlsx?|pptx?|txt|zip|rar|apk|csv)($|\?)', caseSensitive: false).hasMatch(m.mediaUrl!))).toList();
    final linkMessages = messages.where((m) => urlRegex.hasMatch(m.content)).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('$title Media'),
          backgroundColor: AppTheme.surfaceColor,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Media'),
              Tab(text: 'Docs'),
              Tab(text: 'Links'),
            ],
          ),
        ),
        backgroundColor: AppTheme.backgroundColor,
        body: TabBarView(
          children: [
            // Media Grid
            mediaMessages.isEmpty
                ? Center(child: Text('No media shared yet', style: TextStyle(color: AppTheme.textSecondary)))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: mediaMessages.length,
                    itemBuilder: (context, index) {
                      final msg = mediaMessages[index];
                      final fullUrl = ApiService.getMediaUrl(msg.mediaUrl!);
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => FullScreenImageView(imageUrl: fullUrl)),
                          );
                        },
                        child: CachedNetworkImage(
                          imageUrl: fullUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: Colors.black12),
                          errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      );
                    },
                  ),

            // Docs List
            docMessages.isEmpty
                ? Center(child: Text('No documents shared yet', style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docMessages.length,
                    itemBuilder: (context, index) {
                      final msg = docMessages[index];
                      final name = msg.content.trim().isNotEmpty
                          ? msg.content.trim()
                          : (msg.mediaUrl != null ? msg.mediaUrl!.split('/').last : 'Document');
                      return Card(
                        color: AppTheme.surfaceColor,
                        child: ListTile(
                          leading: const Icon(Icons.insert_drive_file, color: Colors.blueAccent),
                          title: Text(name, style: TextStyle(color: AppTheme.textPrimary)),
                          subtitle: Text(msg.createdAt.toString().split('.')[0], style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          onTap: () async {
                            if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
                              final fullUrl = ApiService.getMediaUrl(msg.mediaUrl!);
                              final uri = Uri.tryParse(fullUrl);
                              if (uri != null && await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),

            // Links List
            linkMessages.isEmpty
                ? Center(child: Text('No links shared yet', style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: linkMessages.length,
                    itemBuilder: (context, index) {
                      final msg = linkMessages[index];
                      final match = urlRegex.firstMatch(msg.content);
                      final linkUrl = match != null ? match.group(0)! : msg.content;
                      final effectiveUrl = linkUrl.startsWith('http') ? linkUrl : 'https://$linkUrl';
                      return Card(
                        color: AppTheme.surfaceColor,
                        child: ListTile(
                          leading: const Icon(Icons.link, color: Colors.green),
                          title: Text(msg.content, style: const TextStyle(color: Colors.lightBlueAccent, decoration: TextDecoration.underline)),
                          subtitle: Text(msg.createdAt.toString().split('.')[0], style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                          onTap: () async {
                            final uri = Uri.tryParse(effectiveUrl);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
