import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../services/local_database_service.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/color_avatar.dart';
import 'chat_room_screen.dart';
import 'secret_lock_settings_screen.dart';
import '../utils/e2ee/crypto_service.dart';

/// WhatsApp-grade Biometric Chat Lock & Hidden Vault (Phase 14)
///
/// Features:
/// 1. Biometric (Face ID / Fingerprint / Device PIN) hardware authentication via local_auth.
/// 2. Instant auto-lock when app is minimized, backgrounded, or switched.
/// 3. Direct synchronization with SQLite local_conversations (isLocked column).
/// 4. Secret code concealment and hidden vault privacy protection.
class LockedChatsScreen extends StatefulWidget {
  final List<Chat>? initialLockedChats;
  final VoidCallback? onRefresh;
  final VoidCallback? onChatsUpdated;

  const LockedChatsScreen({
    super.key,
    this.initialLockedChats,
    this.onRefresh,
    this.onChatsUpdated,
  });

  @override
  State<LockedChatsScreen> createState() => _LockedChatsScreenState();
}

class _LockedChatsScreenState extends State<LockedChatsScreen> with WidgetsBindingObserver {
  final ChatService _chatService = ChatService();
  final LocalAuthentication _localAuth = LocalAuthentication();
  late List<Chat> _lockedChats;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockedChats = List.from(widget.initialLockedChats ?? []);
    _authenticateAndLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // WhatsApp auto-relock behavior: immediately re-lock vault when app is backgrounded
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (mounted && _isAuthenticated) {
        setState(() => _isAuthenticated = false);
      }
    }
  }

  Future<void> _authenticateAndLoad() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;

    try {
      final isSupported = await _localAuth.isDeviceSupported() || await _localAuth.canCheckBiometrics;
      if (!isSupported) {
        // Fallback if device has no biometric hardware/lock
        if (mounted) {
          setState(() {
            _isAuthenticated = true;
            _isAuthenticating = false;
          });
          _fetchLockedChats();
        }
        return;
      }

      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access Locked Chats',
      );

      if (mounted) {
        setState(() {
          _isAuthenticated = didAuth;
          _isAuthenticating = false;
        });

        if (didAuth) {
          _fetchLockedChats();
        }
      }
    } catch (e) {
      debugPrint('[LockedChats] Biometric authentication error: $e');
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isAuthenticating = false;
        });
      }
    }
  }

  Future<void> _fetchLockedChats() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final lockedIds = (prefs.getStringList('locked_chat_ids') ?? []).toSet();

    var allChats = await _chatService.getCachedChats();
    if (allChats.isEmpty) {
      try {
        allChats = await _chatService.getChats();
      } catch (_) {}
    } else {
      _chatService.getChats().then((remote) {
        if (mounted && remote.isNotEmpty) {
          for (var c in remote) {
            c.isLocked = lockedIds.contains(c.id);
          }
          setState(() {
            _lockedChats = remote.where((c) => c.isLocked).toList();
          });
        }
      }).catchError((_) {});
    }

    for (var c in allChats) {
      c.isLocked = lockedIds.contains(c.id);
    }

    if (mounted) {
      setState(() {
        _lockedChats = allChats.where((c) => c.isLocked).toList();
        _isLoading = false;
      });
      widget.onRefresh?.call();
      widget.onChatsUpdated?.call();
    }
  }

  String _getChatName(Chat chat) {
    if (chat.isGroup && chat.name != null) return chat.name!;
    if (chat.participants != null && chat.participants!.isNotEmpty) {
      final currentUserId = Provider.of<AuthProvider>(context, listen: false).user?['id'] ??
          Provider.of<AuthProvider>(context, listen: false).user?['_id'];
      final other = chat.participants!.firstWhere(
        (p) => p['user'] != null && (p['user']['id'] != currentUserId && p['user']['_id'] != currentUserId),
        orElse: () => null,
      );
      if (other != null && other['user']['username'] != null) {
        return other['user']['username'];
      }
    }
    return "Locked Chat";
  }

  Future<void> _unlockChat(Chat chat) async {
    final chatId = chat.id;
    setState(() {
      chat.isLocked = false;
      _lockedChats.removeWhere((c) => c.id == chatId);
    });

    final prefs = await SharedPreferences.getInstance();
    final lockedIds = (prefs.getStringList('locked_chat_ids') ?? []).toSet();
    lockedIds.remove(chatId);
    await prefs.setStringList('locked_chat_ids', lockedIds.toList());

    // Synchronize both SQLite WAL and Backend
    await LocalDatabaseService().setChatLocked(chatId, false);
    _chatService.updateChatSettings(chatId, {'isLocked': false}).catchError((_) => false);

    widget.onChatsUpdated?.call();
    widget.onRefresh?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unlocked "${_getChatName(chat)}" and restored to main chats')),
      );
    }
  }

  void _showLockedChatOptions(Chat chat) {
    final name = _getChatName(chat);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            title: Text('Open $name', style: const TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(
                    conversationId: chat.id,
                    chatName: name,
                    avatarUrl: chat.avatarUrl,
                  ),
                ),
              ).then((_) => _fetchLockedChats());
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_open, color: Color(0xFF00A884)),
            title: const Text('Unlock & Remove from Locked Chats',
                style: TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(ctx);
              _unlockChat(chat);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildSubtitle(Chat chat) {
    if (chat.lastMessage == null) {
      return const Text("No messages", style: TextStyle(color: Colors.white60, fontSize: 13));
    }
    final msg = chat.lastMessage!;
    final mType = (msg['mediaType'] ?? '').toString();
    if (mType == 'IMAGE') return const Text("📷 Photo", style: TextStyle(color: Colors.white60, fontSize: 13));
    if (mType == 'VIDEO') return const Text("🎬 Video", style: TextStyle(color: Colors.white60, fontSize: 13));
    if (mType == 'AUDIO') return const Text("🎵 Voice message", style: TextStyle(color: Colors.white60, fontSize: 13));
    if (mType == 'FILE') return const Text("📎 Document", style: TextStyle(color: Colors.white60, fontSize: 13));
    if (mType == 'CALL_LOG') return const Text("📞 Call", style: TextStyle(color: Colors.white60, fontSize: 13));

    final raw = (msg['content'] ?? '').toString().trim();
    if (raw.isEmpty) return const Text("Sent a message", style: TextStyle(color: Colors.white60, fontSize: 13));
    if (raw.startsWith('{') && (raw.contains('ciphertext') || raw.contains('e2ee'))) {
      return FutureBuilder<String>(
        future: CryptoService.instance.decryptIncomingContent(
          content: raw,
          senderUserId: (msg['senderId'] ?? '').toString(),
          conversationId: chat.id,
        ),
        builder: (context, snapshot) {
          final text = snapshot.data;
          if (text != null && text.isNotEmpty && text != raw && !text.contains('ciphertext')) {
            return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 13));
          }
          return const Text("Message", style: TextStyle(color: Colors.white60, fontSize: 13));
        },
      );
    }
    if (raw.contains(':') && raw.split(':').length == 3) {
      return const Text("Message", style: TextStyle(color: Colors.white60, fontSize: 13));
    }
    return Text(raw, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 13));
  }

  Widget _buildLockedChallengeView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00A884).withValues(alpha: 0.15),
                border: Border.all(color: const Color(0xFF00A884).withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Icon(Icons.lock_rounded, size: 72, color: Color(0xFF00A884)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Locked chats',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Use your fingerprint, face, or device PIN to view your locked chats vault.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _authenticateAndLoad,
              icon: const Icon(Icons.fingerprint_rounded, size: 22),
              label: const Text('Unlock Vault', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A884),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locked chats', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.surfaceColor,
        actions: [
          if (_isAuthenticated)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Lock settings',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SecretLockSettingsScreen()),
                ).then((_) => _fetchLockedChats());
              },
            ),
        ],
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: !_isAuthenticated
          ? _buildLockedChallengeView()
          : _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
              : _lockedChats.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00A884).withValues(alpha: 0.12),
                            ),
                            child: const Icon(Icons.lock_rounded, size: 64, color: Color(0xFF00A884)),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'No locked chats',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              'Chats you lock will appear here. You can lock any chat from its chat options menu.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _lockedChats.length,
                      separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, index) {
                        final chat = _lockedChats[index];
                        final name = _getChatName(chat);

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: chat.avatarUrl != null
                              ? CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AppTheme.surfaceColor,
                                  backgroundImage: CachedNetworkImageProvider(
                                    chat.avatarUrl!.startsWith('http')
                                        ? chat.avatarUrl!
                                        : 'https://dolsyx-app.onrender.com${chat.avatarUrl!}',
                                  ),
                                )
                              : ColorAvatar(name: name, radius: 24),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: _buildSubtitle(chat),
                          trailing: TextButton.icon(
                            icon: const Icon(Icons.lock_open, color: Color(0xFF00A884), size: 18),
                            label: const Text('Unlock', style: TextStyle(color: Color(0xFF00A884), fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () => _unlockChat(chat),
                          ),
                          onLongPress: () => _showLockedChatOptions(chat),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatRoomScreen(
                                  conversationId: chat.id,
                                  chatName: name,
                                  avatarUrl: chat.avatarUrl,
                                ),
                              ),
                            ).then((_) => _fetchLockedChats());
                          },
                        );
                      },
                    ),
    );
  }
}
