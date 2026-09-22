import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/update/version_comparator.dart';

void main() {
  group('VersionComparator Tests', () {
    test('TEST 1: installed == latest (1.0.0 == 1.0.0) -> No update', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.0.0',
        currentBuild: 1,
        latestVersion: '1.0.0',
        latestBuild: 1,
      );
      expect(res.isUpdateAvailable, false);
      expect(res.isForced, false);
      expect(res.semverComparison, 0);
    });

    test('TEST 2: installed < latest (1.0.0 < 1.1.0) -> Update available', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.0.0',
        currentBuild: 1,
        latestVersion: '1.1.0',
        latestBuild: 2,
      );
      expect(res.isUpdateAvailable, true);
      expect(res.semverComparison, -1);
    });

    test('TEST 3: installed > latest (1.1.0 > 1.0.0) -> No update (dev/newer)', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.1.0',
        currentBuild: 2,
        latestVersion: '1.0.0',
        latestBuild: 1,
      );
      expect(res.isUpdateAvailable, false);
      expect(res.semverComparison, 1);
    });

    test('TEST 4: SemVer ordering: 1.9.0 < 1.10.0 -> Update available', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.9.0',
        currentBuild: 9,
        latestVersion: '1.10.0',
        latestBuild: 10,
      );
      expect(res.isUpdateAvailable, true);
      expect(res.semverComparison, -1);
    });

    test('TEST 5: SemVer ordering: 1.10.0 > 1.9.0 -> No update', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.10.0',
        currentBuild: 10,
        latestVersion: '1.9.0',
        latestBuild: 9,
      );
      expect(res.isUpdateAvailable, false);
      expect(res.semverComparison, 1);
    });

    test('TEST 6: Patch bump: 1.0.3 < 1.0.4 -> Update available', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.0.3',
        currentBuild: 3,
        latestVersion: '1.0.4',
        latestBuild: 4,
      );
      expect(res.isUpdateAvailable, true);
    });

    test('TEST 7: Android ABI offset normalization (arm64-v8a 2004 -> 4)', () {
      // Installed app is 1.0.4 with Android ARM64 versionCode 2004
      // Server is 1.0.4 with buildNumber 4
      final res = VersionComparator.evaluate(
        currentVersion: '1.0.4',
        currentBuild: 2004,
        latestVersion: '1.0.4',
        latestBuild: 4,
      );
      expect(res.isUpdateAvailable, false);
    });

    test('TEST 8: Android ABI offset normalization (arm64-v8a 2003 vs server build 4)', () {
      // Installed app is 1.0.3 with Android ARM64 versionCode 2003
      // Server is 1.0.4 with buildNumber 4
      final res = VersionComparator.evaluate(
        currentVersion: '1.0.3',
        currentBuild: 2003,
        latestVersion: '1.0.4',
        latestBuild: 4,
      );
      expect(res.isUpdateAvailable, true);
    });

    test('TEST 9: Same version, higher build number -> Update available', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.0.4',
        currentBuild: 4,
        latestVersion: '1.0.4',
        latestBuild: 5,
      );
      expect(res.isUpdateAvailable, true);
    });

    test('TEST 10: Same version, same build number -> No update', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.0.4',
        currentBuild: 4,
        latestVersion: '1.0.4',
        latestBuild: 4,
      );
      expect(res.isUpdateAvailable, false);
    });

    test('TEST 11: Forced update when installed is below minimumSupportedVersion', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.1.0',
        currentBuild: 11,
        latestVersion: '1.5.0',
        latestBuild: 15,
        minimumSupportedVersion: '1.4.0',
      );
      expect(res.isUpdateAvailable, true);
      expect(res.isForced, true);
    });

    test('TEST 12: Optional update when installed >= minimumSupportedVersion but < latest', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.4.0',
        currentBuild: 14,
        latestVersion: '1.5.0',
        latestBuild: 15,
        minimumSupportedVersion: '1.4.0',
      );
      expect(res.isUpdateAvailable, true);
      expect(res.isForced, false);
    });

    test('TEST 13: Forced update by build number', () {
      final res = VersionComparator.evaluate(
        currentVersion: '1.0.4',
        currentBuild: 2,
        latestVersion: '1.0.4',
        latestBuild: 5,
        minimumSupportedBuild: 4,
      );
      expect(res.isUpdateAvailable, true);
      expect(res.isForced, true);
    });

    test('TEST 14: Clean SemVer parsing with v-prefix and build suffixes', () {
      expect(VersionComparator.compareSemanticVersions('v1.0.4', '1.0.4'), 0);
      expect(VersionComparator.compareSemanticVersions('1.0.4+4', '1.0.4+5'), 0);
      expect(VersionComparator.compareSemanticVersions('1.0.4-beta', '1.0.4'), 0);
      expect(VersionComparator.compareSemanticVersions('2.0.0', '1.99.99'), 1);
      expect(VersionComparator.compareSemanticVersions('1.9.99', '1.10.0'), -1);
    });

    test('TEST 15: Post-update critical regression test: installed == latest -> No popup loop', () {
      // Step 1: Prior to update (installed 1.0.3+3, latest 1.0.4+4)
      final preUpdate = VersionComparator.evaluate(
        currentVersion: '1.0.3',
        currentBuild: 3,
        latestVersion: '1.0.4',
        latestBuild: 4,
      );
      expect(preUpdate.isUpdateAvailable, true);

      // Step 2: Post update & restart (installed 1.0.4+4, latest 1.0.4+4)
      final postUpdate = VersionComparator.evaluate(
        currentVersion: '1.0.4',
        currentBuild: 4,
        latestVersion: '1.0.4',
        latestBuild: 4,
      );
      expect(postUpdate.isUpdateAvailable, false);
      expect(postUpdate.isForced, false);

      // Step 3: Repeated restart
      final repeatedRestart = VersionComparator.evaluate(
        currentVersion: '1.0.4',
        currentBuild: 2004, // ABI split ARM64 code
        latestVersion: '1.0.4',
        latestBuild: 4,
      );
      expect(repeatedRestart.isUpdateAvailable, false);
    });
  });
}
