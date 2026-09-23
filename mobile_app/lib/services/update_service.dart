import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../theme/app_theme.dart';
import 'update/version_comparator.dart';
import 'update/update_state.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final String downloadUrl;
  final String fileSizeMb;
  final String updatedAt;
  final bool hasApk;
  final String? minimumSupportedVersion;
  final int? minimumSupportedBuild;
  final bool isForced;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileSizeMb,
    required this.updatedAt,
    required this.hasApk,
    this.minimumSupportedVersion,
    this.minimumSupportedBuild,
    this.isForced = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {bool isForced = false}) {
    return UpdateInfo(
      version: json['version']?.toString() ?? '1.0.0',
      buildNumber: (json['buildNumber'] is int)
          ? json['buildNumber']
          : int.tryParse(json['buildNumber']?.toString() ?? '1') ?? 1,
      releaseNotes: json['releaseNotes']?.toString() ?? 'New updates and stability improvements.',
      downloadUrl: json['downloadUrl']?.toString() ?? '/api/app/download',
      fileSizeMb: json['fileSizeMb']?.toString() ?? '117.5 MB',
      updatedAt: json['updatedAt']?.toString() ?? '',
      hasApk: json['hasApk'] == true,
      minimumSupportedVersion: json['minimumSupportedVersion']?.toString(),
      minimumSupportedBuild: (json['minimumSupportedBuild'] is int)
          ? json['minimumSupportedBuild']
          : int.tryParse(json['minimumSupportedBuild']?.toString() ?? '0'),
      isForced: isForced || json['updateRequired'] == true,
    );
  }
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String _installedBuildKey = 'installed_build_number';
  static const String _pendingUpdateVersionKey = 'pending_update_version';
  static const String _pendingUpdateBuildKey = 'pending_update_build';
  static const String _lastCheckedVersionKey = 'last_checked_version';
  static const String _lastCheckedTimeKey = 'last_checked_timestamp';

  static const MethodChannel _installerChannel = MethodChannel('com.dolsyx/app_installer');

  // Fallback build number if native channel is unavailable
  static const int currentAppBuild = 5;
  static const String currentAppVersion = '1.0.5';

  // In-flight deduplication lock
  Future<UpdateInfo?>? _inFlightCheck;

  // Last auto check timestamp for cooldown (15 minutes)
  DateTime? _lastAutoCheckTime;
  static const Duration _autoCheckCooldown = Duration(minutes: 15);

  // Single dialog presentation lock
  static bool _isDialogShowing = false;

  // Current reactive state
  UpdateState _currentState = const UpdateState(status: UpdateStatus.idle);
  UpdateState get currentState => _currentState;

  /// Retrieves the actual running application version and build number
  /// directly from the Android PackageManager runtime.
  Future<Map<String, dynamic>> getRunningAppInfo() async {
    try {
      final info = await _installerChannel.invokeMethod('getAppInfo');
      if (info is Map) {
        final verName = info['versionName']?.toString() ?? currentAppVersion;
        final rawCode = (info['versionCode'] as num?)?.toInt() ?? currentAppBuild;
        return {
          'versionName': verName,
          'versionCode': rawCode,
          'normalizedBuild': VersionComparator.normalizeBuildNumber(rawCode),
        };
      }
    } catch (e) {
      debugPrint('[UPDATE] Failed to query native getAppInfo: $e');
    }

    // Fallback to SharedPreferences or default constants
    final prefs = await SharedPreferences.getInstance();
    final storedBuild = prefs.getInt(_installedBuildKey) ?? currentAppBuild;
    return {
      'versionName': currentAppVersion,
      'versionCode': storedBuild,
      'normalizedBuild': VersionComparator.normalizeBuildNumber(storedBuild),
    };
  }

  Future<int> getInstalledBuildNumber() async {
    final info = await getRunningAppInfo();
    return info['versionCode'] as int;
  }

  /// Post-update verification executed on app startup.
  /// Validates whether a previously attempted update succeeded.
  Future<void> verifyInstallationState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingVersion = prefs.getString(_pendingUpdateVersionKey);
      final pendingBuild = prefs.getInt(_pendingUpdateBuildKey);

      final running = await getRunningAppInfo();
      final runningVer = running['versionName'] as String;
      final runningBuild = running['versionCode'] as int;

      debugPrint('[UPDATE] Running Version: $runningVer (Build: $runningBuild)');

      if (pendingVersion != null || pendingBuild != null) {
        final cmp = VersionComparator.evaluate(
          currentVersion: runningVer,
          currentBuild: runningBuild,
          latestVersion: pendingVersion ?? runningVer,
          latestBuild: pendingBuild ?? runningBuild,
        );

        if (!cmp.isUpdateAvailable) {
          // Installed version is >= pending version: update confirmed!
          debugPrint('[UPDATE] Post-Install Version: $runningVer');
          debugPrint('[UPDATE] Post-Install Build: $runningBuild');
          debugPrint('[UPDATE] Verification: UP_TO_DATE (Update successfully confirmed)');
          await prefs.setInt(_installedBuildKey, runningBuild);
          await prefs.remove(_pendingUpdateVersionKey);
          await prefs.remove(_pendingUpdateBuildKey);
        } else {
          // Installed version is still older: update was interrupted, cancelled, or failed
          debugPrint('[UPDATE] Post-Install Verification: UPDATE_NOT_APPLIED (Installed: $runningVer+$runningBuild, Expected: $pendingVersion+$pendingBuild)');
          await prefs.remove(_pendingUpdateVersionKey);
          await prefs.remove(_pendingUpdateBuildKey);
        }
      }
    } catch (e) {
      debugPrint('[UPDATE] Error during verifyInstallationState: $e');
    }
  }

  /// Authoritative update check with request deduplication and cooldown.
  Future<UpdateInfo?> checkForUpdate({bool manual = false}) async {
    // 1. If a check is already in-flight, return the existing future (deduplication)
    if (_inFlightCheck != null) {
      debugPrint('[UPDATE] Coalescing concurrent update check request.');
      return _inFlightCheck!;
    }

    // 2. Cooldown check for automatic checks
    if (!manual && _lastAutoCheckTime != null) {
      final elapsed = DateTime.now().difference(_lastAutoCheckTime!);
      if (elapsed < _autoCheckCooldown) {
        debugPrint('[UPDATE] Skipping auto check; last checked ${elapsed.inMinutes}m ago (Cooldown: ${_autoCheckCooldown.inMinutes}m)');
        return null;
      }
    }

    _inFlightCheck = _performCheckForUpdate(manual: manual);
    try {
      final result = await _inFlightCheck!;
      return result;
    } finally {
      _inFlightCheck = null;
    }
  }

  Future<UpdateInfo?> _performCheckForUpdate({required bool manual}) async {
    _currentState = _currentState.copyWith(
      status: UpdateStatus.checking,
      statusMessage: 'Checking for updates...',
    );

    try {
      // First verify post-install state if needed
      await verifyInstallationState();

      final running = await getRunningAppInfo();
      final runningVer = running['versionName'] as String;
      final runningBuild = running['versionCode'] as int;

      // Cache-busting URL to bypass any intermediate caching proxy
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse('${ApiService.baseUrl}/app/version?_t=$timestamp');

      final response = await http.get(
        url,
        headers: {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      ).timeout(const Duration(seconds: 8));

      _lastAutoCheckTime = DateTime.now();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && (data['hasApk'] == true || data['downloadUrl'] != null)) {
          final serverVer = data['version']?.toString() ?? '1.0.0';
          final serverBuild = (data['buildNumber'] is int)
              ? data['buildNumber']
              : int.tryParse(data['buildNumber']?.toString() ?? '1') ?? 1;
          final minVer = data['minimumSupportedVersion']?.toString();
          final minBuild = (data['minimumSupportedBuild'] is int)
              ? data['minimumSupportedBuild']
              : int.tryParse(data['minimumSupportedBuild']?.toString() ?? '0');

          debugPrint('[UPDATE]');
          debugPrint('[UPDATE] Current Version: $runningVer');
          debugPrint('[UPDATE] Current Build: $runningBuild (Normalized: ${running['normalizedBuild']})');
          debugPrint('[UPDATE] Latest Version: $serverVer');
          debugPrint('[UPDATE] Latest Build: $serverBuild');

          // Semantic Version and Build comparison
          final comparison = VersionComparator.evaluate(
            currentVersion: runningVer,
            currentBuild: runningBuild,
            latestVersion: serverVer,
            latestBuild: serverBuild,
            minimumSupportedVersion: minVer,
            minimumSupportedBuild: minBuild,
          );

          debugPrint('[UPDATE] Comparison: ${comparison.isUpdateAvailable ? (comparison.isForced ? "FORCE_UPDATE_REQUIRED" : "UPDATE_AVAILABLE") : "UP_TO_DATE"}');

          if (comparison.isUpdateAvailable) {
            final info = UpdateInfo.fromJson(data, isForced: comparison.isForced);
            _currentState = _currentState.copyWith(
              status: UpdateStatus.updateAvailable,
              currentVersion: runningVer,
              currentBuild: runningBuild,
              latestVersion: serverVer,
              latestBuild: serverBuild,
              updateAvailable: true,
              isForced: comparison.isForced,
              lastCheckTime: DateTime.now(),
            );
            return info;
          } else {
            _currentState = _currentState.copyWith(
              status: UpdateStatus.upToDate,
              currentVersion: runningVer,
              currentBuild: runningBuild,
              latestVersion: serverVer,
              latestBuild: serverBuild,
              updateAvailable: false,
              isForced: false,
              lastCheckTime: DateTime.now(),
            );
            return null;
          }
        }
      }
    } catch (e) {
      debugPrint('[UPDATE] Check update error: $e');
      _currentState = _currentState.copyWith(
        status: UpdateStatus.updateFailed,
        errorMessage: e.toString(),
      );
    }
    return null;
  }

  /// Prompts the user with an update dialog if an update is available.
  /// Duplication protected: only ONE dialog can ever be presented at a time.
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

    final updateInfo = await checkForUpdate(manual: manual);
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

    // Only show dialog if update is genuinely available and no dialog is currently showing
    _showUpdateDialog(context, updateInfo);
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo info) {
    if (_isDialogShowing) {
      debugPrint('[UPDATE] Update dialog already showing; ignoring duplicate prompt.');
      return;
    }
    _isDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: !info.isForced,
      builder: (dialogCtx) => PopScope(
        canPop: !info.isForced,
        child: _UpdateDialog(info: info),
      ),
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

    debugPrint('[UPDATE] Download Started');

    try {
      final String rawUrl = widget.info.downloadUrl;
      String downloadPath;
      if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        downloadPath = rawUrl;
      } else {
        final base = ApiService.baseUrl.endsWith('/')
            ? ApiService.baseUrl.substring(0, ApiService.baseUrl.length - 1)
            : ApiService.baseUrl;
        final cleanPath = rawUrl.startsWith('/api/')
            ? rawUrl.substring(4)
            : (rawUrl.startsWith('/') ? rawUrl : '/$rawUrl');
        downloadPath = '$base$cleanPath';
      }

      final request = http.Request('GET', Uri.parse(downloadPath));
      request.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate';
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

      debugPrint('[UPDATE] Download Completed (${apkFile.lengthSync()} bytes)');

      if (!mounted) return;

      setState(() {
        _downloadStatus = 'Launching installer...';
      });

      // Record pending update metadata.
      // NOTE: We deliberately do NOT mark the update as installed yet!
      // True installation is verified post-restart via package manager metadata.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(UpdateService._pendingUpdateVersionKey, widget.info.version);
      await prefs.setInt(UpdateService._pendingUpdateBuildKey, widget.info.buildNumber);

      debugPrint('[UPDATE] Installation Started');

      // Launch native Android package installer
      await UpdateService._installerChannel.invokeMethod('installApk', {
        'filePath': apkFile.path,
      });

      debugPrint('[UPDATE] Installation Intent Dispatched');

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[UPDATE] Download/Install failed: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Update couldn\'t be completed. Please try again.';
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
              color: AppTheme.primaryColor.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.system_update_rounded, color: AppTheme.primaryColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isDownloading
                  ? 'Downloading Update'
                  : (widget.info.isForced ? 'Update Required' : 'Update Available'),
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
                  color: AppTheme.primaryColor,
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
                  'Please wait while DOLSYX downloads the update over Wi-Fi/Mobile.',
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
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Version ${widget.info.version} (${widget.info.fileSizeMb})',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
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
                  widget.info.isForced
                      ? 'This update includes essential security and protocol updates required to use DOLSYX.'
                      : 'Update will install directly on your phone without losing any chats or settings.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
      actions: _isDownloading
          ? null
          : [
              if (!widget.info.isForced)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Later',
                    style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: ThemeData.estimateBrightnessForColor(AppTheme.primaryColor) == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF0B141A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  elevation: 2,
                ),
                onPressed: _startDownloadAndInstall,
                child: Text(
                  _errorMessage != null ? 'Retry' : 'Update Now',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
    );
  }
}
