import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/message.dart';
import '../widgets/full_screen_image_view.dart';
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
    final mediaMessages = messages.where((m) => m.mediaUrl != null && m.mediaUrl!.isNotEmpty).toList();
    final docMessages = messages.where((m) => m.mediaType == 'DOCUMENT' || m.mediaType == 'FILE').toList();
    final linkMessages = messages.where((m) => m.content.contains('http://') || m.content.contains('https://')).toList();

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
                      final fullUrl = msg.mediaUrl!.startsWith('http') ? msg.mediaUrl! : 'https://dolsyx-app.onrender.com${msg.mediaUrl!}';
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => FullScreenImageView(imageUrl: fullUrl)),
                          );
                        },
                        child: Image.network(fullUrl, fit: BoxFit.cover),
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
                      return Card(
                        color: AppTheme.surfaceColor,
                        child: ListTile(
                          leading: const Icon(Icons.insert_drive_file, color: Colors.blueAccent),
                          title: Text(msg.content.isNotEmpty ? msg.content : 'Document Attachment', style: TextStyle(color: AppTheme.textPrimary)),
                          subtitle: Text(msg.createdAt.toString().split('.')[0], style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
                      return Card(
                        color: AppTheme.surfaceColor,
                        child: ListTile(
                          leading: const Icon(Icons.link, color: Colors.green),
                          title: Text(msg.content, style: const TextStyle(color: Colors.lightBlueAccent, decoration: TextDecoration.underline)),
                          onTap: () async {
                            final uri = Uri.tryParse(msg.content);
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
