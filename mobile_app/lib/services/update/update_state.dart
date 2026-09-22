enum UpdateStatus {
  idle,
  checking,
  updateAvailable,
  downloadStarted,
  downloading,
  downloadCompleted,
  installStarted,
  installing,
  installCompleted,
  appRestarting,
  verifying,
  upToDate,
  updateFailed,
  retryAvailable,
}

class UpdateState {
  final UpdateStatus status;
  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final bool updateAvailable;
  final bool isForced;
  final double downloadProgress;
  final String statusMessage;
  final String? errorMessage;
  final DateTime? lastCheckTime;

  const UpdateState({
    required this.status,
    this.currentVersion = '1.0.0',
    this.currentBuild = 1,
    this.latestVersion = '',
    this.latestBuild = 0,
    this.updateAvailable = false,
    this.isForced = false,
    this.downloadProgress = 0.0,
    this.statusMessage = '',
    this.errorMessage,
    this.lastCheckTime,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    String? currentVersion,
    int? currentBuild,
    String? latestVersion,
    int? latestBuild,
    bool? updateAvailable,
    bool? isForced,
    double? downloadProgress,
    String? statusMessage,
    String? errorMessage,
    DateTime? lastCheckTime,
  }) {
    return UpdateState(
      status: status ?? this.status,
      currentVersion: currentVersion ?? this.currentVersion,
      currentBuild: currentBuild ?? this.currentBuild,
      latestVersion: latestVersion ?? this.latestVersion,
      latestBuild: latestBuild ?? this.latestBuild,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      isForced: isForced ?? this.isForced,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: errorMessage ?? this.errorMessage,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
    );
  }

  @override
  String toString() {
    return 'UpdateState(status: $status, current: $currentVersion+$currentBuild, '
        'latest: $latestVersion+$latestBuild, available: $updateAvailable, forced: $isForced, '
        'progress: ${(downloadProgress * 100).toInt()}%)';
  }
}
