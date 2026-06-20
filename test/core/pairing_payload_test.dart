import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/features/server/pairing/server_qr_payload_builder.dart';

void main() {
  PairingPayload payload({int? expiresAtMs, int schemaVersion = 1}) =>
      PairingPayload(
        schemaVersion: schemaVersion,
        host: '192.168.1.20',
        port: 8080,
        deviceId: 'server_abc',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: expiresAtMs ??
            DateTime.now()
                .add(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
        transport: 'http_ws',
        capabilities: const {
          'video': 'mjpeg',
          'audio': 'pcm16le',
          'events': 'json',
          'maxClients': 5,
        },
      );

  test('valid QR payload parse edilir', () {
    final parsed = PairingPayload.parseUri(payload().toUriString());
    expect(parsed, isNotNull);
    expect(parsed!.host, '192.168.1.20');
    expect(parsed.httpScheme, 'http');
    expect(parsed.wsScheme, 'ws');
  });

  test('expired QR payload reddedilir', () {
    final parsed = PairingPayload.parseUri(payload(
            expiresAtMs: DateTime.now()
                .subtract(const Duration(seconds: 1))
                .millisecondsSinceEpoch)
        .toUriString());
    expect(parsed, isNull);
  });

  test('invalid schema reddedilir', () {
    final parsed =
        PairingPayload.parseUri(payload(schemaVersion: 2).toUriString());
    expect(parsed, isNull);
  });

  test('server QR payload HTTP/WS transport ile üretilir', () {
    final builder = ServerQrPayloadBuilder(tokenService: PairingTokenService());

    final payload = builder.build(host: '192.168.1.20');

    expect(payload.transport, 'http_ws');
    expect(payload.httpScheme, 'http');
    expect(payload.wsScheme, 'ws');
    expect(payload.capabilities['maxClients'], 5);
  });

  test('transport alanı olmadan gelen payload HTTP/WS kabul edilir', () {
    final parsed = PairingPayload.fromJson({
      'schemaVersion': 1,
      'scheme': 'mimicam',
      'host': '192.168.1.20',
      'port': 8080,
      'deviceId': 'server',
      'deviceName': 'Bebek Odası',
      'pairingNonce': 'nonce',
      'expiresAtMs':
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      'capabilities': {'maxClients': 5},
    });

    expect(parsed, isNotNull);
    expect(parsed!.transport, 'http_ws');
    expect(parsed.httpScheme, 'http');
    expect(parsed.wsScheme, 'ws');
  });
}
