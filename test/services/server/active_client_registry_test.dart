import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/services/server/active_client_registry.dart';

void main() {
  test('session/start aynı client için slot sayısını artırmaz', () {
    final tokenService = PairingTokenService();
    final registry = ActiveClientRegistry(
      tokenService: tokenService,
      maxActiveClients: 5,
    );

    final first = registry.startSession('anne');
    final second = registry.startSession('anne');

    expect(first.createdActiveSlot, isTrue);
    expect(second.createdActiveSlot, isFalse);
    expect(registry.activeClientCount, 1);
    expect(first.streamToken.token, isNot(second.streamToken.token));
  });

  test('medya disconnect aktif watch session ve tokeni düşürmez', () {
    final tokenService = PairingTokenService();
    final registry = ActiveClientRegistry(
      tokenService: tokenService,
      maxActiveClients: 1,
    );

    final started = registry.startSession('anne');
    expect(
      () => registry.startSession('baba'),
      throwsA(isA<ActiveClientLimitException>()),
    );

    registry.attachStream('anne');
    registry.detachStream('anne');

    expect(registry.activeClientCount, 1);
    expect(
        tokenService.validateStreamToken(started.streamToken.token), isNotNull);

    registry.stopSession('anne');
    final accepted = registry.startSession('baba');
    expect(accepted.clientId, 'baba');
  });

  test('stream token expiry aktif slotu prune eder', () {
    var now = DateTime(2026);
    final tokenService = PairingTokenService(
      now: () => now,
      streamTokenTtl: const Duration(seconds: 1),
    );
    final registry = ActiveClientRegistry(
      tokenService: tokenService,
      maxActiveClients: 1,
    );

    registry.startSession('anne');
    expect(registry.activeClientCount, 1);

    now = now.add(const Duration(seconds: 2));
    registry.pruneExpiredStreamTokens();

    expect(registry.activeClientCount, 0);
    expect(registry.startSession('baba').clientId, 'baba');
  });

  test('aynı client video ve audio reconnect için session açık kalır', () {
    final tokenService = PairingTokenService();
    final registry = ActiveClientRegistry(
      tokenService: tokenService,
      maxActiveClients: 1,
    );

    final started = registry.startSession('anne');
    registry
      ..attachStream('anne')
      ..attachStream('anne');

    registry.detachStream('anne');
    expect(registry.activeClientCount, 1);

    registry.detachStream('anne');
    expect(registry.activeClientCount, 1);
    expect(
        tokenService.validateStreamToken(started.streamToken.token), isNotNull);

    registry.stopSession('anne');
    expect(registry.activeClientCount, 0);
  });
}
