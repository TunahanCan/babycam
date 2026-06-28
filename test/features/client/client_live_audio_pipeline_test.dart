import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/client/media/client_live_audio_pipeline.dart';
import 'package:mimicam/features/client/media/pcm_audio_output.dart';

void main() {
  test('Bearer token ile WAV streami acar ve PCM native sinke yazar', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final authHeaders = <String>[];
    server.listen((request) async {
      authHeaders
          .add(request.headers.value(HttpHeaders.authorizationHeader) ?? '');
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response.add(_wavHeader(pcmBytes: 8));
      request.response.add(Uint8List.fromList([1, 0, 2, 0, 3, 0, 4, 0]));
      await request.response.flush();
      await request.response.close();
    });
    final sink = _FakePcmAudioSink();
    final pipeline = ClientLiveAudioPipeline(
      audioOutput: sink,
      retryDelay: const Duration(milliseconds: 20),
    );
    addTearDown(pipeline.stop);
    final wrote = Completer<void>();

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
        if (!wrote.isCompleted) wrote.complete();
      },
    );

    await wrote.future.timeout(const Duration(seconds: 2));
    expect(authHeaders.first, 'Bearer trusted-token');
    expect(sink.starts, [(sampleRate: 16000, channels: 1)]);
    expect(sink.writes.single, [1, 0, 2, 0, 3, 0, 4, 0]);
  });

  test('native write reddedilirse status droppedNativeWrites sayar', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response
        ..add(_wavHeader(pcmBytes: 4))
        ..add(Uint8List.fromList([1, 0, 2, 0]));
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
}

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
