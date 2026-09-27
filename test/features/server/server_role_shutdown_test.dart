import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/media/microphone_capture_service.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:record/record.dart';

void main() {
  test('all dispose callers wait for pairing acquisition and final teardown',
      () async {
    final pairingEntered = Completer<void>();
    final pairingRelease = Completer<void>();
    final calls = <String>[];
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async {
        pairingEntered.complete();
        await pairingRelease.future;
        calls.add('host acquired');
        return 'miucam://pair';
      },
      onStop: () async => calls.add('host released'),
    );

    final pairing = runtime.startPairingMode();
    await pairingEntered.future;
    final first = runtime.dispose();
    final second = runtime.dispose();
    expect(identical(first, second), isTrue);
    var finished = false;
    unawaited(second.then((_) => finished = true));
    await pumpEventQueue();
    expect(finished, isFalse);
    expect(calls, isEmpty);

    pairingRelease.complete();
    await Future.wait([pairing, first, second]);
    expect(calls, ['host acquired', 'host released']);
    expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
  });

  test('billing failure cannot skip camera microphone or native lease release',
      () async {
    final billing = _FailingBilling();
    final calls = <String>[];
    final demands = <MediaResourceDemand>[];
    final media = MediaRuntimeController(
      onStartVideo: () async => calls.add('camera started'),
      onStopVideo: () async => calls.add('camera stopped'),
    );
    final runtime = ServerRuntime(
      mediaRuntime: media,
      broadcastAccess: billing,
      ownsBroadcastAccess: false,
      onMediaDemandChanged: (demand) async => demands.add(demand),
    );
    await runtime.startLocalPreview();

    await expectLater(runtime.dispose(), throwsStateError);

    expect(calls, ['camera started', 'camera stopped']);
    expect(media.isActive, isFalse);
    expect(demands.last, MediaResourceDemand.none);
    billing.fail = false;
    await runtime.dispose();
    expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
  });

  test('terminal media shutdown waits for a timed out native acquisition',
      () async {
    final acquisition = Completer<void>();
    var stops = 0;
    final media = MediaRuntimeController(
      onStart: () => acquisition.future,
      onStop: () async => stops++,
      operationTimeout: const Duration(milliseconds: 100),
    );
    await expectLater(media.start(), throwsA(isA<TimeoutException>()));
    final shutdown = media.dispose();
    var finished = false;
    unawaited(shutdown.then((_) => finished = true));
    await pumpEventQueue();
    expect(finished, isFalse);

    acquisition.complete();
    await shutdown;
    expect(stops, 1);
    expect(media.isActive, isFalse);
    await expectLater(media.start(), throwsStateError);
  });

  test('failed camera release still stops audio and terminal retry is safe',
      () async {
    var cameraFails = true;
    var audioStops = 0;
    var cameraStops = 0;
    final media = MediaRuntimeController(
      onStartVideo: () async {},
      onStartAudio: () async {},
      onStopVideo: () async {
        cameraStops++;
        if (cameraFails) throw StateError('camera still owned');
      },
      onStopAudio: () async => audioStops++,
    );
    await media.start();
    await expectLater(media.dispose(), throwsStateError);
    expect(audioStops, 1);
    expect(media.audioActive, isFalse);
    await expectLater(media.resume(), throwsStateError);

    cameraFails = false;
    await media.dispose();
    expect(cameraStops, 2);
    expect(audioStops, 1);
    expect(media.isActive, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(cameraStops, 2);
  });

  test('unconfirmed microphone disposal fails and retains recorder for retry',
      () async {
    final recorder = _Recorder()..failDispose = true;
    final capture = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
    );
    await capture.start(onChunk: (_) {});
    await expectLater(capture.dispose(), throwsStateError);
    await expectLater(capture.start(onChunk: (_) {}), throwsStateError);

    recorder.failDispose = false;
    await capture.dispose();
    expect(recorder.disposeCalls, 2);
    expect(capture.isActive, isFalse);
  });

  test('concurrent microphone disposal waits for late recorder start',
      () async {
    final recorder = _Recorder()..pendingStart = Completer<void>();
    final capture = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
    );
    final start = capture.start(onChunk: (_) {});
    await recorder.startEntered.future;
    final first = capture.dispose();
    final second = capture.dispose();
    expect(identical(first, second), isTrue);
    var finished = false;
    unawaited(second.then((_) => finished = true));
    await pumpEventQueue();
    expect(finished, isFalse);
    recorder.pendingStart!.complete();
    expect(await start, isFalse);
    await first;
    expect(recorder.disposeCalls, 1);
  });
}

class _FailingBilling extends Fake implements BroadcastAccessService {
  bool fail = true;

  @override
  Future<BroadcastAccessSnapshot> endAllSessions() async {
    if (fail) throw StateError('trial storage unavailable');
    return const BroadcastAccessSnapshot(
      unlocked: true,
      active: false,
      freeLimitMs: 1000,
      usedMs: 0,
      remainingMs: 1000,
      priceLabel: '',
      productId: 'test',
    );
  }
}

class _Recorder implements MicrophoneRecorderPort {
  final _stream = StreamController<Uint8List>.broadcast();
  final startEntered = Completer<void>();
  Completer<void>? pendingStart;
  bool failDispose = false;
  int disposeCalls = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    startEntered.complete();
    await pendingStart?.future;
    return _stream.stream;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (failDispose) throw StateError('recorder still owned');
    await _stream.close();
  }
}
