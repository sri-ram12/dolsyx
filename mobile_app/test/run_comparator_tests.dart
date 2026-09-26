import 'dart:io';
import 'package:mobile_app/services/update/version_comparator.dart';

void assertTrue(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAIL: $message');
    exit(1);
  } else {
    stdout.writeln('PASS: $message');
  }
}

void assertEquals(dynamic actual, dynamic expected, String message) {
  if (actual != expected) {
    stderr.writeln('FAIL: $message (Expected: $expected, Actual: $actual)');
    exit(1);
  } else {
    stdout.writeln('PASS: $message');
  }
}

void main() {
  stdout.writeln('=== RUNNING VERSION COMPARATOR AUTOMATED TEST SUITE ===');

  // TEST 1: installed == latest (1.0.0 == 1.0.0) -> No update
  final t1 = VersionComparator.evaluate(
    currentVersion: '1.0.0',
    currentBuild: 1,
    latestVersion: '1.0.0',
    latestBuild: 1,
  );
  assertEquals(t1.isUpdateAvailable, false, 'TEST 1: 1.0.0 == 1.0.0 -> no update');
  assertEquals(t1.isForced, false, 'TEST 1: isForced is false');
  assertEquals(t1.semverComparison, 0, 'TEST 1: semverDiff is 0');

  // TEST 2: installed < latest (1.0.0 < 1.1.0) -> Update available
  final t2 = VersionComparator.evaluate(
    currentVersion: '1.0.0',
    currentBuild: 1,
    latestVersion: '1.1.0',
    latestBuild: 2,
  );
  assertEquals(t2.isUpdateAvailable, true, 'TEST 2: 1.0.0 < 1.1.0 -> update available');
  assertEquals(t2.semverComparison, -1, 'TEST 2: semverDiff is -1');

  // TEST 3: installed > latest (1.1.0 > 1.0.0) -> No update
  final t3 = VersionComparator.evaluate(
    currentVersion: '1.1.0',
    currentBuild: 2,
    latestVersion: '1.0.0',
    latestBuild: 1,
  );
  assertEquals(t3.isUpdateAvailable, false, 'TEST 3: 1.1.0 > 1.0.0 -> no update');
  assertEquals(t3.semverComparison, 1, 'TEST 3: semverDiff is 1');

  // TEST 4: SemVer ordering: 1.9.0 < 1.10.0 -> Update available
  final t4 = VersionComparator.evaluate(
    currentVersion: '1.9.0',
    currentBuild: 9,
    latestVersion: '1.10.0',
    latestBuild: 10,
  );
  assertEquals(t4.isUpdateAvailable, true, 'TEST 4: 1.9.0 < 1.10.0 -> update available');
  assertEquals(t4.semverComparison, -1, 'TEST 4: semverDiff is -1');

  // TEST 5: SemVer ordering: 1.10.0 > 1.9.0 -> No update
  final t5 = VersionComparator.evaluate(
    currentVersion: '1.10.0',
    currentBuild: 10,
    latestVersion: '1.9.0',
    latestBuild: 9,
  );
  assertEquals(t5.isUpdateAvailable, false, 'TEST 5: 1.10.0 > 1.9.0 -> no update');
  assertEquals(t5.semverComparison, 1, 'TEST 5: semverDiff is 1');

  // TEST 6: Patch bump: 1.0.3 < 1.0.4 -> Update available
  final t6 = VersionComparator.evaluate(
    currentVersion: '1.0.3',
    currentBuild: 3,
    latestVersion: '1.0.4',
    latestBuild: 4,
  );
  assertEquals(t6.isUpdateAvailable, true, 'TEST 6: 1.0.3 < 1.0.4 -> update available');

  // TEST 7: Android ABI offset normalization (arm64-v8a 2004 -> 4)
  final t7 = VersionComparator.evaluate(
    currentVersion: '1.0.4',
    currentBuild: 2004,
    latestVersion: '1.0.4',
    latestBuild: 4,
  );
  assertEquals(t7.isUpdateAvailable, false, 'TEST 7: ABI offset 2004 normalized to 4, 1.0.4 == 1.0.4 -> no update');

  // TEST 8: Android ABI offset normalization (arm64-v8a 2003 vs server build 4)
  final t8 = VersionComparator.evaluate(
    currentVersion: '1.0.3',
    currentBuild: 2003,
    latestVersion: '1.0.4',
    latestBuild: 4,
  );
  assertEquals(t8.isUpdateAvailable, true, 'TEST 8: ABI offset 2003 normalized to 3, 1.0.3 < 1.0.4 -> update available');

  // TEST 9: Same version, higher build number -> Update available
  final t9 = VersionComparator.evaluate(
    currentVersion: '1.0.4',
    currentBuild: 4,
    latestVersion: '1.0.4',
    latestBuild: 5,
  );
  assertEquals(t9.isUpdateAvailable, true, 'TEST 9: 1.0.4+4 < 1.0.4+5 -> update available');

  // TEST 10: Same version, same build number -> No update
  final t10 = VersionComparator.evaluate(
    currentVersion: '1.0.4',
    currentBuild: 4,
    latestVersion: '1.0.4',
    latestBuild: 4,
  );
  assertEquals(t10.isUpdateAvailable, false, 'TEST 10: 1.0.4+4 == 1.0.4+4 -> no update');

  // TEST 11: Forced update when installed is below minimumSupportedVersion
  final t11 = VersionComparator.evaluate(
    currentVersion: '1.1.0',
    currentBuild: 11,
    latestVersion: '1.5.0',
    latestBuild: 15,
    minimumSupportedVersion: '1.4.0',
  );
  assertEquals(t11.isUpdateAvailable, true, 'TEST 11: update available');
  assertEquals(t11.isForced, true, 'TEST 11: isForced is true (1.1.0 < min 1.4.0)');

  // TEST 12: Optional update when installed >= minimumSupportedVersion but < latest
  final t12 = VersionComparator.evaluate(
    currentVersion: '1.4.0',
    currentBuild: 14,
    latestVersion: '1.5.0',
    latestBuild: 15,
    minimumSupportedVersion: '1.4.0',
  );
  assertEquals(t12.isUpdateAvailable, true, 'TEST 12: update available');
  assertEquals(t12.isForced, false, 'TEST 12: isForced is false (1.4.0 >= min 1.4.0)');

  // TEST 13: Forced update by build number
  final t13 = VersionComparator.evaluate(
    currentVersion: '1.0.4',
    currentBuild: 2,
    latestVersion: '1.0.4',
    latestBuild: 5,
    minimumSupportedBuild: 4,
  );
  assertEquals(t13.isUpdateAvailable, true, 'TEST 13: update available');
  assertEquals(t13.isForced, true, 'TEST 13: isForced is true (build 2 < minBuild 4)');

  // TEST 14: Clean SemVer parsing with v-prefix and build suffixes
  assertEquals(VersionComparator.compareSemanticVersions('v1.0.4', '1.0.4'), 0, 'TEST 14a: v1.0.4 == 1.0.4');
  assertEquals(VersionComparator.compareSemanticVersions('1.0.4+4', '1.0.4+5'), 0, 'TEST 14b: 1.0.4+4 == 1.0.4+5 (base version)');
  assertEquals(VersionComparator.compareSemanticVersions('1.0.4-beta', '1.0.4'), 0, 'TEST 14c: 1.0.4-beta == 1.0.4');
  assertEquals(VersionComparator.compareSemanticVersions('2.0.0', '1.99.99'), 1, 'TEST 14d: 2.0.0 > 1.99.99');
  assertEquals(VersionComparator.compareSemanticVersions('1.9.99', '1.10.0'), -1, 'TEST 14e: 1.9.99 < 1.10.0');

  // TEST 15: Post-update critical regression test: installed == latest -> No popup loop
  final preUpdate = VersionComparator.evaluate(
    currentVersion: '1.0.3',
    currentBuild: 3,
    latestVersion: '1.0.4',
    latestBuild: 4,
  );
  assertEquals(preUpdate.isUpdateAvailable, true, 'TEST 15a: Pre-update 1.0.3+3 -> update available');

  final postUpdate = VersionComparator.evaluate(
    currentVersion: '1.0.4',
    currentBuild: 4,
    latestVersion: '1.0.4',
    latestBuild: 4,
  );
  assertEquals(postUpdate.isUpdateAvailable, false, 'TEST 15b: Post-update 1.0.4+4 -> NO UPDATE POPUP');

  final repeatedRestart = VersionComparator.evaluate(
    currentVersion: '1.0.4',
    currentBuild: 2004, // ABI split ARM64 code
    latestVersion: '1.0.4',
    latestBuild: 4,
  );
  assertEquals(repeatedRestart.isUpdateAvailable, false, 'TEST 15c: Repeated restart with ARM64 2004 -> NO UPDATE POPUP');

  stdout.writeln('=== ALL 15 AUTOMATED TESTS PASSED SUCCESSFULLY! ===');
}
