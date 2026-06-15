import 'package:flutter_test/flutter_test.dart';
import 'package:babycam/core/protocol/pairing_payload.dart';

void main() {
  PairingPayload payload({int? expiresAtMs, int schemaVersion = 1}) => PairingPayload(
        schemaVersion: schemaVersion,
        host: '192.168.1.20',
        port: 8080,
        deviceId: 'server_abc',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: expiresAtMs ?? DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        capabilities: const {'video': 'mjpeg', 'audio': 'pcm16le', 'events': 'json'},
      );

  test('valid QR payload parse edilir', () {
    final parsed = PairingPayload.parseUri(payload().toUriString());
    expect(parsed, isNotNull);
    expect(parsed!.host, '192.168.1.20');
  });

  test('expired QR payload reddedilir', () {
    final parsed = PairingPayload.parseUri(payload(expiresAtMs: DateTime.now().subtract(const Duration(seconds: 1)).millisecondsSinceEpoch).toUriString());
    expect(parsed, isNull);
  });

  test('invalid schema reddedilir', () {
    final parsed = PairingPayload.parseUri(payload(schemaVersion: 2).toUriString());
    expect(parsed, isNull);
  });
}
