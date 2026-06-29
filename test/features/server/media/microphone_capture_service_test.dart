import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/media/microphone_capture_service.dart';
import 'package:record/record.dart';

void main() {
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
    expect(service.snapshot.lastChunkAtMs, nowMs);
    expect(service.snapshot.lastChunkBytes, raw.length);

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
  });
}

class _FakeRecorder implements MicrophoneRecorderPort {
  _FakeRecorder({this.hasPermissionValue = true});

  final bool hasPermissionValue;
  final _controller = StreamController<Uint8List>();
  int startCalls = 0;
  bool stopped = false;
  bool disposed = false;
  RecordConfig? lastConfig;

  @override
  Future<bool> hasPermission() async => hasPermissionValue;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    startCalls++;
    lastConfig = config;
    return _controller.stream;
  }

  void add(Uint8List bytes) {
    _controller.add(bytes);
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
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
