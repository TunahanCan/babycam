import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';

void main() {
  test('pairing nonce tek kullanımlıktır', () {
    final service = PairingTokenService();
    final nonce = service.createPairingNonce();
    expect(service.validateAndConsumeNonce(nonce), isTrue);
    expect(service.validateAndConsumeNonce(nonce), isFalse);
  });

  test('expired nonce reddedilir', () {
    var now = DateTime(2026);
    final service = PairingTokenService(now: () => now, nonceTtl: const Duration(seconds: 1));
    final nonce = service.createPairingNonce();
    now = now.add(const Duration(seconds: 2));
    expect(service.validateAndConsumeNonce(nonce), isFalse);
  });

  test('pairing başarılı olunca session token üretilir', () {
    final service = PairingTokenService();
    final token = service.issueSessionToken(clientName: 'client', deviceId: 'client_1');
    expect(token.length, greaterThanOrEqualTo(32));
    expect(service.validateSessionToken(token), isTrue);
    service.revokeSession(token);
    expect(service.validateSessionToken(token), isFalse);
  });
}
