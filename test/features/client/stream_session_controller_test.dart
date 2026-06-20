import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/media/client_stream_health_monitor.dart';
import 'package:mimicam/features/client/media/stream_session_controller.dart';

void main() {
  test('session start sonrası video ve audio reader health monitor besler',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == MimiCamProtocolV2.sessionStart) {
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
        request.response.add([1, 2, 3]);
        await request.response.close();
        return;
      }
      if (request.uri.path == MimiCamProtocolV2.audio) {
        request.response.add([4, 5, 6]);
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    final health = ClientStreamHealthMonitor();
    final controller = StreamSessionController(
      healthMonitor: health,
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    await controller.start(_session(server.port));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final snapshot = health.snapshot();

    expect(snapshot.watchActive, isTrue);
    expect(snapshot.lastVideoFrameAtMs, isNotNull);
    expect(snapshot.lastAudioChunkAtMs, isNotNull);
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
