import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/platform_role_shutdown_barrier.dart';
import 'package:miucam/services/platform/platform_runtime_contract.dart';

void main() {
  for (final resource in [
    'serverDemand',
    'alertDemand',
    'cameraDemand',
    'microphoneDemand',
    'playbackDemand',
    'audioOutputActive',
    'nativeCameraRequested',
    'nativeMicrophoneRequested',
    'nativeCameraActive',
    'nativeMicrophoneActive',
    'externalCameraCaptureDemand',
    'externalMicrophoneCaptureDemand',
    'externalMediaCaptureDemand',
    'serviceOwnsMediaHardware',
    'serviceOwnsNativeMediaHardware',
    'foregroundServiceActive',
  ]) {
    test('waits for $resource to stop before handing over', () async {
      var reads = 0;
      final stopped = Completer<PlatformRuntimeSnapshot>();
      final barrier = PlatformRoleShutdownBarrier(
        pollInterval: Duration.zero,
        readSnapshot: () async {
          reads++;
          return reads == 1 ? _snapshot({resource: true}) : stopped.future;
        },
      );
      var complete = false;
      final waiting = barrier.waitUntilStopped().then((_) => complete = true);
      await Future<void>.delayed(Duration.zero);
      expect(complete, isFalse);
      stopped.complete(_snapshot());
      await waiting;
      expect(reads, 2);
    });
  }

  test('native command failure is not an idle confirmation', () async {
    final barrier = PlatformRoleShutdownBarrier(
      readSnapshot: () async => throw StateError('Native bridge failed'),
    );
    await expectLater(barrier.waitUntilStopped(), throwsStateError);
  });

  test('a stalled snapshot is bounded and blocks the next role', () async {
    final barrier = PlatformRoleShutdownBarrier(
      timeout: const Duration(milliseconds: 20),
      readSnapshot: () => Completer<PlatformRuntimeSnapshot>().future,
    );
    await expectLater(
        barrier.waitUntilStopped(), throwsA(isA<TimeoutException>()));
  });

  test('native resources that stay active fail closed at the deadline',
      () async {
    final barrier = PlatformRoleShutdownBarrier(
      timeout: const Duration(milliseconds: 20),
      pollInterval: const Duration(milliseconds: 2),
      readSnapshot: () async => _snapshot({'alertDemand': true}),
    );
    await expectLater(
        barrier.waitUntilStopped(), throwsA(isA<TimeoutException>()));
  });
}

PlatformRuntimeSnapshot _snapshot([Map<String, Object?> values = const {}]) =>
    PlatformRuntimeSnapshot.fromMap({
      'platform': 'android',
      // The same app engine can serve either role after all work has stopped.
      'engineAvailable': true,
      'serviceOwnsEngine': true,
      ...values,
    });
