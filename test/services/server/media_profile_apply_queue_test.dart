import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/services/server/media_profile_apply_queue.dart';

void main() {
  test('profile apply islemlerini ayni anda calistirmaz', () async {
    final queue = MediaProfileApplyQueue();
    final firstRelease = Completer<void>();
    var concurrent = 0;
    var maxConcurrent = 0;
    final applied = <String>[];

    final first = queue.enqueue((_) async {
      concurrent++;
      maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
      applied.add('first-start');
      await firstRelease.future;
      applied.add('first-end');
      concurrent--;
    });
    final second = queue.enqueue((_) async {
      concurrent++;
      maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
      applied.add('second');
      concurrent--;
    });

    await Future<void>.delayed(Duration.zero);
    expect(applied, ['first-start']);
    firstRelease.complete();
    await Future.wait([first, second]);

    expect(maxConcurrent, 1);
    expect(applied, ['first-start', 'first-end', 'second']);
  });

  test('invalidate eski queued profile kararini calistirmaz', () async {
    final queue = MediaProfileApplyQueue();
    final firstRelease = Completer<void>();
    var staleRan = false;

    final first = queue.enqueue((_) => firstRelease.future);
    final stale = queue.enqueue((_) async {
      staleRan = true;
    });
    await Future<void>.delayed(Duration.zero);

    queue.invalidate();
    firstRelease.complete();
    await Future.wait([first, stale]);

    expect(staleRan, isFalse);
  });

  test('failed apply sonraki profile kararini engellemez', () async {
    final queue = MediaProfileApplyQueue();
    var nextRan = false;

    final failed = queue.enqueue((_) async => throw StateError('camera'));
    final next = queue.enqueue((_) async {
      nextRan = true;
    });

    await expectLater(failed, throwsStateError);
    await next;
    expect(nextRan, isTrue);
  });

  test('yalniz FPS degisimi camera restart gerektirmez', () {
    const policy = MediaProfileCameraRestartPolicy();
    final previous =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.balanced);
    final fpsOnly = previous.copyWith(targetFps: previous.targetFps - 2);
    final presetChange = previous.copyWith(cameraPresetKey: 'low');

    expect(policy.requiresRestart(previous, fpsOnly), isFalse);
    expect(policy.requiresRestart(previous, presetChange), isTrue);
    expect(
      policy.captureFps(
        deviceProfile: previous,
        activeProfile: previous.copyWith(targetFps: 5),
      ),
      10,
    );
  });
}
