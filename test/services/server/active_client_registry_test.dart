import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/services/server/active_client_registry.dart';

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
    expect(
      registry.clientIdForStreamToken(first.streamToken.token),
      isNull,
    );
    expect(
      registry.clientIdForStreamToken(second.streamToken.token),
      'anne',
    );
  });

  test('başarısız replacement yalnız yeni stream tokenini geri alır', () {
    final tokenService = PairingTokenService();
    final registry = ActiveClientRegistry(
      tokenService: tokenService,
      maxActiveClients: 5,
    );

    final first = registry.startSession('anne');
    final replacement = registry.startSession('anne');
    registry.rollbackSessionStart(replacement);

    expect(registry.activeClientCount, 1);
    expect(
        tokenService.validateStreamToken(first.streamToken.token), isNotNull);
    expect(
      tokenService.validateStreamToken(replacement.streamToken.token),
      isNull,
    );
    expect(
      registry.clientIdForStreamToken(first.streamToken.token),
      'anne',
    );
    expect(
      registry.clientIdForStreamToken(replacement.streamToken.token),
      isNull,
    );
  });

  test('gec kalan rollback daha yeni token sahibini geri alamaz', () {
    final tokenService = PairingTokenService();
    final registry = ActiveClientRegistry(
      tokenService: tokenService,
      maxActiveClients: 5,
    );

    final first = registry.startSession('anne');
    final staleReplacement = registry.startSession('anne');
    final current = registry.startSession('anne');
    registry.rollbackSessionStart(staleReplacement);

    expect(registry.activeClientCount, 1);
    expect(
      registry.clientIdForStreamToken(first.streamToken.token),
      isNull,
    );
    expect(
      registry.clientIdForStreamToken(staleReplacement.streamToken.token),
      isNull,
    );
    expect(
      registry.clientIdForStreamToken(current.streamToken.token),
      'anne',
    );
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

  test(
      'token expiry sağlıklı medya leaseini korur ve son lease sonrası temizliği bildirir',
      () {
    var now = DateTime(2026);
    final tokenService = PairingTokenService(
      now: () => now,
      streamTokenTtl: const Duration(seconds: 1),
    );
    final expiredSessions = <String>[];
    final registry = ActiveClientRegistry(
      tokenService: tokenService,
      maxActiveClients: 1,
    )..bindExpiredSessionReadyCallback(expiredSessions.add);

    registry.startSession('anne');
    final transportLease = registry.attachStream('anne');

    now = now.add(const Duration(seconds: 2));
    registry.pruneExpiredStreamTokens();

    expect(expiredSessions, isEmpty);
    expect(registry.activeClientCount, 1);
    expect(registry.mediaConnectionCount, 1);
    expect(registry.isExpiredSessionReady('anne'), isFalse);

    transportLease.release();

    expect(expiredSessions, ['anne']);
    expect(registry.activeClientCount, 1);
    expect(registry.mediaConnectionCount, 0);
    expect(registry.isExpiredSessionReady('anne'), isTrue);

    registry.cleanupClient('anne');
    expect(registry.activeClientCount, 0);
  });

  test('yeni token sıradaki gecikmiş expiry temizliğini geçersiz kılar', () {
    var now = DateTime(2026);
    final tokenService = PairingTokenService(
      now: () => now,
      streamTokenTtl: const Duration(seconds: 1),
    );
    final expiredSessions = <String>[];
    final registry = ActiveClientRegistry(
      tokenService: tokenService,
      maxActiveClients: 1,
    )..bindExpiredSessionReadyCallback(expiredSessions.add);

    registry.startSession('anne');
    now = now.add(const Duration(seconds: 2));
    registry.pruneExpiredStreamTokens();
    expect(expiredSessions, ['anne']);
    expect(registry.isExpiredSessionReady('anne'), isTrue);

    final replacement = registry.startSession('anne');

    expect(registry.isExpiredSessionReady('anne'), isFalse);
    expect(
      registry.clientIdForStreamToken(replacement.streamToken.token),
      'anne',
    );
    expect(registry.activeClientCount, 1);
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

  test('media lease limitleri per-client ve toplam kapasiteyi fail-fast korur',
      () {
    final registry = ActiveClientRegistry(
      tokenService: PairingTokenService(),
      maxActiveClients: 5,
      maxMediaConnectionsPerClient: 2,
      maxTotalMediaConnections: 2,
    );

    final video = registry.attachStream('anne');
    final audio = registry.attachStream('anne');

    expect(registry.mediaConnectionCount, 2);
    expect(
      () => registry.attachStream('anne'),
      throwsA(
        isA<ConnectionLimitException>().having(
          (error) => error.scope,
          'scope',
          ConnectionLimitScope.client,
        ),
      ),
    );
    expect(
      () => registry.attachStream('baba'),
      throwsA(
        isA<ConnectionLimitException>().having(
          (error) => error.scope,
          'scope',
          ConnectionLimitScope.server,
        ),
      ),
    );

    video
      ..release()
      ..release();
    expect(registry.mediaConnectionCount, 1);
    expect(audio.isReleased, isFalse);
    final baba = registry.attachStream('baba');
    expect(registry.mediaConnectionCount, 2);

    audio.release();
    baba.release();
    expect(registry.mediaConnectionCount, 0);
  });

  test('event socket lease aynı client ve toplam bağlantı sınırını korur', () {
    final registry = ActiveClientRegistry(
      tokenService: PairingTokenService(),
      maxActiveClients: 5,
      maxEventSocketsPerClient: 1,
      maxTotalEventSockets: 2,
    );

    final anne = registry.attachEventSocket('anne');
    final baba = registry.attachEventSocket('baba');

    expect(
      () => registry.attachEventSocket('anne'),
      throwsA(
        isA<ConnectionLimitException>().having(
          (error) => error.scope,
          'scope',
          ConnectionLimitScope.client,
        ),
      ),
    );
    expect(
      () => registry.attachEventSocket('dede'),
      throwsA(
        isA<ConnectionLimitException>().having(
          (error) => error.scope,
          'scope',
          ConnectionLimitScope.server,
        ),
      ),
    );

    anne
      ..release()
      ..release();
    expect(registry.eventSocketCount, 1);
    final dede = registry.attachEventSocket('dede');
    expect(registry.eventSocketCount, 2);

    baba.release();
    dede.release();
    expect(registry.eventSocketCount, 0);
  });
}
