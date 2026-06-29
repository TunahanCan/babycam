import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/media/mjpeg_stream_service.dart';

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
}
