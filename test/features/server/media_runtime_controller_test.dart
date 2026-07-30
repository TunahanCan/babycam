import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';

import '../../support/deterministic_server_media_source.dart';

void main() {
  test('video-only demand starts camera path without microphone path',
      () async {
    var videoStarts = 0;
    var audioStarts = 0;
    final controller = MediaRuntimeController(
      onStartVideo: () async => videoStarts++,
      onStartAudio: () async => audioStarts++,
    );

    await controller.reconcile(
      const MediaResourceDemand(video: true, audio: false),
    );

    expect(controller.videoActive, isTrue);
    expect(controller.audioActive, isFalse);
    expect(videoStarts, 1);
    expect(audioStarts, 0);
  });

  test('audio-only demand starts microphone path without camera path',
      () async {
    var videoStarts = 0;
    var audioStarts = 0;
    final controller = MediaRuntimeController(
      onStartVideo: () async => videoStarts++,
      onStartAudio: () async => audioStarts++,
    );

    await controller.reconcile(
      const MediaResourceDemand(video: false, audio: true),
    );

    expect(controller.videoActive, isFalse);
    expect(controller.audioActive, isTrue);
    expect(videoStarts, 0);
    expect(audioStarts, 1);
  });

  test('in-flight start and stop are serialized without leaking resource',
      () async {
    final videoStarted = Completer<void>();
    final releaseStart = Completer<void>();
    final events = <String>[];
    final controller = MediaRuntimeController(
      onStartVideo: () async {
        events.add('start.begin');
        videoStarted.complete();
        await releaseStart.future;
        events.add('start.end');
      },
      onStopVideo: () async => events.add('stop'),
    );

    final start = controller.reconcile(
      const MediaResourceDemand(video: true, audio: false),
    );
    await videoStarted.future;
    final stop = controller.reconcile(MediaResourceDemand.none);
    releaseStart.complete();
    await Future.wait([start, stop]);

    expect(events, ['start.begin', 'start.end', 'stop']);
    expect(controller.isActive, isFalse);
  });

  test('platform suspend keeps requested demand and resume restores it',
      () async {
    var starts = 0;
    var stops = 0;
    final published = <MediaResourceDemand>[];
    final controller = MediaRuntimeController(
      onStartVideo: () async => starts++,
      onStopVideo: () async => stops++,
      onDemandChanged: (demand) async => published.add(demand),
    );
    const requested = MediaResourceDemand(video: true, audio: false);

    await controller.reconcile(requested);
    await controller.suspend();
    expect(controller.requestedDemand, requested);
    expect(controller.isActive, isFalse);
    await controller.resume();

    expect(controller.videoActive, isTrue);
    expect(starts, 2);
    expect(stops, 1);
    expect(published, [requested, MediaResourceDemand.none, requested]);
  });

  test('deterministic source honors independent video and audio demand',
      () async {
    final source = DeterministicServerMediaSource();
    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );

    expect(source.snapshot.videoFrames, 1);
    expect(source.snapshot.audioChunks, 0);

    await source.reconcile(
      video: false,
      audio: true,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    expect(source.snapshot.audioChunks, 1);
    await source.stop();
  });

  test('timed out start cannot block stop or a successor demand', () async {
    final firstStart = Completer<void>();
    var starts = 0;
    var stops = 0;
    var nativeVideoActive = false;
    final controller = MediaRuntimeController(
      operationTimeout: const Duration(milliseconds: 20),
      onStartVideo: () async {
        starts++;
        if (starts == 1) await firstStart.future;
        nativeVideoActive = true;
      },
      onStopVideo: () async {
        stops++;
        nativeVideoActive = false;
      },
    );

    await expectLater(
      controller.reconcile(
        const MediaResourceDemand(video: true, audio: false),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await controller.reconcile(MediaResourceDemand.none);
    await controller.reconcile(
      const MediaResourceDemand(video: true, audio: false),
    );

    expect(starts, 2);
    expect(stops, 1);
    expect(controller.videoActive, isTrue);
    expect(nativeVideoActive, isTrue);

    firstStart.complete();
    await pumpEventQueue();

    expect(controller.videoActive, isTrue);
    expect(nativeVideoActive, isTrue);
    expect(stops, 1);
  });

  test('late timed out start is compensated when no successor exists',
      () async {
    final firstStart = Completer<void>();
    var stops = 0;
    var nativeVideoActive = false;
    final controller = MediaRuntimeController(
      operationTimeout: const Duration(milliseconds: 20),
      onStartVideo: () async {
        await firstStart.future;
        nativeVideoActive = true;
      },
      onStopVideo: () async {
        stops++;
        nativeVideoActive = false;
      },
    );

    await expectLater(
      controller.reconcile(
        const MediaResourceDemand(video: true, audio: false),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await controller.reconcile(MediaResourceDemand.none);
    firstStart.complete();
    await _waitUntil(() => stops == 2);

    expect(controller.isActive, isFalse);
    expect(nativeVideoActive, isFalse);
  });

  test(
      'failed successor preserves timed-out start uncertainty until late cleanup',
      () async {
    final firstStart = Completer<void>();
    var starts = 0;
    var stops = 0;
    var nativeVideoActive = false;
    final controller = MediaRuntimeController(
      operationTimeout: const Duration(milliseconds: 20),
      onStartVideo: () async {
        starts++;
        if (starts == 1) {
          await firstStart.future;
          nativeVideoActive = true;
          return;
        }
        throw StateError('successor start failed');
      },
      onStopVideo: () async {
        stops++;
        nativeVideoActive = false;
      },
    );

    await expectLater(
      controller.reconcile(
        const MediaResourceDemand(video: true, audio: false),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(
      controller.reconcile(
        const MediaResourceDemand(video: true, audio: false),
      ),
      throwsA(isA<StateError>()),
    );
    firstStart.complete();
    await pumpEventQueue();
    expect(nativeVideoActive, isTrue);

    await controller.reconcile(MediaResourceDemand.none);

    expect(stops, 1);
    expect(nativeVideoActive, isFalse);
    expect(controller.isActive, isFalse);
  });

  test('failed stop stays uncertain and is retried until confirmed', () async {
    var stops = 0;
    var nativeVideoActive = false;
    final controller = MediaRuntimeController(
      onStartVideo: () async => nativeVideoActive = true,
      onStopVideo: () async {
        stops++;
        if (stops == 1) throw StateError('native stop failed');
        nativeVideoActive = false;
      },
    );

    await controller.reconcile(
      const MediaResourceDemand(video: true, audio: false),
    );
    await expectLater(
      controller.reconcile(MediaResourceDemand.none),
      throwsA(isA<StateError>()),
    );
    expect(controller.videoActive, isTrue);

    await _waitUntil(() => stops == 2);
    expect(nativeVideoActive, isFalse);
    expect(controller.isActive, isFalse);
  });

  test('timed-out stop late error keeps uncertainty and retries stop',
      () async {
    final firstStopRelease = Completer<void>();
    var stops = 0;
    var nativeVideoActive = false;
    final controller = MediaRuntimeController(
      operationTimeout: const Duration(milliseconds: 20),
      onStartVideo: () async => nativeVideoActive = true,
      onStopVideo: () async {
        stops++;
        if (stops == 1) {
          await firstStopRelease.future;
          throw StateError('late stop failure');
        }
        nativeVideoActive = false;
      },
    );

    await controller.reconcile(
      const MediaResourceDemand(video: true, audio: false),
    );
    await expectLater(
      controller.reconcile(MediaResourceDemand.none),
      throwsA(isA<TimeoutException>()),
    );
    firstStopRelease.complete();
    await _waitUntil(() => stops == 2);

    expect(nativeVideoActive, isFalse);
    expect(controller.isActive, isFalse);
  });

  test('timed-out start late error retries while demand is still wanted',
      () async {
    final firstStartRelease = Completer<void>();
    var starts = 0;
    var nativeVideoActive = false;
    final controller = MediaRuntimeController(
      operationTimeout: const Duration(milliseconds: 20),
      onStartVideo: () async {
        starts++;
        if (starts == 1) {
          await firstStartRelease.future;
          throw StateError('late start failure');
        }
        nativeVideoActive = true;
      },
    );

    await expectLater(
      controller.reconcile(
        const MediaResourceDemand(video: true, audio: false),
      ),
      throwsA(isA<TimeoutException>()),
    );
    firstStartRelease.complete();
    await _waitUntil(() => starts == 2);

    expect(nativeVideoActive, isTrue);
    expect(controller.videoActive, isTrue);
  });

  test('stop that throws after stopping is reasserted by successor start',
      () async {
    var starts = 0;
    var stops = 0;
    var nativeVideoActive = false;
    final controller = MediaRuntimeController(
      onStartVideo: () async {
        starts++;
        nativeVideoActive = true;
      },
      onStopVideo: () async {
        stops++;
        nativeVideoActive = false;
        throw StateError('stop response lost');
      },
    );

    await controller.reconcile(
      const MediaResourceDemand(video: true, audio: false),
    );
    await expectLater(
      controller.reconcile(MediaResourceDemand.none),
      throwsA(isA<StateError>()),
    );
    await controller.reconcile(
      const MediaResourceDemand(video: true, audio: false),
    );

    expect(starts, 2);
    expect(stops, 1);
    expect(nativeVideoActive, isTrue);
    expect(controller.videoActive, isTrue);
  });

  test(
      'late timed out stop reasserts latest start without reopening after stop',
      () async {
    final firstStop = Completer<void>();
    var starts = 0;
    var stops = 0;
    var nativeVideoActive = false;
    final controller = MediaRuntimeController(
      operationTimeout: const Duration(milliseconds: 20),
      onStartVideo: () async {
        starts++;
        nativeVideoActive = true;
      },
      onStopVideo: () async {
        stops++;
        if (stops == 1) await firstStop.future;
        nativeVideoActive = false;
      },
    );

    await controller.reconcile(
      const MediaResourceDemand(video: true, audio: false),
    );
    await expectLater(
      controller.reconcile(MediaResourceDemand.none),
      throwsA(isA<TimeoutException>()),
    );
    await controller.reconcile(
      const MediaResourceDemand(video: true, audio: false),
    );
    expect(nativeVideoActive, isTrue);

    firstStop.complete();
    await _waitUntil(() => starts == 3);
    expect(nativeVideoActive, isTrue);

    await controller.reconcile(MediaResourceDemand.none);
    await pumpEventQueue();
    expect(nativeVideoActive, isFalse);
    expect(controller.isActive, isFalse);
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      fail('Condition was not met within $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
