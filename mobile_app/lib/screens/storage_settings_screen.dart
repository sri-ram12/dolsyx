import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  bool _autoDownloadPhotosWifi = true;
  bool _autoDownloadVideosWifi = false;
  bool _autoDownloadDocsWifi = true;
  bool _autoDownloadCellular = false;
  String _compressionLevel = 'Standard';
  bool _dataSaverMode = false;

  void _clearCache() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear App Cache'),
        content: const Text('This will free up cached temporary files and images. Your messages will not be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cleared 142.5 MB of temporary cache!')),
              );
            },
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage and Data'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                      Text('248.4 MB', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: 0.35, backgroundColor: Colors.black26, color: AppTheme.primaryColor),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Photos: 120 MB', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text('Videos: 84 MB', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text('Docs: 44.4 MB', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
          const SizedBox(height: 16),
          Text('Media Auto-Download', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: Text('Auto-download Photos (Wi-Fi)', style: TextStyle(color: AppTheme.textPrimary)),
            value: _autoDownloadPhotosWifi,
            onChanged: (v) => setState(() => _autoDownloadPhotosWifi = v),
          ),
          SwitchListTile(
            title: Text('Auto-download Videos (Wi-Fi)', style: TextStyle(color: AppTheme.textPrimary)),
            value: _autoDownloadVideosWifi,
            onChanged: (v) => setState(() => _autoDownloadVideosWifi = v),
          ),
          SwitchListTile(
            title: Text('Auto-download on Cellular Data', style: TextStyle(color: AppTheme.textPrimary)),
            value: _autoDownloadCellular,
            onChanged: (v) => setState(() => _autoDownloadCellular = v),
          ),
          const Divider(),
          Text('Media Upload Quality & Compression', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
          ListTile(
            title: Text('Media Upload Quality', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: Text(_compressionLevel, style: TextStyle(color: AppTheme.textSecondary)),
            trailing: PopupMenuButton<String>(
              onSelected: (val) => setState(() => _compressionLevel = val),
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
            onChanged: (v) => setState(() => _dataSaverMode = v),
          ),
        ],
      ),
    );
  }
}
