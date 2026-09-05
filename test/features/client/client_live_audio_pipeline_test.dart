import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/client/media/client_live_audio_pipeline.dart';
import 'package:miucam/features/client/media/pcm_audio_output.dart';

void main() {
  for (final hangs in [false, true]) {
    test(
        'periodic native write ${hangs ? 'timeout' : 'error'} reconnects audio',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.headers
          ..contentType = ContentType('audio', 'wav')
          ..chunkedTransferEncoding = true;
        request.response
          ..add(_wavHeader(pcmBytes: 0))
          ..add(_pcmFrames(12));
        await request.response.flush();
        // Keep the network healthy/open; only the native output fails.
      });
      final sink = _FailingPcmAudioSink(hangs: hangs);
      final errors = <Object>[];
      final pipeline = ClientLiveAudioPipeline(
        audioOutput: sink,
        connectTimeout: const Duration(milliseconds: 100),
        retryDelay: const Duration(milliseconds: 1),
      );
      addTearDown(pipeline.stop);
      await pipeline.start(
        uri: Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          path: '/audio',
        ),
        pairedServerHost: InternetAddress.loopbackIPv4.address,
        pairedServerPort: server.port,
        onError: errors.add,
      );

      await _waitUntil(() => sink.starts.length >= 2 && sink.writes.length > 8);

      expect(errors, hasLength(1));
      expect(
          errors.single, hangs ? isA<TimeoutException>() : isA<StateError>());
      expect(sink.stops, greaterThanOrEqualTo(1));
    });
  }

  test('Bearer token ile WAV streami acar ve PCM native sinke yazar', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final authHeaders = <String>[];
    final pcm = _pcmFrames(5);
    server.listen((request) async {
      authHeaders
          .add(request.headers.value(HttpHeaders.authorizationHeader) ?? '');
      request.response.headers
        ..contentType = ContentType('audio', 'wav')
        ..chunkedTransferEncoding = true;
      request.response.add(_wavHeader(pcmBytes: pcm.length));
      await request.response.flush();
      for (var index = 0; index < 5; index++) {
        request.response.add(
          Uint8List.sublistView(pcm, index * 640, (index + 1) * 640),
        );
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await request.response.close();
    });
    final sink = _FakePcmAudioSink();
    final pipeline = ClientLiveAudioPipeline(
      audioOutput: sink,
      retryDelay: const Duration(milliseconds: 20),
    );
    addTearDown(pipeline.stop);
    final wrote = Completer<void>();
    final status = Completer<ClientLiveAudioStatus>();

    await pipeline.start(
      uri: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/audio',
      ),
      pairedServerHost: InternetAddress.loopbackIPv4.address,
      pairedServerPort: server.port,
      bearerToken: 'trusted-token',
      onAudioChunkWritten: () {
        if (sink.writes.length >= 4 && !wrote.isCompleted) wrote.complete();
      },
      onStatus: (update) {
        if (update.event == 'write' && !status.isCompleted) {
          status.complete(update);
        }
      },
    );

    await wrote.future.timeout(const Duration(seconds: 2));
    final update = await status.future.timeout(const Duration(seconds: 2));
    expect(authHeaders.first, 'Bearer trusted-token');
    expect(sink.starts, [(sampleRate: 16000, channels: 1)]);
    expect(sink.writes.length, greaterThanOrEqualTo(4));
    expect(sink.writes.first, pcm.sublist(0, 640));
    expect(update.wavHeaderParsed, isTrue);
    expect(update.networkBytesReceived, greaterThan(44));
    expect(update.pcmChunksParsed, greaterThan(0));
    expect(update.pcmBytesParsed, greaterThanOrEqualTo(640 * 4));
    expect(update.nativeBytesWritten, 640);
    expect(update.toJson()['nativeBytesWritten'], 640);
  });

  test('native write reddedilirse status droppedNativeWrites sayar', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers
        ..contentType = ContentType('audio', 'wav')
        ..chunkedTransferEncoding = true;
      final pcm = _pcmFrames(4);
      request.response.add(_wavHeader(pcmBytes: pcm.length));
      await request.response.flush();
      for (var index = 0; index < 4; index++) {
        request.response.add(
          Uint8List.sublistView(pcm, index * 640, (index + 1) * 640),
        );
        await request.response.flush();
      }
      await request.response.close();
    });
    final sink = _FakePcmAudioSink(acceptWrites: false);
    final pipeline = ClientLiveAudioPipeline(
      audioOutput: sink,
      retryDelay: const Duration(milliseconds: 20),
    );
    addTearDown(pipeline.stop);
    final status = Completer<ClientLiveAudioStatus>();

    await pipeline.start(
      uri: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/audio',
      ),
      pairedServerHost: InternetAddress.loopbackIPv4.address,
      pairedServerPort: server.port,
      onStatus: (update) {
        if (update.event == 'write' && !status.isCompleted) {
          status.complete(update);
        }
      },
    );

    final update = await status.future.timeout(const Duration(seconds: 2));
    expect(update.droppedNativeWrites, 1);
    expect(update.chunksWritten, 1);
  });

  test('WAV stream veri kesilirse read timeout hata sinyali uretir', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    server.listen((request) async {
      request.response.headers
        ..contentType = ContentType('audio', 'wav')
        ..chunkedTransferEncoding = true;
      request.response.add(_wavHeader(pcmBytes: 0));
      await request.response.flush();
      await release.future;
    });
    final sink = _FakePcmAudioSink();
    final pipeline = ClientLiveAudioPipeline(
      audioOutput: sink,
      readTimeout: const Duration(milliseconds: 40),
      retryDelay: const Duration(seconds: 30),
    );
    addTearDown(pipeline.stop);
    final error = Completer<Object>();

    await pipeline.start(
      uri: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/audio',
      ),
      pairedServerHost: InternetAddress.loopbackIPv4.address,
      pairedServerPort: server.port,
      onError: (caught) {
        if (!error.isCompleted) error.complete(caught);
      },
    );

    await expectLater(
      error.future.timeout(const Duration(seconds: 2)),
      completion(isA<TimeoutException>()),
    );
  });

  test('jitter buffer limit asildiginda eski chunklari dusurur', () {
    final buffer = ClientAudioJitterBuffer(bytesPerFrame: 2, maxBytes: 8);

    buffer
      ..add(Uint8List.fromList([1, 0, 2, 0]))
      ..add(Uint8List.fromList([3, 0, 4, 0]))
      ..add(Uint8List.fromList([5, 0, 6, 0]));

    expect(buffer.bufferedBytes, 8);
    expect(buffer.droppedBytes, 4);
    expect(buffer.takeNext(maxBytes: 8), [3, 0, 4, 0]);
    expect(buffer.takeNext(maxBytes: 8), [5, 0, 6, 0]);
  });

  test('jitter buffer tek buyuk burst geldiginde en yeni sesi korur', () {
    final buffer = ClientAudioJitterBuffer(bytesPerFrame: 2, maxBytes: 8);

    buffer.add(Uint8List.fromList([
      1, 0, //
      2, 0,
      3, 0,
      4, 0,
      5, 0,
      6, 0,
    ]));

    expect(buffer.bufferedBytes, 8);
    expect(buffer.droppedBytes, 4);
    expect(buffer.takeNext(maxBytes: 8), [3, 0, 4, 0, 5, 0, 6, 0]);
  });

  test('jitter buffer parcalari sabit playout frameinde birlestirir', () {
    final buffer = ClientAudioJitterBuffer(bytesPerFrame: 2, maxBytes: 16)
      ..add(Uint8List.fromList([1, 0, 2, 0]))
      ..add(Uint8List.fromList([3, 0, 4, 0]));

    expect(buffer.takeFrame(8), [1, 0, 2, 0, 3, 0, 4, 0]);
    expect(buffer.bufferedBytes, 0);
  });

  test('network chunk sinirlari 20 ms PCM frame siniri sayilmaz', () {
    final assembler = PcmAudioFrameAssembler(frameBytes: 8);

    expect(assembler.add(Uint8List.fromList([1, 2, 3])), isEmpty);
    final frames = assembler.add(Uint8List.fromList([4, 5, 6, 7, 8, 9]));

    expect(frames, [
      [1, 2, 3, 4, 5, 6, 7, 8],
    ]);
    expect(assembler.takeRemainder(), [9]);
  });

  test('RFC jitter EWMA delay spikeinda hedef playoutu buyutur', () {
    final estimator = AdaptiveAudioJitterEstimator(
      minDelay: const Duration(milliseconds: 60),
      maxDelay: const Duration(milliseconds: 220),
    );

    estimator.observe(arrivalMs: 1000, mediaDurationMs: 20);
    estimator.observe(arrivalMs: 1020, mediaDurationMs: 20);
    expect(estimator.targetDelayMs, 60);

    estimator.observe(arrivalMs: 1140, mediaDurationMs: 20);
    expect(estimator.jitterMs, closeTo(6.25, 0.01));
    expect(estimator.targetDelayMs, 100);
  });

  test('TCP coalescing birden cok frame icin sahte jitter uretmez', () {
    final estimator = AdaptiveAudioJitterEstimator(
      minDelay: const Duration(milliseconds: 60),
      maxDelay: const Duration(milliseconds: 220),
    );

    estimator.observe(arrivalMs: 1000, mediaDurationMs: 60);
    estimator.observe(arrivalMs: 1060, mediaDurationMs: 60);

    expect(estimator.jitterMs, 0);
    expect(estimator.targetDelayMs, 60);
  });

  test('canli stream EOF partial PCM kalintisini native sinke yazmaz',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response
        ..add(_wavHeader(pcmBytes: 8))
        ..add(Uint8List.fromList([1, 0, 2, 0, 3, 0, 4, 0]));
      await request.response.close();
    });
    final sink = _FakePcmAudioSink();
    final pipeline = ClientLiveAudioPipeline(audioOutput: sink);
    addTearDown(pipeline.stop);
    final ended = Completer<void>();

    await pipeline.start(
      uri: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/audio',
      ),
      pairedServerHost: InternetAddress.loopbackIPv4.address,
      pairedServerPort: server.port,
      shouldRetry: (_) => false,
      onError: (_) {
        if (!ended.isCompleted) ended.complete();
      },
    );

    await ended.future.timeout(const Duration(seconds: 2));
    expect(sink.writes, isEmpty);
  });

  test('stop geciken native start tamamlandiktan sonra outputu kapatir',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers
        ..contentType = ContentType('audio', 'wav')
        ..chunkedTransferEncoding = true;
      final pcm = _pcmFrames(4);
      request.response.add(_wavHeader(pcmBytes: pcm.length));
      await request.response.flush();
      for (var index = 0; index < 4; index++) {
        request.response.add(
          Uint8List.sublistView(pcm, index * 640, (index + 1) * 640),
        );
        await request.response.flush();
      }
      await request.response.close();
    });
    final sink = _DelayedStartPcmAudioSink();
    final pipeline = ClientLiveAudioPipeline(audioOutput: sink);
    addTearDown(pipeline.stop);

    await pipeline.start(
      uri: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/audio',
      ),
      pairedServerHost: InternetAddress.loopbackIPv4.address,
      pairedServerPort: server.port,
    );
    await sink.startEntered.future.timeout(const Duration(seconds: 2));
    final stopFuture = pipeline.stop();
    sink.releaseStart.complete();
    await stopFuture.timeout(const Duration(seconds: 2));

    expect(pipeline.isRunning, isFalse);
    expect(sink.writes, isEmpty);
    expect(sink.stops, greaterThanOrEqualTo(2));
  });

  test('cancelImmediately takilan native start kuyrugunu beklemez', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers
        ..contentType = ContentType('audio', 'wav')
        ..chunkedTransferEncoding = true;
      final pcm = _pcmFrames(4);
      request.response.add(_wavHeader(pcmBytes: pcm.length));
      await request.response.flush();
      for (var index = 0; index < 4; index++) {
        request.response.add(
          Uint8List.sublistView(pcm, index * 640, (index + 1) * 640),
        );
        await request.response.flush();
      }
      await request.response.close();
    });
    final sink = _DelayedStartPcmAudioSink();
    final pipeline = ClientLiveAudioPipeline(audioOutput: sink);
    addTearDown(() {
      if (!sink.releaseStart.isCompleted) sink.releaseStart.complete();
      return pipeline.stop();
    });

    await pipeline.start(
      uri: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/audio',
      ),
      pairedServerHost: InternetAddress.loopbackIPv4.address,
      pairedServerPort: server.port,
    );
    await sink.startEntered.future.timeout(const Duration(seconds: 2));

    pipeline.cancelImmediately();

    expect(pipeline.isRunning, isFalse);
    await pumpEventQueue();
    expect(sink.stops, greaterThanOrEqualTo(1));

    sink.releaseStart.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sink.stops, greaterThanOrEqualTo(2));
  });

  test('geciken eski native start yeni audio leaseini durduramaz', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var streamRequests = 0;
    server.listen((request) async {
      final requestIndex = ++streamRequests;
      request.response.headers
        ..contentType = ContentType('audio', 'wav')
        ..chunkedTransferEncoding = true;
      final pcm = _pcmFrames(4);
      request.response.add(_wavHeader(pcmBytes: pcm.length));
      await request.response.flush();
      if (requestIndex == 1) {
        request.response.add(pcm);
        await request.response.close();
        return;
      }
      for (var index = 0; index < 100; index++) {
        request.response.add(
          Uint8List.sublistView(
            pcm,
            (index % 4) * 640,
            ((index % 4) + 1) * 640,
          ),
        );
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await request.response.close();
    });
    final sink = _DelayedStartPcmAudioSink();
    final first = ClientLiveAudioPipeline(
      audioOutput: sink,
      connectTimeout: const Duration(milliseconds: 50),
      retryDelay: const Duration(seconds: 30),
    );
    final second = ClientLiveAudioPipeline(
      audioOutput: sink,
      connectTimeout: const Duration(milliseconds: 500),
      retryDelay: const Duration(seconds: 30),
    );
    addTearDown(() async {
      if (!sink.releaseStart.isCompleted) sink.releaseStart.complete();
      await first.stop();
      await second.stop();
    });
    final firstError = Completer<Object>();

    await first.start(
      uri: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/audio',
      ),
      pairedServerHost: InternetAddress.loopbackIPv4.address,
      pairedServerPort: server.port,
      shouldRetry: (_) => false,
      onError: (error) {
        if (!firstError.isCompleted) firstError.complete(error);
      },
    );
    await sink.startEntered.future.timeout(const Duration(seconds: 2));
    expect(
      await firstError.future.timeout(const Duration(seconds: 2)),
      isA<TimeoutException>(),
    );

    await second.start(
      uri: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        path: '/audio',
      ),
      pairedServerHost: InternetAddress.loopbackIPv4.address,
      pairedServerPort: server.port,
      shouldRetry: (_) => false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sink.starts, hasLength(1));

    sink.releaseStart.complete();
    await _waitUntil(() => sink.starts.length == 2);
    final stopsAfterSecondStart = sink.stops;
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(sink.stops, stopsAfterSecondStart);
    expect(second.isRunning, isTrue);
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Uint8List _pcmFrames(int count) => Uint8List.fromList(
      List<int>.generate(640 * count, (index) => index & 0xff),
    );

