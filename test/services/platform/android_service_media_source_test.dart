import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/analysis/video/luma_frame.dart';
import 'package:miucam/services/platform/android_service_media_source.dart';

void main() {
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

class _FakeBridge implements AndroidServiceMediaBridgePort {
  final _events = StreamController<Object?>.broadcast(sync: true);
  final consumerDemands = <({bool video, bool audio, bool encodeVideo})>[];
  final readyDemands = <({bool video, bool audio})>[];
  final mediaPolicies = <({int jpegQuality, int maxVideoFps})>[];
  int attachCalls = 0;
  int detachCalls = 0;
  int hardwareDemandMutations = 0;
  int readyFailuresRemaining = 0;

  @override
  Stream<Object?> get events => _events.stream;

  void emit(Map<Object?, Object?> event) => _events.add(event);

  Future<void> close() => _events.close();

  @override
  Future<Map<Object?, Object?>> attach({
    required int jpegQuality,
    required int maxVideoFps,
  }) async {
    attachCalls++;
    return {
      'consumerAttached': true,
      'jpegQuality': jpegQuality,
      'maxVideoFps': maxVideoFps,
    };
  }

  @override
  Future<Map<Object?, Object?>> awaitReady({
    required bool video,
    required bool audio,
    required Duration timeout,
  }) async {
    readyDemands.add((video: video, audio: audio));
    if (readyFailuresRemaining > 0) {
      readyFailuresRemaining--;
      throw StateError('native camera failed');
    }
    return {'cameraActive': video, 'microphoneActive': audio};
  }

  @override
  Future<Map<Object?, Object?>> detach() async {
    detachCalls++;
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
    consumerDemands.add((
      video: video,
      audio: audio,
      encodeVideo: encodeVideo,
    ));
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
