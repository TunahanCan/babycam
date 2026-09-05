import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/analysis/video/luma_frame.dart';
import 'package:miucam/features/server/media/server_media_source.dart';
import 'package:miucam/services/platform/android_service_media_source.dart';

void main() {
  test('native torch is unavailable before video capture and awaits hardware',
      () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(bridge: bridge);
    addTearDown(bridge.close);
    addTearDown(source.stop);

    expect(await source.setTorchEnabled(true), isFalse);
    expect(bridge.torchRequests, isEmpty);
    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );

    bridge.torchCompletion = Completer<bool>();
    var completed = false;
    final enabled = source.setTorchEnabled(true).then((value) {
      completed = true;
      return value;
    });
    await _waitUntil(() => bridge.torchRequests.isNotEmpty);
    expect(completed, isFalse);
    bridge.torchCompletion!.complete(true);
    expect(await enabled, isTrue);

    bridge.torchCompletion = null;
    expect(await source.setTorchEnabled(false), isTrue);
    expect(bridge.torchRequests, [true, false]);
  });

  test('native torch failure or timeout returns the screen fallback signal',
      () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      nativeOperationTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(bridge.close);
    addTearDown(source.stop);
    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );

    bridge.torchCompletion = Completer<bool>()..complete(false);
    expect(await source.setTorchEnabled(true), isFalse);
    bridge.torchCompletion = Completer<bool>();
    expect(await source.setTorchEnabled(true), isFalse);
    bridge.torchCompletion!.complete(false);
    bridge.torchCompletion = null;
    expect(await source.setTorchEnabled(false), isTrue);
  });

  test('forwards service JPEG and PCM with exact independent demand', () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(bridge: bridge);
    final videoFrames = <Uint8List>[];
    final audioChunks = <Uint8List>[];
    final previewFrames = <Uint8List>[];
    final lumaFrames = <LumaFrame>[];
    final previewSubscription = source.previewFrames.listen(previewFrames.add);
    final lumaSubscription = source.lumaFrames.listen(lumaFrames.add);

    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: videoFrames.add,
      onAudioChunk: audioChunks.add,
    );
    bridge.emit({
      'type': 'video',
      'timestampMs': 101,
      'bytes': Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      'lumaBytes': Uint8List.fromList([10, 20, 30, 40]),
      'lumaWidth': 2,
      'lumaHeight': 2,
    });
    bridge.emit({
      'type': 'audio',
      'timestampMs': 102,
      'bytes': Uint8List.fromList([1, 0, 2, 0]),
    });

    expect(videoFrames, hasLength(1));
    expect(previewFrames, hasLength(1));
    expect(lumaFrames, hasLength(1));
    expect(lumaFrames.single.width, 2);
    expect(lumaFrames.single.height, 2);
    expect(lumaFrames.single.rowStride, 2);
    expect(lumaFrames.single.pixelStride, 1);
    expect(lumaFrames.single.yPlane, [10, 20, 30, 40]);
    expect(source.latestPreviewFrame, videoFrames.single);
    expect(audioChunks, isEmpty);
    expect(source.videoActive, isTrue);
    expect(source.audioActive, isFalse);
    expect(source.snapshot.videoFrames, 1);
    expect(source.snapshot.lastVideoFrameAtMs, 101);
    expect(
      bridge.consumerDemands.single,
      (video: true, audio: false, encodeVideo: true),
    );
    expect(bridge.readyDemands.single, (video: true, audio: false));

    await source.reconcile(
      video: false,
      audio: true,
      onVideoFrame: videoFrames.add,
      onAudioChunk: audioChunks.add,
    );
    bridge.emit({
      'type': 'video',
      'bytes': Uint8List.fromList([9]),
    });
    bridge.emit({
      'type': 'audio',
      'timestampMs': 202,
      'bytes': Uint8List.fromList([3, 0, 4, 0]),
    });

    expect(videoFrames, hasLength(1));
    expect(source.latestPreviewFrame, isNull);
    expect(audioChunks, hasLength(1));
    expect(source.videoActive, isFalse);
    expect(source.audioActive, isTrue);
    expect(source.snapshot.audioChunks, 1);
    expect(source.snapshot.lastAudioChunkAtMs, 202);
    expect(bridge.attachCalls, 1);

    await source.stop();
    await previewSubscription.cancel();
    await lumaSubscription.cancel();
    await bridge.close();
  });

  test(
      'preserves native audio timing and marks a dropped audio sequence as a gap',
      () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(bridge: bridge);
    final metadata = <ServerAudioChunkMetadata>[];

    await source.reconcile(
      video: false,
      audio: true,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {
        metadata.add(source.currentAudioChunkMetadata!);
      },
    );
    expect(source.currentAudioChunkMetadata, isNull);

    bridge.emit({
      'type': 'audio',
      'audioSequence': 41,
      'timestampMs': 10020,
      'capturedAtMonoUs': 5020000,
      'sampleRate': 16000,
      'channels': 1,
      'bytes': Uint8List(640),
    });
    bridge.emit({
      'type': 'audio',
      'audioSequence': 42,
      'timestampMs': 10040,
      'capturedAtMonoUs': 5040000,
      'sampleRate': 16000,
      'channels': 1,
      'bytes': Uint8List(640),
    });
    bridge.emit({
      'type': 'audio',
      'audioSequence': 44,
      'timestampMs': 10080,
      'capturedAtMonoUs': 5080000,
      'sampleRate': 16000,
      'channels': 1,
      'bytes': Uint8List(640),
    });

    expect(metadata, hasLength(3));
    expect(metadata[0].capturedAtMs, 10020);
    expect(metadata[0].capturedAtMonoUs, 5020000);
    expect(metadata[0].sampleRate, 16000);
    expect(metadata[0].channels, 1);
    expect(metadata[0].discontinuityBefore, isTrue);
    expect(metadata[1].discontinuityBefore, isFalse);
    expect(metadata[2].sequence, 44);
    expect(metadata[2].discontinuityBefore, isTrue);
    expect(source.currentAudioChunkMetadata, isNull);

    await source.stop();
    await bridge.close();
  });

  test('monotonic capture stall and microphone restart break audio continuity',
      () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(bridge: bridge);
    final discontinuities = <bool>[];

    await source.reconcile(
      video: false,
      audio: true,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {
        discontinuities
            .add(source.currentAudioChunkMetadata!.discontinuityBefore);
      },
    );

    void emitAudio(int sequence, int capturedAtMonoUs) {
      bridge.emit({
        'type': 'audio',
        'audioSequence': sequence,
        'timestampMs': 20000 + sequence * 20,
        'capturedAtMonoUs': capturedAtMonoUs,
        'sampleRate': 16000,
        'channels': 1,
        'bytes': Uint8List(640),
      });
    }

    emitAudio(1, 1000000);
    emitAudio(2, 1020000);
    emitAudio(3, 1400000);
    bridge.emit({
      'type': 'captureState',
      'cameraActive': false,
      'microphoneActive': false,
    });
    bridge.emit({
      'type': 'captureState',
      'cameraActive': false,
      'microphoneActive': true,
    });
    emitAudio(4, 1420000);

    expect(discontinuities, [true, false, true, true]);

    await source.stop();
    await bridge.close();
  });

  test('native readiness failure cleans up and a later demand can retry',
      () async {
    final bridge = _FakeBridge()..readyFailuresRemaining = 1;
    final source = AndroidServiceMediaSource(bridge: bridge);
    final errors = <Object>[];

    await expectLater(
      source.reconcile(
        video: true,
        audio: false,
        onVideoFrame: (_) {},
        onAudioChunk: (_) {},
        onError: (error, _) => errors.add(error),
      ),
      throwsA(isA<StateError>()),
    );
    expect(source.isActive, isFalse);
    expect(errors, hasLength(1));
    expect(bridge.detachCalls, 1);

    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    expect(source.isActive, isTrue);
    expect(bridge.attachCalls, 2);

    await source.stop();
    await bridge.close();
  });

  test('hanging native attach does not block successor reconciliation',
      () async {
    final bridge = _FakeBridge()..hangFirstAttach = true;
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      nativeOperationTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      source.reconcile(
        video: true,
        audio: false,
        onVideoFrame: (_) {},
        onAudioChunk: (_) {},
      ),
      throwsA(isA<TimeoutException>()),
    );

    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    expect(source.videoActive, isTrue);
    expect(bridge.attachCalls, 2);

    bridge.releaseFirstAttach();
    await _waitUntil(
      () =>
          bridge.attachCalls >= 3 &&
          bridge.nativeAttached &&
          bridge.nativeVideoDemand,
    );

    expect(source.videoActive, isTrue);
    expect(bridge.detachCalls, 1);
    await source.stop();
    await bridge.close();
  });

  test('late native attach is detached when demand was rolled back', () async {
    final bridge = _FakeBridge()..hangFirstAttach = true;
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      nativeOperationTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      source.reconcile(
        video: true,
        audio: false,
        onVideoFrame: (_) {},
        onAudioChunk: (_) {},
      ),
      throwsA(isA<TimeoutException>()),
    );
    await source.stop();
    bridge.releaseFirstAttach();
    await _waitUntil(() => bridge.detachCalls == 1);

    expect(source.isActive, isFalse);
    await bridge.close();
  });

  test(
      'unexpected event stream close reattaches and restores exact media demand',
      () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      reconnectBackoff: const [Duration.zero],
    );
    final errors = <Object>[];
    final videoFrames = <Uint8List>[];
    final audioChunks = <Uint8List>[];
    final audioDiscontinuities = <bool>[];

    await source.reconcile(
      video: true,
      audio: true,
      onVideoFrame: videoFrames.add,
      onAudioChunk: (bytes) {
        audioChunks.add(bytes);
        audioDiscontinuities
            .add(source.currentAudioChunkMetadata!.discontinuityBefore);
      },
      onError: (error, _) => errors.add(error),
    );
    bridge.emit({
      'type': 'video',
      'timestampMs': 100,
      'bytes': Uint8List.fromList([1]),
    });
    bridge.emit({
      'type': 'audio',
      'audioSequence': 7,
      'timestampMs': 100,
      'capturedAtMonoUs': 1000000,
      'sampleRate': 16000,
      'channels': 1,
      'bytes': Uint8List(640),
    });

    bridge.readyFailuresRemaining = 2;
    await bridge.closeCurrentEventStream();
    await bridge.waitForReadyCalls(4);
    await pumpEventQueue();

    expect(bridge.attachCalls, 4);
    expect(
      bridge.consumerDemands.last,
      (video: true, audio: true, encodeVideo: true),
    );
    expect(bridge.readyDemands.last, (video: true, audio: true));
    expect(source.videoActive, isTrue);
    expect(source.audioActive, isTrue);
    expect(
      errors.map((error) => error.toString()),
      contains(contains('event stream closed unexpectedly')),
    );
    expect(
      errors.map((error) => error.toString()),
      contains(contains('recovery attempt 1 failed')),
    );
    expect(
      errors.map((error) => error.toString()),
      contains(contains('recovery attempt 2 failed')),
    );

    bridge.emit({
      'type': 'video',
      'timestampMs': 200,
      'bytes': Uint8List.fromList([2]),
    });
    bridge.emit({
      'type': 'audio',
      'audioSequence': 8,
      'timestampMs': 200,
      'capturedAtMonoUs': 1020000,
      'sampleRate': 16000,
      'channels': 1,
      'bytes': Uint8List(640),
    });

    expect(videoFrames, hasLength(2));
    expect(audioChunks, hasLength(2));
    expect(audioDiscontinuities, [true, true]);

    await source.stop();
    await bridge.close();
  });

  test('hanging reconnect cannot block stop and successor demand', () async {
    final bridge = _FakeBridge()..hangAttachCall(2);
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      nativeOperationTimeout: const Duration(milliseconds: 30),
      reconnectBackoff: const [Duration.zero],
    );

    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    await bridge.closeCurrentEventStream();
    await _waitUntil(() => bridge.attachCalls == 2);

    final stopping = source.stop();
    final successor = source.reconcile(
      video: false,
      audio: true,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    await Future.wait([stopping, successor])
        .timeout(const Duration(milliseconds: 250));
    expect(source.audioActive, isTrue);

    bridge.releaseAttachCall(2);
    await _waitUntil(
      () =>
          bridge.nativeAttached &&
          !bridge.nativeVideoDemand &&
          bridge.nativeAudioDemand,
    );
    expect(source.audioActive, isTrue);
    await source.stop();
    await bridge.close();
  });

  test('late old clear-demand is repaired to successor exact demand', () async {
    final bridge = _FakeBridge()..hangDemandCall(2);
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      nativeOperationTimeout: const Duration(milliseconds: 30),
      reconnectBackoff: const [Duration(milliseconds: 10)],
    );

    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    await expectLater(source.stop(), throwsA(isA<TimeoutException>()));
    await source.reconcile(
      video: false,
      audio: true,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    expect(bridge.nativeAudioDemand, isTrue);

    bridge.releaseDemandCall(2);
    await _waitUntil(
      () =>
          bridge.nativeAttached &&
          !bridge.nativeVideoDemand &&
          bridge.nativeAudioDemand &&
          bridge.demandCalls >= 4,
    );

    expect(source.audioActive, isTrue);
    await source.stop();
    await bridge.close();
  });

  test('late old detach is repaired without detaching successor', () async {
    final bridge = _FakeBridge()..hangDetachCall(1);
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      nativeOperationTimeout: const Duration(milliseconds: 30),
      reconnectBackoff: const [Duration(milliseconds: 10)],
    );

    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    await expectLater(source.stop(), throwsA(isA<TimeoutException>()));
    await source.reconcile(
      video: false,
      audio: true,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );

    bridge.releaseDetachCall(1);
    await _waitUntil(
      () =>
          bridge.nativeAttached &&
          bridge.nativeAudioDemand &&
          bridge.attachCalls >= 3,
    );

    expect(source.audioActive, isTrue);
    await source.stop();
    await bridge.close();
  });

  test('late attach cleanup retries when compensating detach hangs', () async {
    final bridge = _FakeBridge()..hangFirstAttach = true;
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      nativeOperationTimeout: const Duration(milliseconds: 20),
      reconnectBackoff: const [Duration(milliseconds: 10)],
    );

    await expectLater(
      source.reconcile(
        video: true,
        audio: false,
        onVideoFrame: (_) {},
        onAudioChunk: (_) {},
      ),
      throwsA(isA<TimeoutException>()),
    );
    try {
      await source.stop();
    } catch (_) {}
    final compensatingDetach = bridge.detachCalls + 1;
    bridge.hangDetachCall(compensatingDetach);
    bridge.releaseFirstAttach();

    await _waitUntil(() => bridge.detachCalls > compensatingDetach);
    expect(bridge.nativeAttached, isFalse);
    await bridge.close();
  });

  test('immediate detach failure retains lease and retries cleanup', () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      nativeOperationTimeout: const Duration(milliseconds: 30),
      reconnectBackoff: const [Duration(milliseconds: 10)],
    );
    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    bridge.detachFailuresRemaining = 1;

    await expectLater(source.stop(), throwsA(isA<StateError>()));
    await _waitUntil(() => bridge.detachCalls >= 2);

    expect(bridge.nativeAttached, isFalse);
    expect(source.isActive, isFalse);
    await bridge.close();
  });

  test('stop cancels a pending event stream recovery retry', () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      reconnectBackoff: const [Duration(seconds: 10)],
    );
    final errors = <Object>[];

    await source.reconcile(
      video: true,
      audio: true,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
      onError: (error, _) => errors.add(error),
    );
    await bridge.closeCurrentEventStream();
    await source.stop();
    await pumpEventQueue();

    expect(bridge.attachCalls, 1);
    expect(bridge.readyDemands, hasLength(1));
    expect(bridge.detachCalls, 1);
    expect(
      bridge.consumerDemands.last,
      (video: false, audio: false, encodeVideo: false),
    );
    expect(
      errors.map((error) => error.toString()),
      contains(contains('event stream closed unexpectedly')),
    );

    await bridge.close();
  });

  test('new reconcile replaces a pending recovery generation', () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      reconnectBackoff: const [Duration(seconds: 10)],
    );
    final videoFrames = <Uint8List>[];
    final audioChunks = <Uint8List>[];

    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: videoFrames.add,
      onAudioChunk: audioChunks.add,
    );
    await bridge.closeCurrentEventStream();
    await source.reconcile(
      video: false,
      audio: true,
      onVideoFrame: videoFrames.add,
      onAudioChunk: audioChunks.add,
    );
    await pumpEventQueue();

    expect(bridge.attachCalls, 2);
    expect(bridge.readyDemands, [
      (video: true, audio: false),
      (video: false, audio: true),
    ]);
    expect(
      bridge.consumerDemands.last,
      (video: false, audio: true, encodeVideo: false),
    );
    bridge.emit({
      'type': 'video',
      'bytes': Uint8List.fromList([1]),
    });
    bridge.emit({
      'type': 'audio',
      'bytes': Uint8List.fromList([1, 0]),
    });
    expect(videoFrames, isEmpty);
    expect(audioChunks, hasLength(1));

    await source.stop();
    await bridge.close();
  });

  test('stop detaches the consumer without changing native hardware demand',
      () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(bridge: bridge);

    await source.reconcile(
      video: true,
      audio: true,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );
    await source.stop();

    expect(source.isActive, isFalse);
    expect(source.latestPreviewFrame, isNull);
    expect(
      bridge.consumerDemands.last,
      (video: false, audio: false, encodeVideo: false),
    );
    expect(bridge.detachCalls, 1);
    expect(bridge.hardwareDemandMutations, 0);
    await bridge.close();
  });

  test('constructor rejects transport settings outside native bounds', () {
    final bridge = _FakeBridge();
    expect(
      () => AndroidServiceMediaSource(bridge: bridge, maxVideoFps: 30),
      throwsArgumentError,
    );
    expect(
      () => AndroidServiceMediaSource(bridge: bridge, jpegQuality: 10),
      throwsArgumentError,
    );
  });

  test('capture state reflects failure, deduplicates it, and recovers',
      () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(bridge: bridge);
    final errors = <Object>[];

    await source.reconcile(
      video: false,
      audio: true,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
      onError: (error, _) => errors.add(error),
    );
    expect(source.audioActive, isTrue);

    bridge.emit({
      'type': 'error',
      'resource': 'microphone',
      'message': 'read failed',
    });
    bridge.emit({
      'type': 'captureState',
      'cameraActive': false,
      'microphoneActive': false,
      'microphoneError': 'read failed',
    });
    bridge.emit({
      'type': 'captureState',
      'cameraActive': false,
      'microphoneActive': false,
      'microphoneError': 'read failed',
    });

    expect(source.audioActive, isFalse);
    expect(errors, hasLength(1));
    expect(source.snapshot.lastError, contains('read failed'));

    bridge.emit({
      'type': 'captureState',
      'cameraActive': false,
      'microphoneActive': false,
    });
    bridge.emit({
      'type': 'captureState',
      'cameraActive': false,
      'microphoneActive': true,
    });

    expect(source.audioActive, isTrue);
    expect(source.snapshot.lastError, isNull);
    await source.stop();
    await bridge.close();
  });

  test('thermal media policy updates native encoder before later frames',
      () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(
      bridge: bridge,
      jpegQuality: 68,
      maxVideoFps: 8,
    );
    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: (_) {},
      onAudioChunk: (_) {},
    );

    await source.applyMediaPolicy(jpegQuality: 42, maxVideoFps: 2);

    expect(bridge.mediaPolicies.single, (jpegQuality: 42, maxVideoFps: 2));
    await source.stop();
    await bridge.close();
  });

  test('motion-only demand forwards luma without requiring a JPEG', () async {
    final bridge = _FakeBridge();
    final source = AndroidServiceMediaSource(bridge: bridge);
    final videoFrames = <Uint8List>[];
    final lumaFrames = <LumaFrame>[];
    final subscription = source.lumaFrames.listen(lumaFrames.add);

    await source.setVideoEncodingDemand(false);
    await source.reconcile(
      video: true,
      audio: false,
      onVideoFrame: videoFrames.add,
      onAudioChunk: (_) {},
    );
    bridge.emit({
      'type': 'video',
      'timestampMs': 303,
      'bytes': Uint8List(0),
      'lumaBytes': Uint8List.fromList([1, 2, 3, 4]),
      'lumaWidth': 2,
      'lumaHeight': 2,
    });

    expect(videoFrames, isEmpty);
    expect(lumaFrames, hasLength(1));
    expect(lumaFrames.single.yPlane, [1, 2, 3, 4]);
    expect(
      bridge.consumerDemands.single,
      (video: true, audio: false, encodeVideo: false),
    );

    await source.stop();
    await subscription.cancel();
    await bridge.close();
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

class _FakeBridge
    implements
        AndroidServiceMediaBridgePort,
        AndroidServiceMediaTorchBridgePort {
  final _eventControllers = <StreamController<Object?>>[];
  final _readyCallNotifications = StreamController<int>.broadcast(sync: true);
  StreamController<Object?>? _currentEvents;
  final consumerDemands = <({bool video, bool audio, bool encodeVideo})>[];
  final readyDemands = <({bool video, bool audio})>[];
  final mediaPolicies = <({int jpegQuality, int maxVideoFps})>[];
  final torchRequests = <bool>[];
  Completer<bool>? torchCompletion;

  @override
  Future<bool> setTorchEnabled(bool enabled) async {
    torchRequests.add(enabled);
    return torchCompletion?.future ?? Future<bool>.value(true);
  }

  int attachCalls = 0;
  int detachCalls = 0;
  int hardwareDemandMutations = 0;
  int readyFailuresRemaining = 0;
  int detachFailuresRemaining = 0;
  bool hangFirstAttach = false;
  final Completer<void> _firstAttachRelease = Completer<void>();
  final _attachReleases = <int, Completer<void>>{};
  final _demandReleases = <int, Completer<void>>{};
  final _detachReleases = <int, Completer<void>>{};
  bool nativeAttached = false;
  bool nativeVideoDemand = false;
  bool nativeAudioDemand = false;
  int demandCalls = 0;

  @override
  Stream<Object?> get events {
    final events = StreamController<Object?>.broadcast(sync: true);
    _eventControllers.add(events);
    _currentEvents = events;
    return events.stream;
  }

  void emit(Map<Object?, Object?> event) => _currentEvents!.add(event);

  Future<void> closeCurrentEventStream() async {
    final events = _currentEvents;
    if (events != null && !events.isClosed) await events.close();
  }

  Future<void> waitForReadyCalls(int count) async {
    if (readyDemands.length >= count) return;
    await _readyCallNotifications.stream.firstWhere(
      (currentCount) => currentCount >= count,
    );
  }

  Future<void> close() async {
    for (final events in _eventControllers) {
      if (!events.isClosed) await events.close();
    }
    await _readyCallNotifications.close();
  }

  @override
  Future<Map<Object?, Object?>> attach({
    required int jpegQuality,
    required int maxVideoFps,
  }) async {
    attachCalls++;
    if (hangFirstAttach && attachCalls == 1) {
      await _firstAttachRelease.future;
    }
    final release = _attachReleases[attachCalls];
    if (release != null) await release.future;
    nativeAttached = true;
    return {
      'consumerAttached': true,
      'jpegQuality': jpegQuality,
      'maxVideoFps': maxVideoFps,
    };
  }

  void releaseFirstAttach() {
    if (!_firstAttachRelease.isCompleted) _firstAttachRelease.complete();
  }

  void hangAttachCall(int call) {
    _attachReleases[call] = Completer<void>();
  }

  void releaseAttachCall(int call) {
    final release = _attachReleases[call];
    if (release != null && !release.isCompleted) release.complete();
  }

  void hangDemandCall(int call) {
    _demandReleases[call] = Completer<void>();
  }

  void releaseDemandCall(int call) {
    final release = _demandReleases[call];
    if (release != null && !release.isCompleted) release.complete();
  }

  void hangDetachCall(int call) {
    _detachReleases[call] = Completer<void>();
  }

  void releaseDetachCall(int call) {
    final release = _detachReleases[call];
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<Map<Object?, Object?>> awaitReady({
    required bool video,
    required bool audio,
    required Duration timeout,
  }) async {
    readyDemands.add((video: video, audio: audio));
    _readyCallNotifications.add(readyDemands.length);
    if (readyFailuresRemaining > 0) {
      readyFailuresRemaining--;
      throw StateError('native camera failed');
    }
    return {'cameraActive': video, 'microphoneActive': audio};
  }

  @override
  Future<Map<Object?, Object?>> detach() async {
    detachCalls++;
    final release = _detachReleases[detachCalls];
    if (release != null) await release.future;
    if (detachFailuresRemaining > 0) {
      detachFailuresRemaining--;
      throw StateError('native detach failed');
    }
    nativeAttached = false;
    nativeVideoDemand = false;
    nativeAudioDemand = false;
    return {'consumerAttached': false};
  }

  @override
  Future<Map<Object?, Object?>> resetDiagnostics() async => const {};

  @override
  Future<Map<Object?, Object?>> setConsumerDemand({
    required bool video,
    required bool audio,
    bool encodeVideo = true,
  }) async {
    demandCalls++;
    consumerDemands.add((
      video: video,
      audio: audio,
      encodeVideo: encodeVideo,
    ));
    final release = _demandReleases[demandCalls];
    if (release != null) await release.future;
    nativeVideoDemand = video;
    nativeAudioDemand = audio;
    return {
      'consumerVideo': video,
      'consumerAudio': audio,
      'consumerVideoEncoding': encodeVideo,
    };
  }

  @override
  Future<Map<Object?, Object?>> setMediaPolicy({
    required int jpegQuality,
    required int maxVideoFps,
  }) async {
    mediaPolicies.add((
      jpegQuality: jpegQuality,
      maxVideoFps: maxVideoFps,
    ));
    return {
      'jpegQuality': jpegQuality,
      'maxVideoFps': maxVideoFps,
    };
  }

  @override
  Future<Map<Object?, Object?>> snapshot() async => const {
        'cameraActive': true,
        'microphoneActive': true,
      };
}
