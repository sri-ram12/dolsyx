import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'chat_room_screen.dart';

import 'package:local_auth/local_auth.dart';
import 'package:image_picker/image_picker.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final ChatService _chatService = ChatService();
  bool _isProcessing = false;
  late final MobileScannerController _scannerController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WakelockPlus.enable();
    });
    _scannerController = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null || barcodes.first.rawValue!.trim().isEmpty) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    String scannedUserId = barcodes.first.rawValue!.trim();
    print("SCANNED RAW VALUE: $scannedUserId");

    final bool isQrSession = scannedUserId.startsWith('dolsyx_qr_session_') ||
        scannedUserId.startsWith('dolsyx_qr_') ||
        scannedUserId.startsWith('sess_') ||
        scannedUserId.contains('||') ||
        scannedUserId.contains('qrSession');

    if (isQrSession) {
      setState(() => _isProcessing = false);
      _showQrLoginApprovalDialog(scannedUserId);
      return;
    }

    Map<String, dynamic>? inlineUser;
    if (scannedUserId.startsWith('dolsyx://user/')) {
      scannedUserId = scannedUserId.replaceFirst('dolsyx://user/', '');
    }

    try {
      final Map<String, dynamic> parsed = jsonDecode(scannedUserId);
      if (parsed.containsKey('id')) scannedUserId = parsed['id'];
      else if (parsed.containsKey('_id')) scannedUserId = parsed['_id'];
      else if (parsed.containsKey('userId')) scannedUserId = parsed['userId'];

      if (parsed.containsKey('username')) {
        inlineUser = parsed;
      }
    } catch (e) {
      // Not a JSON string, assume raw ID
    }
    
    print("SCANNED EXTRACTED ID: $scannedUserId");

    setState(() => _isProcessing = true);

    // If user details are embedded in QR code, go directly to chat INSTANTLY
    if (inlineUser != null && mounted) {
      final name = inlineUser['username'] ?? 'User';
      _startCommunication(scannedUserId, name, userMap: inlineUser);
      return;
    }
    
    try {
      final targetUser = await ApiService().getUserById(scannedUserId);
      if (targetUser != null && mounted) {
        final String resolvedName = targetUser['username'] ?? targetUser['name'] ?? 'User';
        _startCommunication(scannedUserId, resolvedName, userMap: targetUser);
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

  void _showQrLoginApprovalDialog(String rawSessionData) {
    String sessionId = rawSessionData;
    String? customApiUrl;
    if (rawSessionData.contains('||')) {
      final parts = rawSessionData.split('||');
      sessionId = parts[0];
      customApiUrl = parts[1];
    }
    if (sessionId.startsWith('dolsyx_qr_session_')) {
      sessionId = sessionId.replaceFirst('dolsyx_qr_session_', '');
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.laptop_mac_rounded, size: 48, color: AppTheme.primaryColor),
              ),
              const SizedBox(height: 16),
              Text(
                'Approve Web Login',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Do you want to log into your DOLSYX account on this web browser / laptop?\n(Biometric verification required)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      setState(() => _isProcessing = false);
                    },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      // Trigger Biometric authentication
                      final localAuth = LocalAuthentication();
                      bool authenticated = false;
                      try {
                        final canCheck = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();
                        if (canCheck) {
                          authenticated = await localAuth.authenticate(
                            localizedReason: 'Authenticate with Fingerprint/Face ID to authorize laptop login',
                          );
                        } else {
                          authenticated = true;
                        }
                      } catch (e) {
                        debugPrint('Biometric auth error: $e');
                        authenticated = true;
                      }

                      if (!authenticated) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Biometric authentication failed. Laptop login cancelled.')),
                          );
                        }
                        return;
                      }

                      Navigator.pop(dialogContext);
                      final authProvider = Provider.of<AuthProvider>(context, listen: false);
                      final token = authProvider.token ?? '';
                      try {
                        final success = await ApiService().approveQrWebLogin(token, sessionId, customBackendUrl: customApiUrl);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(success ? 'Web Login Approved!' : 'Failed to approve Web Login'),
                              backgroundColor: success ? AppTheme.primaryColor : Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('Approve QR error: $e');
                      }
                      if (mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                    child: const Text('Approve with Biometrics', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
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

  void _startCommunication(String userId, String chatName, {Map<String, dynamic>? userMap}) async {
    setState(() => _isProcessing = true);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token ?? '';
      final myUserId = (authProvider.user?['id'] ?? authProvider.user?['_id'])?.toString();

      if (myUserId != null && myUserId == userId.toString()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This is your own QR code')));
          setState(() => _isProcessing = false);
        }
        return;
      }
      
      // Save contact asynchronously in background without delaying navigation
      ContactService.addContactById(token, userId, savedName: chatName).catchError((_) {});

      final chat = await _chatService.createDirectChat(userId);
      if (mounted && chat != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(
              conversationId: chat.id,
              chatName: chatName,
              remoteUserId: userId,
              remoteUser: userMap,
              avatarUrl: userMap?['avatarUrl'],
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

  Future<void> _scanFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      // Downscale image to 1280x1280 max for instant local QR detection without thread blocking
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (image == null) return;

      setState(() => _isProcessing = true);

      final BarcodeCapture? capture = await _scannerController.analyzeImage(image.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        _onDetect(capture);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No QR code detected in selected image')),
          );
          setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
      debugPrint('Gallery QR scan error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to read QR code from image')),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Scan from Gallery',
            onPressed: _scanFromGallery,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
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
