import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/features/client/pairing/qr_pairing_client.dart';

void main() {
  test('QRPairingClient HTTP QR payload ile pair confirm gönderir', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, MimiCamProtocolV2.pairConfirm);

      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body);
      expect(json, isA<Map>());
      expect((json as Map)['pairingNonce'], 'nonce');

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'clientId': 'client_1',
        'trustedClientToken': 'trusted-token',
        'trustedClientTokenExpiresAtMs': 123,
      }));
      await request.response.close();
    });

    final payload = PairingPayload(
      schemaVersion: MimiCamProtocolV2.schemaVersion,
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      deviceId: 'server_1',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {
        'video': 'mjpeg',
        'audio': 'pcm16le',
        'events': 'json',
        'transport': 'http',
      },
    );

    final session = await (const QRPairingClient()).pair(payload);

    expect(session.clientId, 'client_1');
    expect(session.sessionToken, 'trusted-token');
    expect(session.payload.host, InternetAddress.loopbackIPv4.address);
  });
}
