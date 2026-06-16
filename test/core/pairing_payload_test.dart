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
        capabilities: const {
          'video': 'mjpeg',
          'audio': 'pcm16le',
          'events': 'json'
        },
      );

  test('valid QR payload parse edilir', () {
    final parsed = PairingPayload.parseUri(payload().toUriString());
    expect(parsed, isNotNull);
    expect(parsed!.host, '192.168.1.20');
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

  test('server QR payload mevcut HTTP server ile uyumlu üretilir', () {
    final builder = ServerQrPayloadBuilder(tokenService: PairingTokenService());

    final payload = builder.build(host: '192.168.1.20');

    expect(payload.certificateFingerprintSha256, isEmpty);
    expect(payload.capabilities['transport'], 'http');
  });
}
