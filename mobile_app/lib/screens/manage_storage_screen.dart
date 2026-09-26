import 'package:flutter/material.dart';
import '../services/local_database_service.dart';
import '../widgets/color_avatar.dart';
import 'chat_room_screen.dart';

/// WhatsApp-grade "Manage Storage" Screen (Phase 8)
/// Provides real disk breakdown, >5MB large files filter with multi-delete,
/// per-conversation media analysis, and SQLite auto-vacuum defragmentation.
class ManageStorageScreen extends StatefulWidget {
  const ManageStorageScreen({super.key});

  @override
  State<ManageStorageScreen> createState() => _ManageStorageScreenState();
}

class _ManageStorageScreenState extends State<ManageStorageScreen> {
  final LocalDatabaseService _localDb = LocalDatabaseService();

  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _largeFiles = [];
  List<Map<String, dynamic>> _chatsBreakdown = [];

  // Multi-select for >5MB files
  bool _isSelectionMode = false;
  final Set<String> _selectedFileIds = {};

  @override
  void initState() {
    super.initState();
    _loadStorageData();
  }

  Future<void> _loadStorageData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _localDb.getStorageBreakdown();
      final largeFiles = await _localDb.getLargeMediaItems(minSizeBytes: 5 * 1024 * 1024);
      final chats = await _localDb.getChatsStorageBreakdown();

