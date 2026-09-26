import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/backup_service.dart';

/// WhatsApp-grade End-to-End Encrypted Chat Backup Screen (Phase 11)
/// Features AES-256-GCM / PBKDF2 cryptography, 64-digit key generator,
/// and instant cloud & local chat restoration.
class ChatBackupScreen extends StatefulWidget {
  const ChatBackupScreen({super.key});

  @override
  State<ChatBackupScreen> createState() => _ChatBackupScreenState();
}

class _ChatBackupScreenState extends State<ChatBackupScreen> {
  final BackupService _backupService = BackupService();

  bool _isLoading = true;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  Map<String, dynamic> _status = {};

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    final status = await _backupService.getBackupStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _isLoading = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showBackupCredentialDialog() {
    final passwordCtrl = TextEditingController();
    bool use64Digit = false;
    String generatedKey = _backupService.generate64DigitKey();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 24,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A884).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_rounded, color: Color(0xFF00A884), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'End-to-End Encrypted Backup',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your backup will be encrypted with AES-256-GCM. Neither DOLSYX nor anyone else can read your chats.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Password'),
                        selected: !use64Digit,
                        onSelected: (val) => setModalState(() => use64Digit = !val),
                        selectedColor: const Color(0xFF00A884),
                        labelStyle: TextStyle(color: !use64Digit ? Colors.white : Colors.white70),
                      ),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('64-digit key'),
                        selected: use64Digit,
                        onSelected: (val) => setModalState(() => use64Digit = val),
                        selectedColor: const Color(0xFF00A884),
                        labelStyle: TextStyle(color: use64Digit ? Colors.white : Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (use64Digit) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111B21),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Your 64-digit encryption key:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, color: Color(0xFF00A884), size: 18),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: generatedKey));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Copied 64-digit key to clipboard!')),
                                  );
                                },
                              ),
                            ],
                          ),
                          Text(
                            generatedKey,
                            style: const TextStyle(
                              color: Color(0xFF00A884),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Create a password (min. 6 chars)',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF111B21),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A884),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: () {
                        final cred = use64Digit ? generatedKey : passwordCtrl.text.trim();
                        if (cred.length < 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Password must be at least 6 characters')),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        _performBackup(cred, use64Digit);
                      },
                      child: const Text('Encrypt and Back Up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _performBackup(String keyOrPass, bool is64Digit) async {
    setState(() => _isBackingUp = true);
    final result = await _backupService.createEncryptedBackup(
      keyOrPassword: keyOrPass,
      is64DigitKey: is64Digit,
    );

    if (mounted) {
      setState(() => _isBackingUp = false);
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Chat backup completed! (${_formatBytes(result['sizeBytes'])})'),
            backgroundColor: const Color(0xFF00A884),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Backup failed: ${result['error']}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      await _loadStatus();
    }
  }

  void _showRestoreDialog() {
    final credCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        title: const Row(
          children: [
            Icon(Icons.restore_rounded, color: Color(0xFF00A884)),
            SizedBox(width: 8),
            Text('Restore Chats', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your 64-digit key or password to decrypt and restore your messages:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: credCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Password or 64-digit key',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF111B21),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884)),
            onPressed: () async {
              final cred = credCtrl.text.trim();
              if (cred.isEmpty) return;
              Navigator.pop(ctx);
              setState(() => _isRestoring = true);

              final res = await _backupService.restoreEncryptedBackup(keyOrPassword: cred);
              if (mounted) {
                setState(() => _isRestoring = false);
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Restored ${res['conversationsRestored']} chats & ${res['messagesRestored']} messages!'),
                      backgroundColor: const Color(0xFF00A884),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Restore failed: ${res['error']}'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text('Restore', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastTime = _status['lastBackupTime'] as DateTime?;
    final lastSize = (_status['lastSizeBytes'] as int?) ?? 0;
    final lastMessages = (_status['lastMessagesCount'] as int?) ?? 0;
    final isE2EE = _status['isE2EEEnabled'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0B141B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2C34),
        title: const Text('Chat backup', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              children: [
                // Top E2EE Lock Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111B21),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF00A884).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A884).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.security_rounded, color: Color(0xFF00A884), size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isE2EE ? 'End-to-end encrypted backup: ON' : 'End-to-end encrypted backup: Ready',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Your chat history and media are secured with AES-256-GCM before uploading.',
                              style: TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Last Backup Metadata Section
                const Text(
                  'LAST BACKUP',
                  style: TextStyle(color: Color(0xFF00A884), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111B21),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Date:', style: TextStyle(color: Colors.white70)),
                          Text(
                            lastTime != null ? DateFormat('EEE, MMM d, yyyy @ hh:mm a').format(lastTime) : 'Never',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Size:', style: TextStyle(color: Colors.white70)),
                          Text(
                            _formatBytes(lastSize),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Messages:', style: TextStyle(color: Colors.white70)),
                          Text(
                            '$lastMessages messages',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Big Green Back Up Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A884),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: _isBackingUp ? null : _showBackupCredentialDialog,
                    child: _isBackingUp
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            'Back Up Now',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Restore Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00A884)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    icon: _isRestoring
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Color(0xFF00A884), strokeWidth: 2),
                          )
                        : const Icon(Icons.restore_rounded, color: Color(0xFF00A884)),
                    label: Text(
                      _isRestoring ? 'Restoring...' : 'Restore from Backup',
                      style: const TextStyle(color: Color(0xFF00A884), fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isRestoring ? null : _showRestoreDialog,
                  ),
                ),

                const SizedBox(height: 28),
                const Divider(color: Color(0xFF222E35)),
                const SizedBox(height: 12),

                // Cloud Backup info
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_done_rounded, color: Color(0xFF00A884)),
                  title: const Text('Back up to DOLSYX Cloud', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Encrypted zero-knowledge copy synced with your account', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.check_circle_rounded, color: Color(0xFF00A884), size: 20),
                ),
              ],
            ),
    );
  }
}
