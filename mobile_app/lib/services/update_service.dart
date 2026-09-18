import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../theme/app_theme.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final String downloadUrl;
  final String fileSizeMb;
  final String updatedAt;
  final bool hasApk;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileSizeMb,
    required this.updatedAt,
    required this.hasApk,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version']?.toString() ?? '1.0.0',
      buildNumber: (json['buildNumber'] is int)
          ? json['buildNumber']
          : int.tryParse(json['buildNumber']?.toString() ?? '1') ?? 1,
      releaseNotes: json['releaseNotes']?.toString() ?? 'New updates and stability improvements.',
      downloadUrl: json['downloadUrl']?.toString() ?? '/api/app/download',
      fileSizeMb: json['fileSizeMb']?.toString() ?? '220 MB',
      updatedAt: json['updatedAt']?.toString() ?? '',
      hasApk: json['hasApk'] == true,
    );
  }
}

class UpdateService {
  static const String _installedBuildKey = 'installed_build_number';
  static const MethodChannel _installerChannel = MethodChannel('com.dolsyx/app_installer');

  // Currently installed client build number
  static const int currentAppBuild = 1;

  Future<Map<String, dynamic>> getRunningAppInfo() async {
    try {
      final info = await _installerChannel.invokeMethod('getAppInfo');
      if (info is Map) {
        return {
          'versionName': info['versionName']?.toString() ?? '1.0.0',
          'versionCode': (info['versionCode'] as num?)?.toInt() ?? currentAppBuild,
        };
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return {
      'versionName': '1.0.0',
      'versionCode': prefs.getInt(_installedBuildKey) ?? currentAppBuild,
    };
  }

  Future<int> getInstalledBuildNumber() async {
    final info = await getRunningAppInfo();
    return info['versionCode'] as int;
  }

  static bool _isDialogShowing = false;

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final url = Uri.parse('${ApiService.baseUrl}/app/version');
      final response = await http.get(url).timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && (data['hasApk'] == true || data['downloadUrl'] != null)) {
          final info = UpdateInfo.fromJson(data);
          final installedBuild = await getInstalledBuildNumber();
          if (info.buildNumber > installedBuild) {
            return info;
          }
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] Check update error: $e');
    }
    return null;
  }

  Future<void> promptUpdate(BuildContext context, {bool manual = false}) async {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 12),
              Text('Checking for DOLSYX updates...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }

    final updateInfo = await checkForUpdate();
    if (!context.mounted) return;

    if (updateInfo == null) {
      if (manual) {
        final running = await getRunningAppInfo();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('DOLSYX is up to date! (v${running['versionName']})'),
            backgroundColor: const Color(0xFF1E7E52),
          ),
        );
      }
      return;
    }

    _showUpdateDialog(context, updateInfo);
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo info) {
    if (_isDialogShowing) return;
    _isDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _UpdateDialog(info: info),
    ).then((_) {
      _isDialogShowing = false;
    });
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _downloadStatus = '';
  String? _errorMessage;

  Future<void> _startDownloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _downloadStatus = 'Connecting to server...';
    });

    try {
      final downloadPath = widget.info.downloadUrl.startsWith('http')
          ? widget.info.downloadUrl
          : '${ApiService.baseUrl}${widget.info.downloadUrl}';

      final request = http.Request('GET', Uri.parse(downloadPath));
      final client = http.Client();
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Server returned HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/dolsyx-update.apk');
      if (await apkFile.exists()) {
        try { await apkFile.delete(); } catch (_) {}
      }

      final sink = apkFile.openWrite();
      int receivedBytes = 0;

      await streamedResponse.stream.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0 && mounted) {
            setState(() {
              _progress = receivedBytes / totalBytes;
              final recMb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
              final totMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
              _downloadStatus = '$recMb MB / $totMb MB (${(_progress * 100).toInt()}%)';
            });
          }
        },
        cancelOnError: true,
      ).asFuture();

      await sink.flush();
      await sink.close();

      if (!mounted) return;

      setState(() {
        _downloadStatus = 'Verifying and launching installer...';
      });

      // Update stored build number so it reflects the new installed build
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(UpdateService._installedBuildKey, widget.info.buildNumber);

      // Launch native Android installer
      final res = await UpdateService._installerChannel.invokeMethod('installApk', {
        'filePath': apkFile.path,
      });

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[UpdateService] Download failed: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.isDark ? const Color(0xFF202C33) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E7E52).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update_rounded, color: Color(0xFF25D366), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isDownloading ? 'Downloading Update' : 'Update Available',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: _isDownloading
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: AppTheme.isDark ? Colors.black26 : Colors.grey.shade300,
                  color: const Color(0xFF25D366),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Text(
                  _downloadStatus,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  'Please wait while DOLSYX downloads the update over Wi-Fi.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E7E52).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Version ${widget.info.version} (${widget.info.fileSizeMb})',
                    style: const TextStyle(
                      color: Color(0xFF25D366),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.info.releaseNotes,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Update will install directly on your phone without losing any chats or settings.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
      actions: _isDownloading
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Later',
                  style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: const Color(0xFF0B141A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: _startDownloadAndInstall,
                child: const Text(
                  'Update Now',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
    );
  }
}
