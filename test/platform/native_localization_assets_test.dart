import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _androidStringKeys = {
  'mimicam_server_channel_name',
  'mimicam_alert_connection_channel_name',
  'mimicam_server_channel_description',
  'mimicam_alert_connection_channel_description',
  'mimicam_runtime_camera_microphone_playback',
  'mimicam_runtime_camera_microphone',
  'mimicam_runtime_camera_playback',
  'mimicam_runtime_microphone_playback',
  'mimicam_runtime_camera',
  'mimicam_runtime_microphone',
  'mimicam_runtime_playback',
  'mimicam_runtime_server',
  'mimicam_runtime_alerts',
  'mimicam_runtime_stopping',
  'mimicam_runtime_title_media',
  'mimicam_runtime_title_server',
  'mimicam_runtime_title_alerts',
};

const _iosPermissionKeys = {
  'NSCameraUsageDescription',
  'NSLocalNetworkUsageDescription',
  'NSMicrophoneUsageDescription',
};

void main() {
  test('Android foreground-service copy is complete in every app language', () {
    const localeDirectories = [
      'values',
      'values-tr',
      'values-zh',
      'values-hi',
      'values-es',
      'values-fr',
      'values-de',
      'values-ar',
    ];

    for (final directory in localeDirectories) {
      final file = File('android/app/src/main/res/$directory/strings.xml');
      expect(file.existsSync(), isTrue, reason: '$directory is missing');
      final values = _androidStrings(file.readAsStringSync());
      expect(
        values.keys.toSet(),
        _androidStringKeys,
        reason: '$directory has an incomplete or stale foreground-service pack',
      );
      for (final entry in values.entries) {
        expect(entry.value.trim(), isNotEmpty,
            reason: '$directory:${entry.key} is blank');
      }
    }

    final service = File(
      'android/app/src/main/kotlin/com/mimicam/app/'
      'MimiCamForegroundService.kt',
    ).readAsStringSync();
    for (final key in _androidStringKeys) {
      expect(service, contains('R.string.$key'), reason: '$key is unused');
    }
    expect(service, isNot(contains('MimiCam Bildirim Bağlantısı')));
    expect(service, isNot(contains('Bebek odası bildirimleri')));
  });

  test('iOS permission copy is localized and included in the Runner bundle',
      () {
    const localeDirectories = [
      'en',
      'tr',
      'zh-Hans',
      'hi',
      'es',
      'fr',
      'de',
      'ar',
    ];
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    for (final locale in localeDirectories) {
      final file = File('ios/Runner/$locale.lproj/InfoPlist.strings');
      expect(file.existsSync(), isTrue, reason: '$locale is missing');
      final values = _infoPlistStrings(file.readAsStringSync());
      expect(values.keys.toSet(), _iosPermissionKeys,
          reason: '$locale has an incomplete iOS permission pack');
      for (final entry in values.entries) {
        expect(entry.value.trim(), isNotEmpty,
            reason: '$locale:${entry.key} is blank');
      }
      expect(
        project,
        contains('$locale.lproj/InfoPlist.strings'),
        reason: '$locale is not referenced by the Xcode project',
      );
    }

    expect(project, contains('InfoPlist.strings in Resources'));
    final knownRegions = RegExp(
      r'knownRegions = \(([\s\S]*?)\);',
    ).firstMatch(project)?.group(1);
    expect(knownRegions, isNotNull);
    for (final locale in localeDirectories) {
      expect(knownRegions, contains(locale),
          reason: '$locale is absent from knownRegions');
    }

    final fallback = File('ios/Runner/Info.plist').readAsStringSync();
    expect(fallback, contains('MimiCam uses the camera'));
    expect(fallback, contains('MimiCam uses your local network'));
    expect(fallback, contains('MimiCam uses the microphone'));
  });
}

Map<String, String> _androidStrings(String source) => {
      for (final match in RegExp(
        r'<string\s+name="([^"]+)">([\s\S]*?)</string>',
      ).allMatches(source))
        match.group(1)!: match.group(2)!,
    };

Map<String, String> _infoPlistStrings(String source) => {
      for (final match in RegExp(
        r'^"([^"]+)"\s*=\s*"([^"]*)";$',
        multiLine: true,
      ).allMatches(source))
        match.group(1)!: match.group(2)!,
    };
