import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/security/transport_security_config.dart';
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
        certificateFingerprintSha256: 'ab' * 32,
        transport: const {
          'httpScheme': 'https',
          'wsScheme': 'wss',
          'tlsMode': 'selfSignedPinned',
        },
        capabilities: const {
          'video': 'mjpeg',
          'audio': 'pcm16le',
          'events': 'json',
          'transport': 'https',
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

  test('server QR payload pinned HTTPS transport ile üretilir', () {
    final builder = ServerQrPayloadBuilder(tokenService: PairingTokenService());

    final payload = builder.build(
      host: '192.168.1.20',
      certificateFingerprintSha256: 'cd' * 32,
    );

    expect(payload.certificateFingerprintSha256, 'cd' * 32);
    expect(payload.transport['httpScheme'], 'https');
    expect(payload.transport['wsScheme'], 'wss');
    expect(payload.capabilities['transport'], 'https');
  });

  test('eski payload transport alanı olmadan parse edilebilir', () {
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
      'capabilities': {'transport': 'http'},
    });

    expect(parsed, isNotNull);
    expect(parsed!.httpScheme, 'http');
    expect(parsed.wsScheme, 'ws');
  });

  test('insecure dev config QR payload içinde HTTP/WS taşıyabilir', () {
    final builder = ServerQrPayloadBuilder(
      tokenService: PairingTokenService(),
      transportSecurityConfig: TransportSecurityConfig.insecureDevOnly,
    );

    final payload = builder.build(host: '127.0.0.1');

    expect(payload.transport['httpScheme'], 'http');
    expect(payload.transport['wsScheme'], 'ws');
    expect(payload.capabilities['transport'], 'http');
  });
}
