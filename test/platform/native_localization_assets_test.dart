import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/l10n/app_strings.dart';

const _androidStringKeys = {
  'miucam_server_channel_name',
  'miucam_alert_connection_channel_name',
  'miucam_server_channel_description',
  'miucam_alert_connection_channel_description',
  'miucam_runtime_camera_microphone_playback',
  'miucam_runtime_camera_microphone',
  'miucam_runtime_camera_playback',
  'miucam_runtime_microphone_playback',
  'miucam_runtime_camera',
  'miucam_runtime_microphone',
  'miucam_runtime_playback',
  'miucam_runtime_server',
  'miucam_runtime_alerts',
  'miucam_runtime_stopping',
  'miucam_runtime_title_media',
  'miucam_runtime_title_server',
  'miucam_runtime_title_alerts',
};

const _iosPermissionKeys = {
  'NSCameraUsageDescription',
  'NSLocalNetworkUsageDescription',
  'NSMicrophoneUsageDescription',
};

void main() {
  test('Android foreground-service copy is complete in every app language', () {
    // ar-SA and ar-QA intentionally resolve to the same neutral Arabic pack.
    final localeDirectories = AppStrings.supportedLocales.map((locale) =>
        locale.languageCode == 'en'
            ? 'values'
            : 'values-${locale.languageCode}');
    final fallback = _androidStrings(
      File('android/app/src/main/res/values/strings.xml').readAsStringSync(),
    );

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
        if (directory != 'values') {
          expect(entry.value, isNot(fallback[entry.key]),
              reason: '$directory:${entry.key} falls back to English');
        }
        expect(_nativePlaceholders(entry.value),
            _nativePlaceholders(fallback[entry.key]!),
            reason: '$directory:${entry.key} changes native placeholders');
      }
    }

    final service = File(
      'android/app/src/main/kotlin/com/miucam/app/'
      'MiuCamForegroundService.kt',
    ).readAsStringSync();
    for (final key in _androidStringKeys) {
      expect(service, contains('R.string.$key'), reason: '$key is unused');
    }
    expect(service, isNot(contains('MiuCam Bildirim Bağlantısı')));
    expect(service, isNot(contains('Bebek odası bildirimleri')));
  });

  test('iOS permission copy is localized and included in the Runner bundle',
      () {
    final localeDirectories = AppStrings.supportedLocales.map((locale) =>
        locale.languageCode == 'zh' ? 'zh-Hans' : locale.languageCode);
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
      expect(values['NSMicrophoneUsageDescription'], isNot(contains('Server')),
          reason:
              '$locale microphone consent should describe both nursery audio and talk');
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
    expect(fallback, contains('MiuCam uses the camera'));
    expect(fallback, contains('MiuCam uses your local network'));
    expect(fallback, contains('MiuCam uses the microphone'));
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

List<String> _nativePlaceholders(String value) => (RegExp(r'%(?:\d+\$)?[sdif@]')
    .allMatches(value)
    .map((match) => match.group(0)!)
    .toList()
  ..sort());
