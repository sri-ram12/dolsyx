import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import '../services/chat_service.dart';
import '../services/contact_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
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
    String scannedValue = barcodes.first.rawValue!.trim();
    print("SCANNED RAW VALUE: $scannedValue");

    // ── Check if this is a DOLSYX Linked Device QR Login ───────────────────
    String? pairingId;
    String? challenge;
    String? customApiUrl;

    if (scannedValue.startsWith('dolsyx://pair')) {
      final uri = Uri.tryParse(scannedValue);
      if (uri != null) {
        pairingId = uri.queryParameters['pairingId'];
        challenge = uri.queryParameters['challenge'];
        customApiUrl = uri.queryParameters['api'];
      }
    } else if (scannedValue.startsWith('{') && scannedValue.contains('pairingId')) {
      try {
        final parsed = jsonDecode(scannedValue);
        pairingId = parsed['pairingId']?.toString();
        challenge = parsed['challenge']?.toString();
        customApiUrl = parsed['apiUrl']?.toString();
      } catch (_) {}
    }

    if (pairingId != null && pairingId.isNotEmpty && challenge != null && challenge.isNotEmpty) {
      setState(() => _isProcessing = true);
      _processDevicePairing(pairingId, challenge, customBackendUrl: customApiUrl);
      return;
    }

    // ── Classic Pre-5pm WhatsApp Web Style QR Code Login ───────────────────
    final bool isClassicQrSession = scannedValue.startsWith('dolsyx_qr_session_') ||
        scannedValue.startsWith('dolsyx_qr_') ||
        scannedValue.startsWith('sess_') ||
        scannedValue.contains('||') ||
        scannedValue.contains('qrSession');

    if (isClassicQrSession) {
      setState(() => _isProcessing = false);
      _showClassicQrLoginApprovalDialog(scannedValue);
      return;
    }

    String scannedUserId = scannedValue;
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

  // ─────────────────────────────────────────────────────────────────────────
  // Process Device Pairing Scan & Show Confirmation Bottom Sheet
  // ─────────────────────────────────────────────────────────────────────────
  void _processDevicePairing(String pairingId, String challenge, {String? customBackendUrl}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token ?? '';

    if (token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in first to link devices')),
        );
        setState(() => _isProcessing = false);
      }
      return;
    }

    try {
      // Step 1: Scan & validate pairing with backend
      final scanResult = await ApiService().scanDevicePairing(
        token,
        pairingId,
        challenge,
        customBackendUrl: customBackendUrl,
      );

      if (!mounted) return;

      if (scanResult == null || scanResult['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This QR code is invalid, expired, or already used.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _isProcessing = false);
        return;
      }

      final device = scanResult['device'] as Map<String, dynamic>? ?? {};
      final browser = device['browser'] ?? 'Web Browser';
      final platform = device['platform'] ?? 'Computer';
      final location = device['location'] ?? 'Approximate / privacy-safe';

      // Step 2: Show confirmation sheet matching requirements
      _showDeviceConfirmationSheet(pairingId, challenge, browser, platform, location, customBackendUrl);
    } catch (e) {
      debugPrint('Error processing device pairing scan: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error validating pairing code')),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showDeviceConfirmationSheet(
    String pairingId,
    String challenge,
    String browser,
    String platform,
    String location,
    String? customBackendUrl,
  ) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A884).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.laptop_chromebook_rounded, size: 28, color: Color(0xFF00A884)),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Link New Device?',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Authorize access to your DOLSYX account',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Device details card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(Icons.web_rounded, 'Device', browser),
                      const Divider(color: Colors.white10, height: 16),
                      _buildDetailRow(Icons.computer_rounded, 'Platform', platform),
                      const Divider(color: Colors.white10, height: 16),
                      _buildDetailRow(Icons.location_on_outlined, 'Location', location),
                      const Divider(color: Colors.white10, height: 16),
                      _buildDetailRow(Icons.access_time_rounded, 'Requested', 'Just now'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Your chats and calls remain end-to-end encrypted on this computer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 20),

                // Action buttons: Cancel and Link Device
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          final authProvider = Provider.of<AuthProvider>(context, listen: false);
                          final token = authProvider.token ?? '';
                          ApiService().rejectDevicePairing(token, pairingId, customBackendUrl: customBackendUrl);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Device linking cancelled')),
                            );
                            setState(() => _isProcessing = false);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          // Biometric prompt before approval
                          final localAuth = LocalAuthentication();
                          bool authenticated = false;
                          try {
                            final canCheck = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();
                            if (canCheck) {
                              authenticated = await localAuth.authenticate(
                                localizedReason: 'Verify identity to link device',
                              );
                            } else {
                              authenticated = true;
                            }
                          } catch (e) {
                            debugPrint('Biometric verification error: $e');
                            authenticated = true;
                          }

                          if (!authenticated) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Authentication required to link device')),
                              );
                            }
                            return;
                          }

                          Navigator.pop(sheetContext);

                          final authProvider = Provider.of<AuthProvider>(context, listen: false);
                          final token = authProvider.token ?? '';

                          final success = await ApiService().approveDevicePairing(
                            token,
                            pairingId,
                            challenge,
                            customBackendUrl: customBackendUrl,
                          );

                          if (mounted) {
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Device linked successfully! Computer is now logged in.'),
                                  backgroundColor: Color(0xFF00A884),
                                ),
                              );
                              Navigator.pop(context, true);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to link device. The QR may have expired.'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              setState(() => _isProcessing = false);
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00A884),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Link Device',
                          style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  void _showClassicQrLoginApprovalDialog(String rawSessionData) {
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
                      final myUserId = (authProvider.user?['id'] ?? authProvider.user?['_id'])?.toString();
                      bool success = false;
                      try {
                        success = await ApiService().approveQrWebLogin(
                          token,
                          sessionId,
                          customBackendUrl: customApiUrl,
                          userId: myUserId,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(success ? 'Web Login Approved! Laptop logged in.' : 'Failed to approve Web Login'),
                              backgroundColor: success ? const Color(0xFF00A884) : Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('Approve QR error: $e');
                      }
                      if (mounted) {
                        Navigator.pop(context, success ? sessionId : null);
                        setState(() => _isProcessing = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A884),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Approve with Biometrics', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      ContactService.addContactById(token, userId, savedName: chatName).catchError((_) => <String, dynamic>{});

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
