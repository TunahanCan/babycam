import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/media/microphone_capture_service.dart';
import 'package:miucam/services/server/audio_stream_leveler.dart';
import 'package:record/record.dart';

void main() {
  test('stop during automatic restart cannot revive microphone capture',
      () async {
    final recorder = _FakeRecorder();
    final replacement = _FakeRecorder();
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
      recorderFactory: () => replacement,
      restartBaseDelay: const Duration(milliseconds: 1),
      restartMaxDelay: const Duration(milliseconds: 2),
      cleanupTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    final lateStream = Completer<Stream<Uint8List>>();
    addTearDown(() {
      if (!lateStream.isCompleted) lateStream.complete(const Stream.empty());
    });
    expect(await service.start(onChunk: (_) {}), isTrue);
    recorder.nextStreamResult = lateStream.future;
    recorder.addError(StateError('lost microphone capture'));
    await _waitUntil(() => recorder.startCalls == 2);
    await service.stop();
    lateStream.complete(const Stream.empty());
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(replacement.startCalls, 0);
    expect(service.isActive, isFalse);
  });

  test('parcali PCM orneklerini gain ve analizden once kayipsiz birlestirir',
      () async {
    final recorder = _FakeRecorder();
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
      streamLeveler: AudioStreamLeveler(maxGain: 1),
    );
    addTearDown(service.dispose);
    final chunks = <MicrophonePcmChunk>[];
    await service.start(onChunk: chunks.add);
    final raw = _pcm16le([258, -515, 772, -1029]);
    recorder.add(Uint8List.sublistView(raw, 0, 3));
    recorder.add(Uint8List.sublistView(raw, 3, 4));
    recorder.add(Uint8List.sublistView(raw, 4, 7));
    recorder.add(Uint8List.sublistView(raw, 7));
    await pumpEventQueue();

    expect(chunks.every((chunk) => chunk.rawPcm16le.length.isEven), isTrue);
    expect(chunks.expand((chunk) => chunk.rawPcm16le), raw);
    expect(chunks.expand((chunk) => chunk.streamPcm16le), raw);
  });

  test('yeni capture eski kismi ornegi ve gain durumunu devralmaz', () async {
    final recorder = _FakeRecorder();
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
    );
    addTearDown(service.dispose);
    final chunks = <MicrophonePcmChunk>[];
    final raw = _pcm16le(List<int>.filled(320, 20));
    await service.start(onChunk: chunks.add);
    recorder.add(raw);
    await pumpEventQueue();
    final firstOutput = chunks.single.streamPcm16le;
    recorder.add(Uint8List.fromList([123]));
    await pumpEventQueue();
    await service.stop();
    chunks.clear();

    await service.start(onChunk: chunks.add);
    recorder.add(raw);
    await pumpEventQueue();

    expect(chunks.single.rawPcm16le, raw);
    expect(chunks.single.streamPcm16le, firstOutput);
  });

  test('dusuk RMS mikrofon sinyalini canli yayin icin yukseltir', () async {
    var nowMs = 1000;
    final recorder = _FakeRecorder();
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
      nowMs: () => nowMs,
    );
    final chunks = <MicrophonePcmChunk>[];

    expect(await service.start(onChunk: chunks.add), isTrue);
    final raw = _pcm16le(List<int>.filled(1600, 20));
    recorder.add(raw);
    await pumpEventQueue();

    expect(chunks, hasLength(1));
    expect(identical(chunks.single.rawPcm16le, raw), isTrue);
    expect(_rms(chunks.single.streamPcm16le), greaterThan(_rms(raw) * 8));
    expect(chunks.single.leveler.outputRms, greaterThan(150));
    expect(service.snapshot.active, isTrue);
    expect(service.snapshot.chunksCaptured, 1);
    expect(service.snapshot.bytesCaptured, raw.length);
    expect(service.snapshot.lastChunkAtMs, nowMs);
    expect(service.snapshot.lastChunkBytes, raw.length);
    expect(service.snapshot.failureReason, isNull);

    nowMs += 20;
    await service.stop();
    expect(service.snapshot.active, isFalse);
  });

  test('mikrofon izni yoksa stream baslatmaz', () async {
    final recorder = _FakeRecorder(hasPermissionValue: false);
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
    );

    expect(await service.start(onChunk: (_) => fail('chunk gelmemeli')), false);

    expect(recorder.startCalls, 0);
    expect(service.snapshot.recorderCreated, isTrue);
    expect(service.snapshot.permissionGranted, isFalse);
    expect(service.snapshot.active, isFalse);
    expect(service.snapshot.failureReason, 'permissionDenied');
    expect(service.snapshot.lastStartError, contains('permission denied'));
  });

  test('izin onceden cozulur ve start ikinci kez izin istemez', () async {
    final recorder = _FakeRecorder();
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
    );

    expect(await service.ensurePermission(), isTrue);
    expect(await service.start(onChunk: (_) {}), isTrue);

    expect(recorder.permissionCalls, 1);
    expect(recorder.startCalls, 1);
    await service.stop();
    expect(await service.ensurePermission(), isTrue);
    expect(
      recorder.permissionCalls,
      2,
      reason: 'yeni capture lease sistem iznini yeniden doğrulamalı',
    );
    await service.dispose();
  });

  test('bekleyen izin kontrolunu stop sinirli surede gecersiz kilar', () async {
    final permission = Completer<bool>();
    final recorder = _FakeRecorder(permissionResult: permission.future);
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
      cleanupTimeout: const Duration(milliseconds: 20),
    );

    final checking = service.ensurePermission();
    final stopwatch = Stopwatch()..start();
    await service.stop().timeout(const Duration(seconds: 1));
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 200)));
    permission.complete(true);
    expect(await checking, isFalse);
    expect(service.snapshot.permissionGranted, isNull);
    expect(recorder.startCalls, 0);
    await service.dispose();
  });

  test('es zamanli start talepleri tek recorder operasyonunda birlesir',
      () async {
    final permission = Completer<bool>();
    final recorder = _FakeRecorder(permissionResult: permission.future);
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
    );

    final first = service.start(onChunk: (_) {});
    final second = service.start(onChunk: (_) {});
    expect(recorder.permissionCalls, 1);
    permission.complete(true);

    expect(await Future.wait([first, second]), [true, true]);
    expect(recorder.startCalls, 1);
    expect(service.isActive, isTrue);
    await service.dispose();
  });

  test('pending start sirasinda stop gec gelen streami aktif birakmaz',
      () async {
    final streamResult = Completer<Stream<Uint8List>>();
    final recorder = _FakeRecorder(streamResult: streamResult.future);
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
    );

    final starting = service.start(onChunk: (_) {});
    await pumpEventQueue();
    final stopping = service.stop();
    streamResult.complete(recorder.stream);

    expect(await starting, isFalse);
    await stopping;
    expect(service.isActive, isFalse);
    expect(recorder.stopped, isTrue);
    await service.dispose();
  });

  test('takilan start ve recorder stop temizligi sure sinirlidir', () async {
    final streamResult = Completer<Stream<Uint8List>>();
    final recorderStop = Completer<void>();
    final recorder = _FakeRecorder(
      streamResult: streamResult.future,
      stopResult: recorderStop.future,
    );
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
      cleanupTimeout: const Duration(milliseconds: 20),
    );

    final starting = service.start(onChunk: (_) {});
    await pumpEventQueue();
    final stopwatch = Stopwatch()..start();
    await service.stop().timeout(const Duration(seconds: 1));
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 200)));
    expect(service.isActive, isFalse);

    streamResult.complete(recorder.stream);
    expect(await starting, isFalse);
    recorderStop.complete();
    await service.dispose();
  });

  test('basarisiz recorder teardown sonraki capture icin yenisini olusturur',
      () async {
    final hangingStop = Completer<void>();
    final first = _FakeRecorder(stopResult: hangingStop.future);
    final second = _FakeRecorder();
    final recorders = [first, second];
    var factoryCalls = 0;
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorderFactory: () => recorders[factoryCalls++],
      cleanupTimeout: const Duration(milliseconds: 20),
    );

    expect(await service.start(onChunk: (_) {}), isTrue);
    await service.stop().timeout(const Duration(seconds: 1));

    expect(first.disposed, isTrue);
    expect(await service.start(onChunk: (_) {}), isTrue);
    expect(factoryCalls, 2);
    expect(second.startCalls, 1);
    await service.dispose();
  });

  test('gec tamamlanan eski start yeni recorder captureini durduramaz',
      () async {
    final firstStream = Completer<Stream<Uint8List>>();
    final first = _FakeRecorder(streamResult: firstStream.future);
    final second = _FakeRecorder();
    final recorders = [first, second];
    var factoryCalls = 0;
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorderFactory: () => recorders[factoryCalls++],
      cleanupTimeout: const Duration(milliseconds: 20),
    );

    final firstStart = service.start(onChunk: (_) {});
    await pumpEventQueue();
    await service.stop().timeout(const Duration(seconds: 1));

    expect(first.disposed, isTrue);
    expect(await service.start(onChunk: (_) {}), isTrue);
    expect(factoryCalls, 2);
    expect(second.startCalls, 1);
    expect(second.stopCalls, 0);

    firstStream.complete(first.stream);
    expect(await firstStart, isFalse);
    await pumpEventQueue();

    expect(second.stopCalls, 0);
    expect(service.isActive, isTrue);
    await service.dispose();
  });

  test('hic tamamlanmayan eski start sonraki capturei bloke etmez', () async {
    final neverCompletes = Completer<Stream<Uint8List>>();
    final first = _FakeRecorder(streamResult: neverCompletes.future);
    final second = _FakeRecorder();
    final recorders = [first, second];
    var factoryCalls = 0;
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorderFactory: () => recorders[factoryCalls++],
      cleanupTimeout: const Duration(milliseconds: 20),
    );

    unawaited(service.start(onChunk: (_) {}));
    await pumpEventQueue();
    await service.stop().timeout(const Duration(seconds: 1));

    expect(first.disposed, isTrue);
    expect(await service.start(onChunk: (_) {}), isTrue);
    expect(factoryCalls, 2);
    expect(second.startCalls, 1);
    expect(service.isActive, isTrue);
    await service.dispose();
  });

  test('capture stream hatasindan sonra mikrofonu yeniden baslatir', () async {
    final recorder = _FakeRecorder();
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
      restartBaseDelay: const Duration(milliseconds: 1),
      restartMaxDelay: const Duration(milliseconds: 2),
    );
    final errors = <Object>[];

    expect(
      await service.start(
        onChunk: (_) {},
        onError: (error, _) => errors.add(error),
      ),
      isTrue,
    );
    recorder.addError(StateError('recorder disconnected'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(errors, hasLength(1));
    expect(recorder.startCalls, greaterThanOrEqualTo(2));
    expect(service.isActive, isTrue);
    await service.dispose();
  });

  test('takilan terminal cancel mikrofon yeniden baslatmayi engellemez',
      () async {
    final cancelRelease = Completer<void>();
    final recorder = _FakeRecorder(
      onCancel: () => cancelRelease.future,
    );
    final service = MicrophoneCaptureService(
      sampleRate: 16000,
      channels: 1,
      recorder: recorder,
      restartBaseDelay: const Duration(milliseconds: 1),
      restartMaxDelay: const Duration(milliseconds: 2),
      cleanupTimeout: const Duration(milliseconds: 20),
    );

    expect(await service.start(onChunk: (_) {}), isTrue);
    recorder.addError(StateError('terminal stream failure'));
    await _waitUntil(() => recorder.startCalls >= 2);

    expect(service.isActive, isTrue);
    cancelRelease.complete();
    await service.dispose();
  });
}

