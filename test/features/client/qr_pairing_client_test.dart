import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/pairing/pairing_failure.dart';
import 'package:miucam/features/client/pairing/qr_pairing_client.dart';

void main() {
  test(
      're-pair proves remembered server-assigned identity only to its endpoint',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final bodies = <Map<String, dynamic>>[];
    server.listen((request) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'clientId': bodies.last['deviceId'],
        'trustedClientToken': 'replacement-token',
      }));
      await request.response.close();
    });
    PairingPayload payload({String serverId = 'room', int? port}) =>
        PairingPayload(
          schemaVersion: MiuCamProtocolV2.schemaVersion,
          host: InternetAddress.loopbackIPv4.address,
          port: port ?? server.port,
          deviceId: serverId,
          deviceName: 'Room',
          pairingNonce: 'new-nonce',
          expiresAtMs: DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          capabilities: const {'transport': 'http'},
        );
    final remembered = PairingSession(
        payload: payload(),
        sessionToken: 'remembered-secret',
        clientId: 'server-assigned-id');
    final client =
        QRPairingClient(clientIdProvider: () async => 'installation-id');
    await client.pair(payload(), rememberedSession: remembered);
    expect(bodies.last['deviceId'], 'server-assigned-id');
    expect(bodies.last['existingTrustedClientToken'], 'remembered-secret');

    await client.pair(payload(),
        rememberedSession:
            remembered.copyWith(payload: payload(serverId: 'other-room')));
    expect(bodies.last['deviceId'], 'installation-id');
    expect(bodies.last, isNot(contains('existingTrustedClientToken')));

    await client.pair(payload(),
        rememberedSession:
            remembered.copyWith(payload: payload(port: server.port + 1)));
    expect(bodies.last['deviceId'], 'installation-id');
    expect(bodies.last, isNot(contains('existingTrustedClientToken')));
  });

  test('QRPairingClient HTTP QR payload ile pair confirm gönderir', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, MiuCamProtocolV2.pairConfirm);

      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body);
      expect(json, isA<Map>());
      expect((json as Map)['pairingNonce'], 'nonce');
      expect(json['deviceId'], 'client_unique');
      expect(json['deviceId'], isNot('client_local'));
      expect(json['originServerDeviceId'], 'room_already_on_this_phone');

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'clientId': 'client_1',
        'trustedClientToken': 'trusted-token',
        'trustedClientTokenExpiresAtMs': 123,
      }));
      await request.response.close();
    });

    final payload = PairingPayload(
      schemaVersion: MiuCamProtocolV2.schemaVersion,
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

    final session = await QRPairingClient(
      clientIdProvider: () async => 'client_unique',
      localServerDeviceIdProvider: () async => 'room_already_on_this_phone',
    ).pair(payload);

    expect(session.clientId, 'client_1');
    expect(session.sessionToken, 'trusted-token');
    expect(session.payload.host, InternetAddress.loopbackIPv4.address);
  });

  test('pair/confirm hatalarını kullanıcı akışı için anlamlı koda çevirir',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.conflict;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ok': false,
        'code': 'SELF_PAIRING_NOT_ALLOWED',
        'message': 'A device cannot pair with its own room.',
      }));
      await request.response.close();
    });

    final payload = PairingPayload(
      schemaVersion: MiuCamProtocolV2.schemaVersion,
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      deviceId: 'server_1',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {'transport': 'http'},
    );

    await expectLater(
      const QRPairingClient().pair(payload),
      throwsA(
        isA<PairingFailure>().having(
          (failure) => failure.code,
          'code',
          PairingFailureCode.selfPairingNotAllowed,
        ),
      ),
    );
  });

  test('ulaşılamayan veya geçersiz pair yanıtı ham hata sızdırmaz', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write('temporary gateway failure');
      await request.response.close();
    });
    final payload = PairingPayload(
      schemaVersion: MiuCamProtocolV2.schemaVersion,
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      deviceId: 'server_1',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {'transport': 'http'},
    );

    await expectLater(
      const QRPairingClient().pair(payload),
      throwsA(
        isA<PairingFailure>().having(
          (failure) => failure.code,
          'code',
          PairingFailureCode.connectionUnavailable,
        ),
      ),
    );
  });
}
