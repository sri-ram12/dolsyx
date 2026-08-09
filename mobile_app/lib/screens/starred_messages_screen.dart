import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/message.dart';
import '../widgets/message_bubble.dart';

class StarredMessagesScreen extends StatelessWidget {
  final List<Message> starredMessages;

  const StarredMessagesScreen({super.key, required this.starredMessages});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Starred Messages'),
      ),
      body: starredMessages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_border, size: 64, color: AppTheme.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    'No Starred Messages',
                    style: TextStyle(fontSize: 18, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap & hold any message to pin or star it',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: starredMessages.length,
              itemBuilder: (context, index) {
                final message = starredMessages[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Card(
                    color: AppTheme.surfaceColor,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: MessageBubble(
                        message: message,
                        isMe: true,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
