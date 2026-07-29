import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/media/remote_broadcast_access_client.dart';

void main() {
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
        schemaVersion: 1,
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