      if (mounted) {
        setState(() {
          _stats = stats;
          _largeFiles = largeFiles;
          _chatsBreakdown = chats;
          _selectedFileIds.clear();
          _isSelectionMode = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ManageStorage] Error loading stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _cleanCache() async {
    final freed = await _localDb.clearStorageCache();
    await _loadStorageData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Cleaned temporary cache! Freed ${_formatBytes(freed)}'),
          backgroundColor: const Color(0xFF00A884),
        ),
      );
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFileIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete items?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Delete ${_selectedFileIds.length} item(s) from device storage? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete for Me', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final freed = await _localDb.deleteMediaItems(_selectedFileIds.toList(), deleteFullMessage: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ Deleted ${_selectedFileIds.length} items. Reclaimed ${_formatBytes(freed)}!'),
            backgroundColor: const Color(0xFF00A884),
          ),
        );
      }
      await _loadStorageData();
    }
  }

  void _openChatDetail(Map<String, dynamic> chatRow) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatStorageDetailScreen(
          conversationId: chatRow['id'] ?? '',
          chatName: chatRow['name'] ?? 'Chat',
          avatarUrl: chatRow['avatarUrl'],
          totalBytes: (chatRow['total_bytes'] as int?) ?? 0,
          onStorageChanged: _loadStorageData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2C34),
        elevation: 0,
        title: Text(
          _isSelectionMode ? '${_selectedFileIds.length} selected' : 'Manage storage',
          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all_rounded, color: Colors.white),
              tooltip: 'Select all',
              onPressed: () {
                setState(() {
                  if (_selectedFileIds.length == _largeFiles.length) {
                    _selectedFileIds.clear();
                  } else {
                    _selectedFileIds.addAll(_largeFiles.map((e) => e['id'] as String));
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              tooltip: 'Delete selected',
              onPressed: _selectedFileIds.isEmpty ? null : _deleteSelectedFiles,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedFileIds.clear();
                });
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF00A884)),
              tooltip: 'Clean cache & optimize DB',
              onPressed: _cleanCache,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              tooltip: 'Refresh',
              onPressed: _loadStorageData,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
          : RefreshIndicator(
              color: const Color(0xFF00A884),
              backgroundColor: const Color(0xFF1F2C34),
              onRefresh: _loadStorageData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _buildStorageBarHeader(),
                  const Divider(color: Color(0xFF222E35), height: 1),
                  _buildReviewSection(),
                  const Divider(color: Color(0xFF222E35), height: 1),
                  _buildChatsSection(),
                ],
              ),
            ),
    );
  }

  /// Top Storage Bar showing DOLSYX Media vs DB/Cache vs Free
  Widget _buildStorageBarHeader() {
    final mediaBytes = (_stats['mediaBytes'] as int?) ?? 0;
    final dbBytes = (_stats['databaseBytes'] as int?) ?? 0;
    final cacheBytes = (_stats['cacheBytes'] as int?) ?? 0;
    final totalAppBytes = (_stats['totalAppBytes'] as int?) ?? (mediaBytes + dbBytes + cacheBytes);

    // Baseline 64 GB representation for proportion
    const totalSimulatedDisk = 64 * 1024 * 1024 * 1024;
    final mediaFraction = (mediaBytes / totalSimulatedDisk).clamp(0.02, 0.7);
    final appFraction = ((dbBytes + cacheBytes) / totalSimulatedDisk).clamp(0.01, 0.3);

    return Container(
      color: const Color(0xFF111B21),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatBytes(totalAppBytes),
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  const Text('Used by DOLSYX', style: TextStyle(color: Colors.white60, fontSize: 13)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _cleanCache,
                icon: const Icon(Icons.auto_delete_outlined, size: 16),
                label: const Text('Clean Cache', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A884).withOpacity(0.15),
                  foregroundColor: const Color(0xFF00A884),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Storage Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: (mediaFraction * 1000).toInt(),
                    child: Container(color: const Color(0xFF00A884)),
                  ),
                  Expanded(
                    flex: (appFraction * 1000).toInt(),
                    child: Container(color: const Color(0xFF3B82F6)),
                  ),
                  Expanded(
                    flex: ((1.0 - mediaFraction - appFraction) * 1000).toInt().clamp(100, 1000),
                    child: Container(color: const Color(0xFF222E35)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Row(
            children: [
              _buildLegendDot(const Color(0xFF00A884), 'DOLSYX Media', _formatBytes(mediaBytes)),
              const SizedBox(width: 20),
              _buildLegendDot(const Color(0xFF3B82F6), 'DB & Cache', _formatBytes(dbBytes + cacheBytes)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label, String sizeStr) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          sizeStr,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }

  /// Review and Delete Items (WhatsApp style: >5 MB items)
  Widget _buildReviewSection() {
    final largeCount = _largeFiles.length;
    final largeBytes = (_stats['largeFilesBytes'] as int?) ?? 0;

    return Container(
      color: const Color(0xFF111B21),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'REVIEW AND DELETE ITEMS',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // > 5 MB Card
          InkWell(
            onTap: () {
              setState(() => _isSelectionMode = !_isSelectionMode);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF222E35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.file_copy_outlined, color: Color(0xFF00A884), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Larger than 5 MB',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$largeCount items • ${_formatBytes(largeBytes)}',
                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isSelectionMode ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_right_rounded,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),

          // Horizontal scroll of large items
          if (_largeFiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 100,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _largeFiles.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (ctx, idx) {
                  final item = _largeFiles[idx];
                  final itemId = (item['id'] ?? '').toString();
                  final isSelected = _selectedFileIds.contains(itemId);
                  final size = (item['computedSize'] as int?) ?? (item['file_size'] as int?) ?? 0;
                  final type = (item['media_type'] as String? ?? '').toUpperCase();

                  return GestureDetector(
                    onTap: () {
                      if (_isSelectionMode) {
                        setState(() {
                          if (isSelected) {
                            _selectedFileIds.remove(itemId);
                          } else {
                            _selectedFileIds.add(itemId);
                          }
                        });
                      } else {
                        // Open Chat for this message
                        final convId = item['conversation_id']?.toString() ?? '';
                        final convName = item['conversation_name']?.toString() ?? 'Chat';
                        if (convId.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatRoomScreen(
                                conversationId: convId,
                                chatName: convName,
                                avatarUrl: item['conversation_avatar']?.toString(),
                              ),
                            ),
                          );
                        }
                      }
                    },
                    onLongPress: () {
                      setState(() {
                        _isSelectionMode = true;
                        _selectedFileIds.add(itemId);
                      });
                    },
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 100,
                          decoration: BoxDecoration(
                            color: const Color(0xFF222E35),
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected ? Border.all(color: const Color(0xFF00A884), width: 2.5) : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                type == 'VIDEO'
                                    ? Icons.videocam_rounded
                                    : (type == 'IMAGE' ? Icons.image_rounded : Icons.insert_drive_file_rounded),
                                color: Colors.white70,
                                size: 28,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatBytes(size),
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Color(0xFF00A884), shape: BoxShape.circle),
                              child: const Icon(Icons.check, color: Colors.white, size: 14),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ] else if (!_isLoading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('No files larger than 5 MB found.', style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  /// Chats Section: chats sorted by storage used
  Widget _buildChatsSection() {
    return Container(
      color: const Color(0xFF111B21),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'CHATS',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_chatsBreakdown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Center(
                child: Text('No chat storage data available', style: TextStyle(color: Colors.white38, fontSize: 14)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _chatsBreakdown.length,
              itemBuilder: (ctx, idx) {
                final chat = _chatsBreakdown[idx];
                final name = chat['name']?.toString() ?? 'Chat';
                final avatarUrl = chat['avatarUrl']?.toString();
                final isGroup = chat['isGroup'] == 1;
                final totalBytes = (chat['total_bytes'] as int?) ?? 0;
                final mediaCount = (chat['media_count'] as int?) ?? 0;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  leading: ColorAvatar(
                    name: name,
                    avatarUrl: avatarUrl,
                    radius: 22,
                  ),
                  title: Row(
                    children: [
                      if (isGroup) ...[
                        const Icon(Icons.group_rounded, color: Colors.white70, size: 16),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '$mediaCount media files',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatBytes(totalBytes),
                        style: const TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
                    ],
                  ),
                  onTap: () => _openChatDetail(chat),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Detailed media breakdown screen for an individual chat
class ChatStorageDetailScreen extends StatefulWidget {
  final String conversationId;
  final String chatName;
  final String? avatarUrl;
  final int totalBytes;
  final VoidCallback onStorageChanged;

  const ChatStorageDetailScreen({
    super.key,
    required this.conversationId,
    required this.chatName,
    this.avatarUrl,
    required this.totalBytes,
    required this.onStorageChanged,
  });

  @override
  State<ChatStorageDetailScreen> createState() => _ChatStorageDetailScreenState();
}

class _ChatStorageDetailScreenState extends State<ChatStorageDetailScreen> {
  final LocalDatabaseService _localDb = LocalDatabaseService();
  bool _isLoading = true;
  Map<String, dynamic> _chatData = {};

  final Set<String> _selectedItemIds = {};
  bool _isSelectionMode = false;
  String _activeTab = 'ALL'; // ALL, PHOTOS, VIDEOS, AUDIO, DOCS

  @override
  void initState() {
    super.initState();
    _loadChatDetail();
  }

  Future<void> _loadChatDetail() async {
    setState(() => _isLoading = true);
    final data = await _localDb.getChatDetailedStorage(widget.conversationId);
    if (mounted) {
      setState(() {
        _chatData = data;
        _isLoading = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  List<Map<String, dynamic>> _getCurrentItems() {
    final photos = (_chatData['photos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final videos = (_chatData['videos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final audios = (_chatData['audios'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final docs = (_chatData['docs'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    switch (_activeTab) {
      case 'PHOTOS':
        return photos;
      case 'VIDEOS':
        return videos;
      case 'AUDIO':
        return audios;
      case 'DOCS':
        return docs;
      default:
        return [...photos, ...videos, ...audios, ...docs];
    }
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedItemIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete items?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete ${_selectedItemIds.length} item(s) from this chat? Media will be unlinked from storage.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final freed = await _localDb.deleteMediaItems(_selectedItemIds.toList(), deleteFullMessage: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ Freed ${_formatBytes(freed)}!'),
            backgroundColor: const Color(0xFF00A884),
          ),
        );
      }
      _selectedItemIds.clear();
      _isSelectionMode = false;
      widget.onStorageChanged();
      await _loadChatDetail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _getCurrentItems();
    final totalBytes = (_chatData['totalBytes'] as int?) ?? widget.totalBytes;

    return Scaffold(
      backgroundColor: const Color(0xFF0B141B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2C34),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isSelectionMode ? '${_selectedItemIds.length} selected' : widget.chatName,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              _formatBytes(totalBytes),
              style: const TextStyle(color: Color(0xFF00A884), fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all_rounded, color: Colors.white),
              onPressed: () {
                setState(() {
                  if (_selectedItemIds.length == items.length) {
                    _selectedItemIds.clear();
                  } else {
                    _selectedItemIds.addAll(items.map((e) => e['id'] as String));
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              onPressed: _selectedItemIds.isEmpty ? null : _deleteSelectedItems,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedItemIds.clear();
                });
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist_rounded, color: Colors.white70),
              tooltip: 'Select items',
              onPressed: () {
                setState(() => _isSelectionMode = true);
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs (All, Photos, Videos, Audio, Docs)
          Container(
            color: const Color(0xFF111B21),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTab('ALL', 'All (${items.length})'),
                  _buildTab('PHOTOS', 'Photos'),
                  _buildTab('VIDEOS', 'Videos'),
                  _buildTab('AUDIO', 'Audio'),
                  _buildTab('DOCS', 'Documents'),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF222E35), height: 1),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
                : items.isEmpty
                    ? const Center(
                        child: Text('No media items found', style: TextStyle(color: Colors.white38, fontSize: 15)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: items.length,
                        itemBuilder: (ctx, idx) {
                          final item = items[idx];
                          final id = (item['id'] ?? '').toString();
                          final isSelected = _selectedItemIds.contains(id);
                          final size = (item['computedSize'] as int?) ?? 0;
                          final type = (item['media_type'] as String? ?? '').toUpperCase();

                          return GestureDetector(
                            onTap: () {
                              if (_isSelectionMode) {
                                setState(() {
                                  if (isSelected) {
                                    _selectedItemIds.remove(id);
                                  } else {
                                    _selectedItemIds.add(id);
                                  }
                                });
                              }
                            },
                            onLongPress: () {
                              setState(() {
                                _isSelectionMode = true;
                                _selectedItemIds.add(id);
                              });
                            },
                            child: Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: isSelected
                                        ? Border.all(color: const Color(0xFF00A884), width: 2.5)
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        type == 'VIDEO'
                                            ? Icons.videocam_rounded
                                            : (type == 'IMAGE'
                                                ? Icons.image_rounded
                                                : (type == 'AUDIO' || type == 'VOICE'
                                                    ? Icons.audiotrack_rounded
                                                    : Icons.insert_drive_file_rounded)),
                                        color: Colors.white70,
                                        size: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _formatBytes(size),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF00A884),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check, color: Colors.white, size: 14),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String key, String label) {
    final isSelected = _activeTab == key;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = key;
          _selectedItemIds.clear();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00A884) : const Color(0xFF1F2C34),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
