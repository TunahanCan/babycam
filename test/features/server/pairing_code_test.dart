import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/security/secure_random_token_generator.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';

void main() {
  test('six-digit codes retain leading zeroes and the entire numeric range',
      () {
    final generator = SecureRandomTokenGenerator(random: _CodeRandom());
    expect(generator.generateSixDigitCode(), '000000');
    expect(generator.generateSixDigitCode(), '000042');
    expect(generator.generateSixDigitCode(), '999999');
  });

  test('public discovery cannot create, extend or reveal a pairing code', () {
    var now = DateTime(2026);
    final tokens = PairingTokenService(now: () => now);
    addTearDown(tokens.dispose);
    tokens.createPublicPairingNonce();
    expect(tokens.pairingCode, isNull);
    expect(tokens.pairingCodeExpiresAtMs, isNull);
    tokens.refreshPairingCode();
    final code = tokens.pairingCode;
    final expiry = tokens.pairingCodeExpiresAtMs;
    expect(code, matches(RegExp(r'^[0-9]{6}$')));
    expect(expiry, now.add(const Duration(minutes: 10)).millisecondsSinceEpoch);
    now = now.add(const Duration(minutes: 9));
    for (var index = 0; index < 100; index++) {
      tokens.createPublicPairingNonce();
    }
    expect(tokens.pairingCode, code);
    expect(tokens.pairingCodeExpiresAtMs, expiry);
    now = now.add(const Duration(minutes: 1));
    final nonce = tokens.createPublicPairingNonce();
    expect(tokens.pairingCode, isNull);
    expect(tokens.pairingCodeExpiresAtMs, expiry);
    expect(tokens.consumePairingInvitation(nonce, pairingCode: code),
        PairingInvitationResult.invalidCode);
  });

  test('public nonce needs the code through every consumption API', () {
    final tokens = PairingTokenService();
    addTearDown(tokens.dispose);
    tokens.refreshPairingCode();
    final code = tokens.pairingCode!;
    final nonce = tokens.createPublicPairingNonce();
    final qr = tokens.createPairingNonce();
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Remembered parent',
      deviceId: 'remembered',
    );
    expect(tokens.validateAndConsumeNonce(nonce), isFalse);
    expect(tokens.isPairingNonceActive(nonce), isTrue);
    expect(tokens.consumePairingInvitation(nonce, pairingCode: 'invalid'),
        PairingInvitationResult.invalidCode);
    expect(tokens.isPairingNonceActive(nonce), isTrue);
    expect(tokens.validateAndConsumeNonce(nonce, pairingCode: code), isTrue);
    expect(tokens.isPairingNonceActive(nonce), isFalse);
    expect(tokens.isPairingNonceActive(qr), isTrue);
    expect(tokens.validateTrustedClientToken(trusted.token), isNotNull);
    final nextNonce = tokens.createPublicPairingNonce();
    expect(nextNonce, isNot(nonce));
    expect(tokens.validateAndConsumeNonce(nextNonce), isFalse);
    expect(tokens.validateAndConsumeNonce(qr), isTrue);
  });

  test('global five-attempt budget survives refresh and pairing stop/start',
      () {
    var now = DateTime(2026);
    final tokens = PairingTokenService(now: () => now);
    addTearDown(tokens.dispose);
    tokens.refreshPairingCode();
    for (var index = 0; index < 5; index++) {
      expect(
          tokens.consumePairConfirmAttempt('192.168.1.${index + 1}'), isTrue);
      expect(
        tokens.consumePairingInvitation(tokens.createPublicPairingNonce()),
        PairingInvitationResult.invalidCode,
      );
      tokens.refreshPairingCode();
    }
    tokens.clearPairingNonces();
    expect(tokens.pairingCode, isNull);
    tokens.refreshPairingCode();
    final nonce = tokens.createPublicPairingNonce();
    expect(tokens.consumePairConfirmAttempt('192.168.1.200'), isTrue);
    expect(
      tokens.consumePairingInvitation(nonce, pairingCode: tokens.pairingCode),
      PairingInvitationResult.rateLimited,
    );
    final qr = tokens.createPairingNonce();
    expect(tokens.validateAndConsumeNonce(qr), isTrue);
    now = now.add(const Duration(minutes: 1));
    expect(
        tokens.validateAndConsumeNonce(nonce, pairingCode: tokens.pairingCode),
        isTrue);
  });

  test('QR source budget is separate, bounded and expires', () {
    var now = DateTime(2026);
    final tokens = PairingTokenService(
      now: () => now,
      maxPairConfirmSources: 1,
      maxPairConfirmAttemptsPerWindow: 2,
    );
    addTearDown(tokens.dispose);
    expect(tokens.consumePairConfirmAttempt('public-phone'), isTrue);
    expect(tokens.consumePairConfirmAttempt('another-public-phone'), isFalse);
    expect(tokens.consumeQrPairConfirmAttempt('qr-phone'), isTrue);
    expect(tokens.consumeQrPairConfirmAttempt('qr-phone'), isTrue);
    expect(tokens.consumeQrPairConfirmAttempt('qr-phone'), isFalse);
    expect(tokens.consumeQrPairConfirmAttempt('another-qr-phone'), isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(tokens.consumeQrPairConfirmAttempt('another-qr-phone'), isTrue);
    tokens.clearEphemeralState();
    expect(tokens.consumeQrPairConfirmAttempt('fresh-phone'), isTrue);
  });
}

class _CodeRandom implements Random {
  final _values = [0, 42, 999999].iterator;

  @override
  int nextInt(int max) {
    expect(max, 1000000);
    _values.moveNext();
    return _values.current;
  }

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
