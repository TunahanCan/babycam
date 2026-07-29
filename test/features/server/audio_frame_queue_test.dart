import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/media/wav_audio_stream_service.dart';

void main() {
  test('PCM recorder burstlerini 20 ms 640-byte framelere ayirir', () {
    final packetizer = PcmAudioFramePacketizer(
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
    );

    expect(packetizer.add(Uint8List(500)), isEmpty);
    final frames = packetizer.add(Uint8List(900));

    expect(frames, hasLength(2));
    expect(frames, everyElement(hasLength(640)));
    expect(packetizer.pendingBytes, 120);
  });

  test('bounded audio queue dolunca en eski gonderilmemis framei ezer', () {
    final queue = BoundedAudioFrameQueue(maxFrames: 3);

    expect(queue.add(Uint8List.fromList([1])), 0);
    expect(queue.add(Uint8List.fromList([2])), 0);
    expect(queue.add(Uint8List.fromList([3])), 0);
    expect(queue.add(Uint8List.fromList([4])), 1);

    expect(queue.length, 3);
    expect(queue.takeNext(), [2]);
    expect(queue.takeNext(), [3]);
    expect(queue.takeNext(), [4]);
  });

  test('ilk WAV flush timeout olursa client attach edilmis birakilmaz',
      () async {
    final stalledFlush = Completer<void>();
    final detached = Completer<String>();
    final attachReturned = Completer<void>();
    final service = WavAudioStreamService(
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
      flushTimeout: const Duration(milliseconds: 30),
      responseFlusher: (_) => stalledFlush.future,
      onClientDetached: (clientId) {
        if (!detached.isCompleted) detached.complete(clientId);
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) {
      unawaited(() async {
        await service.attachClient(request.response, 'attach-timeout');
        if (!attachReturned.isCompleted) attachReturned.complete();
      }());
    });
    final client = HttpClient();
    addTearDown(() async {
      if (!stalledFlush.isCompleted) stalledFlush.complete();
      await service.closeAll();
      client.close(force: true);
      await requests.cancel();
      await server.close(force: true);
    });

    final request = await client.getUrl(_audioUri(server));
    unawaited(_discardResponse(request.close()));

    expect(
      await detached.future.timeout(const Duration(seconds: 1)),
      'attach-timeout',
    );
    await attachReturned.future.timeout(const Duration(seconds: 1));
    expect(service.clientCount, 0);
  });

  test('attach header flush surerken broadcast ikinci flush baslatmaz',
      () async {
    final allowHeaderFlush = Completer<void>();
    final headerFlushStarted = Completer<void>();
    final drainFlushStarted = Completer<void>();
    final attached = Completer<void>();
    var flushCalls = 0;
    final service = WavAudioStreamService(
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
      flushTimeout: const Duration(seconds: 1),
      responseFlusher: (response) async {
        flushCalls++;
        if (flushCalls == 1) {
          headerFlushStarted.complete();
          await allowHeaderFlush.future;
        } else if (flushCalls == 2) {
          drainFlushStarted.complete();
        }
        await response.flush();
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) {
      unawaited(() async {
        await service.attachClient(request.response, 'attach-race');
        if (!attached.isCompleted) attached.complete();
      }());
    });
    final client = HttpClient();
    addTearDown(() async {
      if (!allowHeaderFlush.isCompleted) allowHeaderFlush.complete();
      await service.closeAll();
      client.close(force: true);
      await requests.cancel();
      await server.close(force: true);
    });

    final request = await client.getUrl(_audioUri(server));
    unawaited(_discardResponse(request.close()));
    await headerFlushStarted.future.timeout(const Duration(seconds: 1));

    service.broadcast(Uint8List(640));

    expect(flushCalls, 1);
    expect(service.snapshot.busyClientIds, ['attach-race']);

    allowHeaderFlush.complete();
    await attached.future.timeout(const Duration(seconds: 1));
    await drainFlushStarted.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(flushCalls, 2);
    expect(service.snapshot.chunksStreamed, 1);
  });

  test('WAV drain flush timeout olursa yavas client detach edilir', () async {
    final stalledFlush = Completer<void>();
    final attached = Completer<void>();
    final detached = Completer<String>();
    var flushCalls = 0;
    final service = WavAudioStreamService(
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
      flushTimeout: const Duration(milliseconds: 30),
      responseFlusher: (response) {
        flushCalls++;
        return flushCalls == 1 ? response.flush() : stalledFlush.future;
      },
      onClientDetached: (clientId) {
        if (!detached.isCompleted) detached.complete(clientId);
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) {
      unawaited(() async {
        await service.attachClient(request.response, 'drain-timeout');
        if (!attached.isCompleted) attached.complete();
      }());
    });
    final client = HttpClient();
    addTearDown(() async {
      if (!stalledFlush.isCompleted) stalledFlush.complete();
      await service.closeAll();
      client.close(force: true);
      await requests.cancel();
      await server.close(force: true);
    });

    final request = await client.getUrl(_audioUri(server));
    unawaited(_discardResponse(request.close()));
    await attached.future.timeout(const Duration(seconds: 1));

    service.broadcast(Uint8List(640));

    expect(
      await detached.future.timeout(const Duration(seconds: 1)),
      'drain-timeout',
    );
    expect(service.clientCount, 0);
  });

  test('WAV queue tasarsa sessiz frame kaybi yerine client detach edilir',
      () async {
    final stalledFlush = Completer<void>();
    final drainStarted = Completer<void>();
    final attached = Completer<void>();
    final detachedClients = <String>[];
    var flushCalls = 0;
    final service = WavAudioStreamService(
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
      maxQueuedAudio: const Duration(milliseconds: 40),
      flushTimeout: const Duration(seconds: 1),
      responseFlusher: (response) {
        flushCalls++;
        if (flushCalls == 1) return response.flush();
        if (!drainStarted.isCompleted) drainStarted.complete();
        return stalledFlush.future;
      },
      onClientDetached: detachedClients.add,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) {
      unawaited(() async {
        await service.attachClient(request.response, 'queue-overflow');
        if (!attached.isCompleted) attached.complete();
      }());
    });
    final client = HttpClient();
    addTearDown(() async {
      if (!stalledFlush.isCompleted) stalledFlush.complete();
      await service.closeAll();
      client.close(force: true);
      await requests.cancel();
      await server.close(force: true);
    });

    final request = await client.getUrl(_audioUri(server));
    unawaited(_discardResponse(request.close()));
    await attached.future.timeout(const Duration(seconds: 1));

    service.broadcast(Uint8List(640));
    await drainStarted.future.timeout(const Duration(seconds: 1));
    service.broadcast(Uint8List(640));
    service.broadcast(Uint8List(640));
    service.broadcast(Uint8List(640));

    expect(detachedClients, ['queue-overflow']);
    expect(service.clientCount, 0);

    stalledFlush.complete();
    await Future<void>.delayed(Duration.zero);
    expect(service.clientCount, 0);
  });
}

Uri _audioUri(HttpServer server) =>
    Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${server.port}/');

Future<void> _discardResponse(Future<HttpClientResponse> response) async {
  try {
    await (await response).drain<void>();
  } catch (_) {}
}
