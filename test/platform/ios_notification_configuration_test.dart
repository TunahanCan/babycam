import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS delegates local notification presentation and taps to Flutter', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate, contains('import UserNotifications'));
    expect(
      appDelegate,
      contains('UNUserNotificationCenter.current().delegate = self'),
    );
    expect(
      appDelegate,
      isNot(contains('willPresent notification: UNNotification')),
      reason: 'FlutterAppDelegate must forward the plugin-specific present* '
          'flags instead of bypassing them with an app-wide override.',
    );
  });

  test('iOS notification permission implementation is compiled in', () {
    final podfile = File('ios/Podfile').readAsStringSync();

    expect(podfile, contains("'PERMISSION_NOTIFICATIONS=1'"));
    expect(podfile, contains("platform :ios, '13.0'"));
  });
}
