import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/media/mjpeg_stream_service.dart';
import 'package:miucam/features/server/media/wav_audio_stream_service.dart';

void main() {
  for (final video in [true, false]) {
    test('${video ? 'MJPEG' : 'WAV'} teardown aborts a blocked TCP connection',
        () async {
      const closeTimeout = Duration(milliseconds: 40);
      final videoService = MjpegStreamService(flushTimeout: closeTimeout);
      final audioService = WavAudioStreamService(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        flushTimeout: closeTimeout,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final backlogged = Completer<HttpResponse>();
      server.listen((request) async {
        if (video) {
          await videoService.attachClient(request.response, 'slow-client');
        } else {
          await audioService.attachClient(request.response, 'slow-client');
        }
        // Simulate output already buffered for a peer that has stopped
        // reading. This exceeds the loopback socket's send/receive buffers.
        request.response.add(Uint8List(8 * 1024 * 1024));
        backlogged.complete(request.response);
      });

      final socket =
          await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      addTearDown(socket.destroy);
      // Never subscribe to the response: the receiving TCP window fills.
      socket.write('GET /media HTTP/1.1\r\nHost: localhost\r\n\r\n');
      await socket.flush();
      final response =
          await backlogged.future.timeout(const Duration(seconds: 2));

      if (video) {
        await videoService.closeAll();
        expect(videoService.clientCount, 0);
      } else {
        await audioService.closeAll();
        expect(audioService.clientCount, 0);
      }
      await Future<void>.delayed(closeTimeout);

      // A Future.timeout alone returns with this connection still alive.
      expect(response.connectionInfo, isNull);
    });
  }
}
