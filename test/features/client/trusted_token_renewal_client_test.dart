import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/pairing/trusted_token_renewal_client.dart';

void main() {
  test('başarılı renew yeni token ve clientId döner', () async {
    final server = await _renewServer((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer old-token',
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'clientId': 'client-2',
        'trustedClientToken': 'new-token',
        'expiresAtMs': 9999,
      }));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final renewed =
        await TrustedTokenRenewalClient().renew(_session(server.port));

    expect(renewed, isNotNull);
    expect(renewed!.sessionToken, 'new-token');
    expect(renewed.clientId, 'client-2');
    expect(renewed.trustedClientTokenExpiresAtMs, 9999);
  });

  test('401 renew sonucu null döner', () async {
    final server = await _renewServer((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final renewed =
        await TrustedTokenRenewalClient().renew(_session(server.port));

    expect(renewed, isNull);
  });

  test('eksik token içeren response hata üretir', () async {
    final server = await _renewServer((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'clientId': 'client-2'}));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    expect(
      () => TrustedTokenRenewalClient().renew(_session(server.port)),
      throwsStateError,
    );
  });
}

Future<HttpServer> _renewServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == MimiCamProtocolV2.authRenew) {
      await handler(request);
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  });
  return server;
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
      sessionToken: 'old-token',
      clientId: 'client-1',
      trustedClientTokenExpiresAtMs: 1234,
    );
