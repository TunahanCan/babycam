import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/media/remote_broadcast_access_client.dart';

void main() {
  test('status and family grants cannot redirect to another endpoint',
      () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => origin.close(force: true));
    addTearDown(() => other.close(force: true));
    var redirectedRequests = 0;
    other.listen((request) async {
      redirectedRequests++;
      request.response.write('{}');
      await request.response.close();
    });
    origin.listen((request) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader,
            'http://127.0.0.1:${other.port}/license');
      await request.response.close();
    });
    final remote = RemoteBroadcastAccessClient();
    await expectLater(
        remote.snapshot(_sessionFor(origin)), throwsA(isA<HttpException>()));
    await expectLater(
        remote.readLicense(_sessionFor(origin)), throwsA(isA<HttpException>()));
    expect(redirectedRequests, 0);
  });

  test('chunked status body is rejected at the configured memory bound',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write('x' * 1024);
      await request.response.close();
    });
    await expectLater(
      RemoteBroadcastAccessClient(maxResponseBytes: 128)
          .snapshot(_sessionFor(server)),
      throwsA(isA<FormatException>()
          .having((error) => error.message, 'message', contains('too large'))),
    );
  });

  test('reads authoritative broadcast access with the trusted bearer',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final handled = Completer<void>();
    server.listen((request) async {
      expect(request.uri.path, MiuCamProtocolV2.status);
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer trusted-token',
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'broadcastAccess': {
          'unlocked': false,
          'active': true,
          'freeLimitMs': 100,
          'usedMs': 75,
          'remainingMs': 25,
          'priceLabel': r'$9.99',
          'productId': 'miucam.broadcast.lifetime',
        },
      }));
      await request.response.close();
      handled.complete();
    });
    final session = PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        deviceId: 'room',
        deviceName: 'Room',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: 'trusted-token',
    );

    final snapshot = await RemoteBroadcastAccessClient().snapshot(session);

    expect(snapshot?.remainingMs, 25);
    expect(snapshot?.active, isTrue);
    await handled.future;
  });
}

PairingSession _sessionFor(HttpServer server) => PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        deviceId: 'room',
        deviceName: 'Room',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: 'trusted-token',
    );
