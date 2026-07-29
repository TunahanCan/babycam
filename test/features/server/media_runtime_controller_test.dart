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
}
