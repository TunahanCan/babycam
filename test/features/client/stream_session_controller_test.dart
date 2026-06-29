import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/media/client_stream_health_state.dart';
import 'package:mimicam/features/client/media/stream_session_controller.dart';

void main() {
  test('health state session start sonrası ayrı video/audio request açmaz',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var videoRequests = 0;
    var audioRequests = 0;
    Map<String, Object?>? sessionStartBody;
    server.listen((request) async {
      if (request.uri.path == MimiCamProtocolV2.sessionStart) {
        final body = await utf8.decoder.bind(request).join();
        sessionStartBody = Map<String, Object?>.from(jsonDecode(body) as Map);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'ok': true,
          'streamToken': 'stream_token',
          'streamTokenExpiresAtMs': DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        }));
        await request.response.close();
        return;
      }
      if (request.uri.path == MimiCamProtocolV2.video) {
        videoRequests++;
        request.response.add([1, 2, 3]);
        await request.response.close();
        return;
      }
      if (request.uri.path == MimiCamProtocolV2.audio) {
        audioRequests++;
        request.response.add([4, 5, 6]);
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    final health = ClientStreamHealthState();
    final controller = StreamSessionController(
      healthState: health,
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    final active = await controller.start(
      _session(server.port),
      audioEnabled: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final snapshot = health.snapshot();

    expect(snapshot.watchActive, isTrue);
    expect(sessionStartBody?['audio'], isTrue);
    expect(sessionStartBody?['video'], isTrue);
    expect(controller.lastStreamToken, 'stream_token');
    expect(active?.audioEnabled, isTrue);
    expect(snapshot.lastVideoFrameAtMs, isNull);
    expect(snapshot.lastAudioChunkAtMs, isNull);
    expect(videoRequests, 0);
    expect(audioRequests, 0);
  });

  test('session start hatası server mesajını taşır', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'ok': false,
          'code': 'MEDIA_START_FAILED',
          'message': 'Kamera izni verilmedi',
        }));
      await request.response.close();
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.start(_session(server.port)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Kamera izni verilmedi'),
        ),
      ),
    );
  });

  test('session start streamToken donmezse aktif state acilmaz', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true}));
      await request.response.close();
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.start(_session(server.port)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('stream token'),
        ),
      ),
    );

    expect(controller.isActive, isFalse);
    expect(controller.lastStreamToken, isNull);
  });
}

PairingSession _session(int port) => PairingSession(
      payload: PairingPayload(
        schemaVersion: MimiCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        deviceId: 'server',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {'transport': 'http'},
      ),
      sessionToken: 'token',
      clientId: 'client',
    );
