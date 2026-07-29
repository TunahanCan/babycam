import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/media/mjpeg_stream_service.dart';

void main() {
  test('hazir frame yokken MJPEG stream headerini flush eder', () async {
    final service = MjpegStreamService();
    addTearDown(service.closeAll);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });

    server.listen((request) async {
      await service.attachClient(request.response, 'client');
      await release.future;
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    addTearDown(() => client.close(force: true));

    final request = await client.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/video',
    ));
    final response = await request.close().timeout(const Duration(seconds: 1));

    expect(response.statusCode, HttpStatus.ok);
    expect(
      response.headers.contentType?.mimeType,
      'multipart/x-mixed-replace',
    );
    expect(service.clientCount, 1);

    client.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('MJPEG header flush timeout client baglantisini kapatir', () async {
    final stalledFlush = Completer<void>();
    final detached = Completer<String>();
    final attachReturned = Completer<void>();
    final service = MjpegStreamService(
      flushTimeout: const Duration(milliseconds: 30),
      responseFlusher: (_) => stalledFlush.future,
      onClientDetached: (clientId) {
        if (!detached.isCompleted) detached.complete(clientId);
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) {
      unawaited(() async {
        await service.attachClient(request.response, 'header-timeout');
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

    final request = await client.getUrl(_videoUri(server));
    unawaited(_discardResponse(request.close()));

    expect(
      await detached.future.timeout(const Duration(seconds: 1)),
      'header-timeout',
    );
    await attachReturned.future.timeout(const Duration(seconds: 1));
    expect(service.clientCount, 0);
  });

  test('MJPEG frame flush timeout yavas client baglantisini kapatir', () async {
    final stalledFlush = Completer<void>();
    final attached = Completer<void>();
    final detached = Completer<String>();
    var flushCalls = 0;
    final service = MjpegStreamService(
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
        await service.attachClient(request.response, 'frame-timeout');
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

    final request = await client.getUrl(_videoUri(server));
    unawaited(_discardResponse(request.close()));
    await attached.future.timeout(const Duration(seconds: 1));

    service.broadcast(Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]));

    expect(
      await detached.future.timeout(const Duration(seconds: 1)),
      'frame-timeout',
    );
    expect(flushCalls, 2);
    expect(service.clientCount, 0);
  });
}

Uri _videoUri(HttpServer server) =>
    Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${server.port}/');

Future<void> _discardResponse(Future<HttpClientResponse> response) async {
  try {
    await (await response).drain<void>();
  } catch (_) {}
}
