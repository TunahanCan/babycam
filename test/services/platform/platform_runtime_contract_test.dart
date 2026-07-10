import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/platform/platform_runtime_contract.dart';

void main() {
  test('parses the iOS foreground-only camera contract', () {
    final snapshot = PlatformRuntimeSnapshot.fromMap(const {
      'platform': 'ios',
      'applicationState': 'background',
      'supportsCameraInBackground': false,
      'cameraRequiresForegroundStart': true,
      'backgroundRecoveryAfterProcessDeath': false,
      'foregroundServiceActive': false,
      'cameraDemand': true,
      'microphoneDemand': true,
      'activityAttached': false,
      'serviceOwnsEngine': false,
      'engineAvailable': true,
      'contractMessage': 'foreground only',
    });

    expect(snapshot.platform, PlatformRuntimeKind.ios);
    expect(snapshot.cameraMustPauseWhenBackgrounded, isTrue);
    expect(snapshot.userVisibleContract, 'foreground only');
  });

  test('parses Android service engine ownership', () {
    final snapshot = PlatformRuntimeSnapshot.fromMap(const {
      'platform': 'android',
      'applicationState': 'background',
      'supportsCameraInBackground': true,
      'cameraRequiresForegroundStart': true,
      'backgroundRecoveryAfterProcessDeath': false,
      'foregroundServiceActive': true,
      'cameraDemand': true,
      'microphoneDemand': false,
      'activityAttached': false,
      'serviceOwnsEngine': true,
      'engineAvailable': true,
    });

    expect(snapshot.cameraMustPauseWhenBackgrounded, isFalse);
    expect(snapshot.serviceOwnsEngine, isTrue);
    expect(snapshot.backgroundRecoveryAfterProcessDeath, isFalse);
  });

  test('event parser keeps native telemetry details', () {
    final event = PlatformRuntimeEvent.fromMap(const {
      'type': 'audioRouteChanged',
      'timestampMs': 123,
      'sequence': 7,
      'reason': 2,
    });

    expect(event.isAudioLifecycleEvent, isTrue);
    expect(event.details['reason'], 2);
    expect(event.sequence, 7);
  });

  test('coordinator serializes one pause and one recovery', () async {
    final events = StreamController<PlatformRuntimeEvent>();
    final calls = <String>[];
    final coordinator = PlatformMediaLifecycleCoordinator(
      events: events.stream,
      pauseMedia: (reason) async => calls.add('pause:$reason'),
      recoverMedia: (reason) async => calls.add('recover:$reason'),
    )..start();

    events
      ..add(_event('mediaPauseRequired', 'background'))
      ..add(_event('mediaPauseRequired', 'duplicate'))
      ..add(_event('mediaRecoveryRequested', 'foreground'));
    await events.close();
    await Future<void>.delayed(Duration.zero);
    await coordinator.dispose();

    expect(calls, ['pause:background', 'recover:foreground']);
    expect(coordinator.pausedByPlatform, isFalse);
  });
}

PlatformRuntimeEvent _event(String type, String reason) => PlatformRuntimeEvent(
      type: type,
      timestampMs: 0,
      sequence: 0,
      details: {'reason': reason},
    );
