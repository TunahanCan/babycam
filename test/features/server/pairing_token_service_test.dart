import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';

void main() {
  test('pairing nonce tek kullanımlıktır', () {
    final service = PairingTokenService();
    final nonce = service.createPairingNonce();
    expect(service.validateAndConsumeNonce(nonce), isTrue);
    expect(service.validateAndConsumeNonce(nonce), isFalse);
  });

  test('expired nonce reddedilir', () {
    var now = DateTime(2026);
    final service = PairingTokenService(
        now: () => now, nonceTtl: const Duration(seconds: 1));
    final nonce = service.createPairingNonce();
    now = now.add(const Duration(seconds: 2));
    expect(service.validateAndConsumeNonce(nonce), isFalse);
  });

  test('nonce havuzu expired kayıtları temizler ve üst limiti korur', () {
    var now = DateTime(2026);
    final service = PairingTokenService(
      now: () => now,
      nonceTtl: const Duration(seconds: 1),
      maxActiveNonces: 2,
    );

    final first = service.createPairingNonce();
    final second = service.createPairingNonce();
    final third = service.createPairingNonce();

    expect(service.activeNonceCount, 2);
    expect(service.validateAndConsumeNonce(first), isFalse);
    expect(service.validateAndConsumeNonce(second), isTrue);
    expect(service.validateAndConsumeNonce(third), isTrue);

    service.createPairingNonce();
    now = now.add(const Duration(seconds: 2));

    expect(service.activeNonceCount, 0);
  });

  test('pair confirm denemeleri pencere içinde rate-limit edilir', () {
    var now = DateTime(2026);
    final service = PairingTokenService(
      now: () => now,
      pairConfirmRateLimitWindow: const Duration(seconds: 10),
      maxPairConfirmAttemptsPerWindow: 2,
    );

    expect(service.consumePairConfirmAttempt('192.168.1.5'), isTrue);
    expect(service.consumePairConfirmAttempt('192.168.1.5'), isTrue);
    expect(service.consumePairConfirmAttempt('192.168.1.5'), isFalse);
    expect(service.consumePairConfirmAttempt('192.168.1.6'), isTrue);

    now = now.add(const Duration(seconds: 11));

    expect(service.consumePairConfirmAttempt('192.168.1.5'), isTrue);
  });

  test('pairing başarılı olunca session token üretilir', () {
    final service = PairingTokenService();
    final token =
        service.issueSessionToken(clientName: 'client', deviceId: 'client_1');
    expect(token.length, greaterThanOrEqualTo(32));
    expect(service.validateSessionToken(token), isTrue);
    service.revokeSession(token);
    expect(service.validateSessionToken(token), isFalse);
  });
}
