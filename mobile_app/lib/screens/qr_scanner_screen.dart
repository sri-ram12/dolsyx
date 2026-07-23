import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
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
      final String scannedUserId = barcodes.first.rawValue!;
      setState(() => _isProcessing = true);
      
      try {
        final chat = await _chatService.createDirectChat(scannedUserId);
        if (mounted && chat != null) {
          String chatName = 'Scanned User';
          if (chat.participants != null && chat.participants!.isNotEmpty) {
            final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ?? Provider.of<AuthProvider>(context, listen: false).user?['_id'];
            final otherParticipant = chat.participants!.firstWhere(
              (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
              orElse: () => null,
            );
            if (otherParticipant != null && otherParticipant['user']['username'] != null) {
              chatName = otherParticipant['user']['username'];
            }
          }
          
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ChatRoomScreen(
                  conversationId: chat.id,
                  chatName: chatName,
                  remoteUserId: scannedUserId,
                ),
              ),
            );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to open chat with this QR code')));
            setState(() => _isProcessing = false);
          }
        }
      } catch (e) {
        if (mounted) setState(() => _isProcessing = false);
      }
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
            onDetect: _onDetect,
          ),
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            ),
        ],
      ),
    );
  }
}
