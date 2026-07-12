import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS declares real background audio capture and playback support', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(infoPlist, contains('<key>UIBackgroundModes</key>'));
    expect(infoPlist, contains('<string>audio</string>'));
    expect(appDelegate, contains('"supportsMicrophoneInBackground": true'));
    expect(appDelegate, contains('"supportsAudioOutputInBackground": true'));
    expect(appDelegate, contains('"preserveAudioInBackground": true'));
    expect(
      appDelegate,
      contains('currentServerDemand && currentMicrophoneDemand'),
    );
    expect(
      appDelegate,
      contains('"supportsServerInBackground": serverBackgroundSupported'),
    );
    expect(
      appDelegate,
      isNot(contains('"supportsServerInBackground": true')),
    );
  });

  test('iOS PCM playback is not paused merely because the screen locks', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(
      appDelegate,
      isNot(contains('UIApplication.willResignActiveNotification')),
    );
    expect(appDelegate, isNot(contains('suspendOutputForBackground')));
    expect(appDelegate, isNot(contains('outputRequiresForeground')));
  });

  test('iOS server does not block screen locking with a wakelock', () {
    final server = File('lib/services/mimicam_server.dart').readAsStringSync();

    expect(
      server,
      contains('defaultTargetPlatform != TargetPlatform.iOS'),
    );
  });
}
