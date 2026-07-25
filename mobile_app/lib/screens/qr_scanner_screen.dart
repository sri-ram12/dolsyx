import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import '../services/chat_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'chat_room_screen.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final ChatService _chatService = ChatService();
  bool _isProcessing = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      String scannedUserId = barcodes.first.rawValue!.trim();
      print("SCANNED RAW VALUE: $scannedUserId");

      if (scannedUserId.startsWith('dolsyx://user/')) {
        scannedUserId = scannedUserId.replaceFirst('dolsyx://user/', '');
      } else {
        // Sometimes QR codes store JSON strings. Let's try parsing it just in case.
        try {
          final Map<String, dynamic> parsed = jsonDecode(scannedUserId);
          if (parsed.containsKey('id')) scannedUserId = parsed['id'];
          else if (parsed.containsKey('_id')) scannedUserId = parsed['_id'];
          else if (parsed.containsKey('userId')) scannedUserId = parsed['userId'];
        } catch (e) {
          // Not a JSON string, assume it's the raw ID
        }
      }
      
      print("SCANNED EXTRACTED ID: $scannedUserId");

      setState(() => _isProcessing = true);
      
      try {
        final targetUser = await ApiService().getUserById(scannedUserId);
        if (targetUser != null && mounted) {
          setState(() => _isProcessing = false);
          _showUserDialog(targetUser, scannedUserId);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not found')));
            setState(() => _isProcessing = false);
          }
        }
      } catch (e) {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  void _showUserDialog(Map<String, dynamic> user, String userId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final String name = user['username'] ?? 'User';
        final String email = user['email'] ?? '';
        final String? avatarUrl = user['avatarUrl'];

        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              (avatarUrl == null || avatarUrl.isEmpty)
                  ? ColorAvatar(name: name, radius: 40, fontSize: 32)
                  : CircleAvatar(
                      radius: 40,
                      backgroundColor: AppTheme.surfaceColor,
                      backgroundImage: avatarUrl.startsWith('http')
                          ? NetworkImage(avatarUrl)
                          : NetworkImage('https://dolsyx-app.onrender.com$avatarUrl'),
                      onBackgroundImageError: (exception, stackTrace) {
                        print("Failed to load avatar image: $exception");
                      },
                    ),
              const SizedBox(height: 16),
              Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              Text(email, style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _isProcessing = false);
                    },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _startCommunication(userId, name);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                    child: const Text('Communicate', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _startCommunication(String userId, String chatName) async {
    setState(() => _isProcessing = true);
    try {
      final chat = await _chatService.createDirectChat(userId);
      if (mounted && chat != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(
              conversationId: chat.id,
              chatName: chatName,
              remoteUserId: userId,
            ),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to start chat')));
          setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: MobileScannerController(
              formats: const [BarcodeFormat.qrCode],
              detectionSpeed: DetectionSpeed.normal,
            ),
            onDetect: _onDetect,
          ),
          if (_isProcessing)
            Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            ),
        ],
      ),
    );
  }
}
