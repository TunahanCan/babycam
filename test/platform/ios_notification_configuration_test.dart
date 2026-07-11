import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS forwards local notification presentation and taps to Flutter', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate, contains('import UserNotifications'));
    expect(
      appDelegate,
      contains('UNUserNotificationCenter.current().delegate = self'),
    );
  });

  test('iOS notification permission implementation is compiled in', () {
    final podfile = File('ios/Podfile').readAsStringSync();

    expect(podfile, contains("'PERMISSION_NOTIFICATIONS=1'"));
    expect(podfile, contains("platform :ios, '13.0'"));
  });
}