class _FakeRecorder implements MicrophoneRecorderPort {
  _FakeRecorder({
    this.hasPermissionValue = true,
    this.permissionResult,
    this.streamResult,
    this.stopResult,
    FutureOr<void> Function()? onCancel,
  }) : _controller = StreamController<Uint8List>.broadcast(
          onCancel: onCancel,
        );

  final bool hasPermissionValue;
  final Future<bool>? permissionResult;
  final Future<Stream<Uint8List>>? streamResult;
  final Future<void>? stopResult;
  Future<Stream<Uint8List>>? nextStreamResult;
  final StreamController<Uint8List> _controller;
  int permissionCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  bool stopped = false;
  bool disposed = false;
  RecordConfig? lastConfig;

  @override
  Future<bool> hasPermission() {
    permissionCalls++;
    return permissionResult ?? Future<bool>.value(hasPermissionValue);
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    startCalls++;
    lastConfig = config;
    final pending = nextStreamResult;
    nextStreamResult = null;
    return pending ??
        streamResult ??
        Future<Stream<Uint8List>>.value(_controller.stream);
  }

  Stream<Uint8List> get stream => _controller.stream;

  void add(Uint8List bytes) {
    _controller.add(bytes);
  }

  void addError(Object error) {
    _controller.addError(error, StackTrace.current);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    stopped = true;
    await stopResult;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
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

Uint8List _pcm16le(List<int> samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

double _rms(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final sampleCount = bytes.length ~/ 2;
  var sumSquares = 0;
  for (var i = 0; i < sampleCount; i++) {
    final sample = view.getInt16(i * 2, Endian.little);
    sumSquares += sample * sample;
  }
  return sqrt(sumSquares / sampleCount);
}