Uint8List _wavHeader({required int pcmBytes}) {
  const sampleRate = 16000;
  const channels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  const blockAlign = channels * bitsPerSample ~/ 8;
  final data = ByteData(44);
  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + pcmBytes, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, pcmBytes, Endian.little);
  return data.buffer.asUint8List();
}

class _FakePcmAudioSink implements PcmAudioSink {
  _FakePcmAudioSink({this.acceptWrites = true});

  final bool acceptWrites;
  final starts = <({int sampleRate, int channels})>[];
  final writes = <Uint8List>[];
  var stops = 0;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    starts.add((sampleRate: sampleRate, channels: channels));
  }

  @override
  Future<Map<String, Object?>> status() async => {
        'writesAccepted': acceptWrites ? writes.length : 0,
        'writesDropped': acceptWrites ? 0 : writes.length,
      };

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<bool> write(Uint8List pcm16le) async {
    writes.add(Uint8List.fromList(pcm16le));
    return acceptWrites;
  }
}

class _DelayedStartPcmAudioSink extends _FakePcmAudioSink {
  final startEntered = Completer<void>();
  final releaseStart = Completer<void>();

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    starts.add((sampleRate: sampleRate, channels: channels));
    if (!startEntered.isCompleted) startEntered.complete();
    await releaseStart.future;
  }
}

class _FailingPcmAudioSink extends _FakePcmAudioSink {
  _FailingPcmAudioSink({required this.hangs});

  final bool hangs;

  @override
  Future<bool> write(Uint8List pcm16le) async {
    await super.write(pcm16le);
    if (writes.length == 8) {
      if (hangs) return Completer<bool>().future;
      throw StateError('native audio device disconnected');
    }
    return true;
  }
}
