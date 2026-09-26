import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/local_database_service.dart';
import 'manage_storage_screen.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  final LocalDatabaseService _localDb = LocalDatabaseService();
  bool _autoDownloadPhotosWifi = true;
  bool _autoDownloadVideosWifi = true;
  bool _autoDownloadDocsWifi = true;
  bool _autoDownloadCellular = false;
  String _compressionLevel = 'Standard Compression';
  bool _dataSaverMode = false;
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final stats = await _localDb.getStorageBreakdown();
    if (mounted) {
      setState(() {
        _stats = stats;
        _autoDownloadPhotosWifi = prefs.getBool('auto_download_photos_wifi') ?? true;
        _autoDownloadVideosWifi = prefs.getBool('auto_download_videos_wifi') ?? true;
        _autoDownloadDocsWifi = prefs.getBool('auto_download_docs_wifi') ?? true;
        _autoDownloadCellular = prefs.getBool('auto_download_cellular') ?? false;
        _compressionLevel = prefs.getString('media_quality') ?? 'Standard Compression';
        _dataSaverMode = prefs.getBool('data_saver_mode') ?? false;
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

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  void _clearCache() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Clear App Cache', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('This will free up cached temporary files and images. Your messages will not be deleted.', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final freed = await _localDb.clearStorageCache();
              await _loadSettings();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Cleared temporary cache! Freed ${_formatBytes(freed)}'),
                    backgroundColor: const Color(0xFF00A884),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Storage and Data'),
          backgroundColor: AppTheme.surfaceColor,
        ),
        backgroundColor: AppTheme.backgroundColor,
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF00A884))),
      );
    }

    final totalAppBytes = (_stats['totalAppBytes'] as int?) ?? 0;
    final photosBytes = (_stats['photosBytes'] as int?) ?? 0;
    final videosBytes = (_stats['videosBytes'] as int?) ?? 0;
    final docsBytes = (_stats['docsBytes'] as int?) ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage and Data'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // WhatsApp Standard: Manage Storage Tile
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: AppTheme.surfaceColor,
            leading: const Icon(Icons.folder_outlined, color: Color(0xFF00A884), size: 28),
            title: Text('Manage storage', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Text(_formatBytes(totalAppBytes), style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManageStorageScreen()),
              ).then((_) => _loadSettings());
            },
          ),
          const SizedBox(height: 16),
          Card(
            color: AppTheme.surfaceColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Storage Used', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(_formatBytes(totalAppBytes), style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: totalAppBytes > 0 ? (totalAppBytes / (500 * 1024 * 1024)).clamp(0.05, 1.0) : 0.05,
                    backgroundColor: Colors.black26,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Photos: ${_formatBytes(photosBytes)}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text('Videos: ${_formatBytes(videosBytes)}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text('Docs: ${_formatBytes(docsBytes)}', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _clearCache,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Clear Storage Cache'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Media Auto-Download', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text('Auto-download Photos (Wi-Fi)', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Automatically saves incoming chat photos to Gallery', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: _autoDownloadPhotosWifi,
            activeTrackColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _autoDownloadPhotosWifi = v);
              _saveSetting('auto_download_photos_wifi', v);
            },
          ),
          SwitchListTile(
            title: Text('Auto-download Videos (Wi-Fi)', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Automatically saves incoming chat videos to Gallery', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: _autoDownloadVideosWifi,
            activeTrackColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _autoDownloadVideosWifi = v);
              _saveSetting('auto_download_videos_wifi', v);
            },
          ),
          SwitchListTile(
            title: Text('Auto-download Documents (Wi-Fi)', style: TextStyle(color: AppTheme.textPrimary)),
            value: _autoDownloadDocsWifi,
            activeTrackColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _autoDownloadDocsWifi = v);
              _saveSetting('auto_download_docs_wifi', v);
            },
          ),
          SwitchListTile(
            title: Text('Auto-download on Cellular Data', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Allow auto-download over mobile carrier data', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: _autoDownloadCellular,
            activeTrackColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _autoDownloadCellular = v);
              _saveSetting('auto_download_cellular', v);
            },
          ),
          const Divider(height: 32),
          Text('Media Upload Quality & Compression', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 15)),
          ListTile(
            title: Text('Media Upload Quality', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_compressionLevel, style: TextStyle(color: AppTheme.textSecondary)),
            trailing: PopupMenuButton<String>(
              onSelected: (val) {
                setState(() => _compressionLevel = val);
                _saveSetting('media_quality', val);
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'Standard Compression', child: Text('Standard Compression')),
                const PopupMenuItem(value: 'High Quality', child: Text('High Quality')),
                const PopupMenuItem(value: 'HD / Original Uncompressed', child: Text('HD / Original Uncompressed')),
              ],
            ),
          ),
          SwitchListTile(
            title: Text('Low Data Usage Mode (Battery Saver)', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text('Reduce socket ping rate and lower call data usage', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: _dataSaverMode,
            activeTrackColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _dataSaverMode = v);
              _saveSetting('data_saver_mode', v);
            },
          ),
        ],
      ),
    );
  }
}
