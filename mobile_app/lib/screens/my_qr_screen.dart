import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class MyQrScreen extends StatelessWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    final userId = user['id'] ?? user['_id'];
    final username = user['username'] ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My QR Code'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(username, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 8),
              const Text('Scan to chat', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              QrImageView(
                data: '{"id":"$userId","username":"$username","email":"${user['email'] ?? ''}","avatarUrl":"${user['avatarUrl'] ?? ''}"}',
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
