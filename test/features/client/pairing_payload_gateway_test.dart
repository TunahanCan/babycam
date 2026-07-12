import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/features/client/pairing/pairing_failure.dart';
import 'package:mimicam/features/client/pairing/pairing_payload_gateway.dart';

void main() {
  test('public status response is adapted into a pairing payload', () async {
    final server = await _serve((request) {
      expect(request.uri.path, MimiCamProtocolV2.statusPublic);
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'serverDeviceId': 'room-1',
          'serverName': 'Bebek Odasi',
          'pairingNonce': 'nonce-1',
          'transport': 'http_ws',
          'capabilities': {'video': 'mjpeg'},
        }));
    });
    addTearDown(() => server.close(force: true));
    final gateway = HttpPairingPayloadGateway(
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );

    final payload = await gateway.fetch(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );

    expect(payload.deviceId, 'room-1');
    expect(payload.deviceName, 'Bebek Odasi');
    expect(payload.pairingNonce, 'nonce-1');
    expect(payload.capabilities, {'video': 'mjpeg'});
    expect(payload.expiresAtMs, 121000);
  });

  test('non-success status becomes a transport-independent failure', () async {
    final server = await _serve((request) {
      request.response.statusCode = HttpStatus.notFound;
    });
    addTearDown(() => server.close(force: true));

    final future = const HttpPairingPayloadGateway().fetch(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );

    await expectLater(
      future,
      throwsA(
        isA<PairingFailure>()
            .having(
              (failure) => failure.code,
              'code',
              PairingFailureCode.connectionUnavailable,
            )
            .having((failure) => failure.statusCode, 'statusCode', 404),
      ),
    );
  });

  test('malformed or incomplete status becomes invalidServerResponse',
      () async {
    final server = await _serve((request) {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'serverName': 'No nonce'}));
    });
    addTearDown(() => server.close(force: true));

    final future = const HttpPairingPayloadGateway().fetch(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );

    await expectLater(
      future,
      throwsA(
        isA<PairingFailure>().having(
          (failure) => failure.code,
          'code',
          PairingFailureCode.invalidServerResponse,
        ),
      ),
    );
  });
}

Future<HttpServer> _serve(void Function(HttpRequest request) respond) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    respond(request);
    await request.response.close();
  });
  return server;
}
