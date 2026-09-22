class VersionComparisonResult {
  final bool isUpdateAvailable;
  final bool isForced;
  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int latestBuild;
  final int semverComparison; // -1: current < latest, 0: equal, 1: current > latest

  const VersionComparisonResult({
    required this.isUpdateAvailable,
    required this.isForced,
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.semverComparison,
  });

  @override
  String toString() {
    return 'VersionComparisonResult(isUpdateAvailable: $isUpdateAvailable, isForced: $isForced, '
        'current: $currentVersion+$currentBuild, latest: $latestVersion+$latestBuild, '
        'semverDiff: $semverComparison)';
  }
}

class VersionComparator {
  /// Normalizes an Android build number.
  /// When Flutter builds with `--split-per-abi`, Gradle prefixes architecture codes:
  /// armeabi-v7a: 1000 + build
  /// arm64-v8a:   2000 + build
  /// x86_64:      3000 + build
  /// Universal:   build
  /// This extracts the canonical build number.
  static int normalizeBuildNumber(int build) {
    if (build >= 1000 && build < 100000) {
      final remainder = build % 1000;
      // If remainder is non-zero, it's an ABI-prefixed build number (e.g. 2004 -> 4)
      if (remainder > 0) {
        return remainder;
      }
    }
    return build;
  }

  /// Parses a SemVer-like version string into integer components [major, minor, patch].
  /// Ignores pre-release tags or trailing build metadata during core comparison.
  static List<int> parseVersionParts(String version) {
    final clean = version.trim().replaceAll(RegExp(r'^[vV]'), '');
    final withoutMetadata = clean.split('+').first.split('-').first;
    final tokens = withoutMetadata.split('.');

    final parts = <int>[];
    for (int i = 0; i < 3; i++) {
      if (i < tokens.length) {
        parts.add(int.tryParse(tokens[i]) ?? 0);
      } else {
        parts.add(0);
      }
    }
    return parts;
  }

  /// Compares two version strings semantically.
  /// Returns:
  /// -1 if v1 < v2
  ///  0 if v1 == v2
  ///  1 if v1 > v2
  static int compareSemanticVersions(String v1, String v2) {
    final p1 = parseVersionParts(v1);
    final p2 = parseVersionParts(v2);

    for (int i = 0; i < 3; i++) {
      if (p1[i] < p2[i]) return -1;
      if (p1[i] > p2[i]) return 1;
    }
    return 0;
  }

  /// Authoritative evaluation to determine if an update is available or required.
  /// 
  /// Rules:
  /// 1. If current semantic version < latest semantic version -> update is available.
  /// 2. If current semantic version == latest semantic version:
  ///    Compare normalized build numbers. If normalized currentBuild < normalized latestBuild -> update is available.
  /// 3. If current version/build >= latest version/build -> NO update.
  /// 4. Forced update is required if minimumSupportedVersion or minimumSupportedBuild is set and current is below it.
  static VersionComparisonResult evaluate({
    required String currentVersion,
    required int currentBuild,
    required String latestVersion,
    required int latestBuild,
    String? minimumSupportedVersion,
    int? minimumSupportedBuild,
  }) {
    final normCurrentBuild = normalizeBuildNumber(currentBuild);
    final normLatestBuild = normalizeBuildNumber(latestBuild);
    final semverDiff = compareSemanticVersions(currentVersion, latestVersion);

    bool updateAvailable = false;
    if (semverDiff < 0) {
      updateAvailable = true;
    } else if (semverDiff == 0) {
      if (normCurrentBuild < normLatestBuild) {
        updateAvailable = true;
      }
    }

    bool isForced = false;
    if (updateAvailable) {
      if (minimumSupportedVersion != null && minimumSupportedVersion.trim().isNotEmpty) {
        final minSemverDiff = compareSemanticVersions(currentVersion, minimumSupportedVersion);
        if (minSemverDiff < 0) {
          isForced = true;
        }
      }
      if (!isForced && minimumSupportedBuild != null && minimumSupportedBuild > 0) {
        final normMinBuild = normalizeBuildNumber(minimumSupportedBuild);
        if (normCurrentBuild < normMinBuild) {
          isForced = true;
        }
      }
    }

    return VersionComparisonResult(
      isUpdateAvailable: updateAvailable,
      isForced: isForced,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      semverComparison: semverDiff,
    );
  }
}
