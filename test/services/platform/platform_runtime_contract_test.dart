import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/platform/platform_runtime_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      'playbackDemand': true,
      'audioOutputActive': true,
      'supportsAudioOutputInBackground': true,
      'supportsMicrophoneInBackground': true,
      'nativeServiceMediaAvailable': true,
      'serviceOwnsMediaHardware': true,
      'serviceOwnsNativeMediaHardware': true,
      'nativeCameraRequested': true,
      'nativeCameraActive': true,
      'nativeMicrophoneRequested': false,
      'nativeMicrophoneActive': false,
      'activityAttached': false,
      'serviceOwnsEngine': true,
      'engineAvailable': true,
    });

    expect(snapshot.cameraMustPauseWhenBackgrounded, isFalse);
    expect(snapshot.serviceOwnsEngine, isTrue);
    expect(snapshot.backgroundRecoveryAfterProcessDeath, isFalse);
    expect(snapshot.playbackDemand, isTrue);
    expect(snapshot.audioOutputActive, isTrue);
    expect(snapshot.supportsAudioOutputInBackground, isTrue);
    expect(snapshot.supportsMicrophoneInBackground, isTrue);
    expect(snapshot.nativeServiceMediaAvailable, isTrue);
    expect(snapshot.serviceOwnsMediaHardware, isTrue);
    expect(snapshot.serviceOwnsNativeMediaHardware, isTrue);
    expect(snapshot.nativeCameraActive, isTrue);
    expect(snapshot.nativeMicrophoneActive, isFalse);
  });

  test('parses external WebRTC ownership separately from native capture', () {
    final snapshot = PlatformRuntimeSnapshot.fromMap(const {
      'platform': 'android',
      'applicationState': 'background',
      'supportsCameraInBackground': true,
      'foregroundServiceActive': true,
      'cameraDemand': true,
      'microphoneDemand': false,
      'serviceOwnsMediaHardware': true,
      'serviceOwnsNativeMediaHardware': false,
      'externalCameraCaptureDemand': true,
      'externalMicrophoneCaptureDemand': false,
      'externalMediaCaptureDemand': true,
      'nativeCameraRequested': false,
      'nativeCameraActive': false,
    });

    expect(snapshot.serviceOwnsMediaHardware, isTrue);
    expect(snapshot.serviceOwnsNativeMediaHardware, isFalse);
    expect(snapshot.externalMediaCaptureDemand, isTrue);
    expect(snapshot.externalCameraCaptureDemand, isTrue);
    expect(snapshot.nativeCameraActive, isFalse);
    expect(snapshot.userVisibleContract, contains('WebRTC'));
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

  test('background iOS snapshot bootstraps a media pause', () {
    final event = PlatformRuntimeEvent.fromMap(const {
      'type': 'snapshot',
      'timestampMs': 123,
      'sequence': 1,
      'platform': 'ios',
      'applicationState': 'background',
    });

    expect(event.requiresMediaPause, isTrue);
    expect(event.requestsMediaRecovery, isFalse);
  });

  test('setMediaDemand forwards exact playback demand', () async {
    const channel = MethodChannel('miucam/platform_runtime_test');
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await const PlatformRuntimeContract(methodChannel: channel).setMediaDemand(
      active: true,
      camera: false,
      microphone: true,
      playback: true,
    );

    expect(received?.method, 'setMediaDemand');
    expect(received?.arguments, {
      'active': true,
      'camera': false,
      'microphone': true,
      'playback': true,
      'nativeCameraCapture': false,
      'nativeMicrophoneCapture': true,
    });
  });

  test('setMediaDemand separates WebRTC FGS type from native capture',
      () async {
    const channel = MethodChannel('miucam/platform_runtime_external_test');
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await const PlatformRuntimeContract(methodChannel: channel).setMediaDemand(
      active: true,
      camera: true,
      microphone: true,
      nativeCameraCapture: false,
      nativeMicrophoneCapture: false,
    );

    expect(received?.arguments, {
      'active': true,
      'camera': true,
      'microphone': true,
      'playback': false,
      'nativeCameraCapture': false,
      'nativeMicrophoneCapture': false,
    });
  });

  test('setServerDemand owns Android LAN host independently from media',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('miucam/platform_runtime_server_test');
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await const PlatformRuntimeContract(methodChannel: channel)
        .setServerDemand(active: true);

    expect(received?.method, 'setServerDemand');
    expect(received?.arguments, {'active': true});
  });

  test('setServerDemand publishes iOS room ownership for capability reporting',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('miucam/platform_runtime_ios_server_test');
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await const PlatformRuntimeContract(methodChannel: channel)
        .setServerDemand(active: true);

    expect(received?.method, 'setServerDemand');
    expect(received?.arguments, {'active': true});
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

  test('coordinator retries after a lifecycle callback fails', () async {
    final events = StreamController<PlatformRuntimeEvent>();
    final calls = <String>[];
    var pauseAttempts = 0;
    final coordinator = PlatformMediaLifecycleCoordinator(
      events: events.stream,
      pauseMedia: (reason) async {
        pauseAttempts++;
        calls.add('pause:$reason');
        if (pauseAttempts == 1) throw StateError('first pause failed');
      },
      recoverMedia: (reason) async => calls.add('recover:$reason'),
    )..start();

    events
      ..add(_event('mediaPauseRequired', 'first'))
      ..add(_event('mediaPauseRequired', 'retry'))
      ..add(_event('mediaRecoveryRequested', 'foreground'));
    await events.close();
    await Future<void>.delayed(Duration.zero);
    await coordinator.dispose();

    expect(calls, [
      'pause:first',
      'pause:retry',
      'recover:foreground',
    ]);
    expect(coordinator.pausedByPlatform, isFalse);
  });

  test('permanent audio focus loss reaches the output owner once', () async {
    final events = StreamController<PlatformRuntimeEvent>();
    final losses = <String>[];
    final coordinator = PlatformMediaLifecycleCoordinator(
      events: events.stream,
      pauseMedia: (_) async {},
      recoverMedia: (_) async {},
      onAudioOutputLost: (event) async => losses.add(event.type),
    )..start();

    events.add(const PlatformRuntimeEvent(
      type: 'audioFocusLost',
      timestampMs: 1,
      sequence: 1,
      details: {'permanent': true},
    ));
    await events.close();
    await Future<void>.delayed(Duration.zero);
    await coordinator.dispose();

    expect(losses, ['audioFocusLost']);
  });
}

PlatformRuntimeEvent _event(String type, String reason) => PlatformRuntimeEvent(
      type: type,
      timestampMs: 0,
      sequence: 0,
      details: {'reason': reason},
    );
