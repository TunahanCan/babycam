import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production config excludes sensitive backup and unused native SDKs',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final secureStore =
        File('lib/core/security/miucam_secure_storage.dart').readAsStringSync();
    final featureFlags = File('lib/core/feature_flags.dart').readAsStringSync();
    final protocol =
        File('lib/core/protocol/miucam_protocol.dart').readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(pubspec, isNot(contains('bluetooth_low_energy:')));
    expect(pubspec, isNot(contains('just_audio:')));
    expect(pubspec, isNot(contains('web_socket_channel:')));
    expect(featureFlags, isNot(contains('MIUCAM_TEST_ENDPOINTS_ENABLED')));
    expect(protocol, isNot(contains("'/test")));
    expect(
      secureStore,
      contains('KeychainAccessibility.first_unlock_this_device'),
    );
  });

  test('release gate compiles both mobile platforms', () {
    final workflow = File('.github/workflows/ios-build.yml').readAsStringSync();

    expect(workflow, contains('flutter build appbundle --release'));
    expect(workflow, contains('flutter build ios --release --no-codesign'));
    expect(workflow, contains('flutter-version: 3.44.4'));
  });

  test('mobile platforms share the production application identity', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final xcode =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final kotlinFiles = Directory('android/app/src/main/kotlin/com/miucam/app')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.kt'))
        .toList();

    expect(gradle, contains('namespace = "com.miucam.app"'));
    expect(gradle, contains('applicationId = "com.miucam.app"'));
    expect(xcode, contains('PRODUCT_BUNDLE_IDENTIFIER = com.miucam.app;'));
    expect(kotlinFiles, isNotEmpty);
    for (final file in kotlinFiles) {
      expect(file.readAsStringSync(), startsWith('package com.miucam.app'));
    }
  });
}
