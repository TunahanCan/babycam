import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('trusted client hash ile kalici olur ve server yeniden acilinca taninir',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final first = PairingTokenService(
      trustedClientRepository: SharedPreferencesTrustedClientRepository(
        preferences,
      ),
    );
    final token = first.issueTrustedClientToken(
      clientName: 'Parent',
      deviceId: 'parent-1',
    );
    await first.flushPersistence();

    final stored = preferences.getString(
      SharedPreferencesTrustedClientRepository.defaultStorageKey,
    );
    expect(stored, isNotNull);
    expect(stored, isNot(contains(token.token)));
    expect(stored, contains(first.hashToken(token.token)));

    first.clearEphemeralState();
    final restarted = PairingTokenService(
      trustedClientRepository: SharedPreferencesTrustedClientRepository(
        preferences,
      ),
    );

    expect(
      restarted.validateTrustedClientToken(token.token)?.clientId,
      'parent-1',
    );
    expect(restarted.pairedClientCount, 1);
  });

  test('revoke kalici olur ve restart sonrasi token reddedilir', () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesTrustedClientRepository(preferences);
    final first = PairingTokenService(trustedClientRepository: repository);
    final token = first.issueTrustedClientToken(
      clientName: 'Parent',
      deviceId: 'parent-1',
    );
    await first.flushPersistence();
    first.revokeClient(token.clientId);
    await first.flushPersistence();

    final restarted = PairingTokenService(
      trustedClientRepository: SharedPreferencesTrustedClientRepository(
        preferences,
      ),
    );

    expect(restarted.validateTrustedClientToken(token.token), isNull);
    expect(restarted.pairedClientCount, 0);
  });

  test('expired persisted client aktif slotu bloke etmez', () async {
    var now = DateTime(2026);
    final repository = InMemoryTrustedClientRepository([
      TrustedClientRecord(
        clientId: 'expired',
        clientName: 'Old parent',
        tokenHash: 'a' * 64,
        createdAtMs:
            now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        lastSeenAtMs:
            now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        expiresAtMs:
            now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      ),
    ]);

    final service = PairingTokenService(
      now: () => now,
      maxTrustedClients: 1,
      trustedClientRepository: repository,
    );
    final token = service.issueTrustedClientToken(
      clientName: 'New parent',
      deviceId: 'new',
    );

    expect(token.clientId, 'new');
    expect(service.pairedClientCount, 1);
  });

  test('kalıcı yazma hatası pairing başarısı gibi yutulmaz', () async {
    final service = PairingTokenService(
      trustedClientRepository: _FailingTrustedClientRepository(),
    );

    service.issueTrustedClientToken(
      clientName: 'Parent',
      deviceId: 'parent-1',
    );

    await expectLater(
      service.flushPersistence(),
      throwsA(isA<TrustedClientPersistenceException>()),
    );
    expect(service.lastPersistenceError, isNotNull);
  });
}

class _FailingTrustedClientRepository implements TrustedClientRepository {
  @override
  List<TrustedClientRecord> readAll() => const [];

  @override
  Future<void> replaceAll(List<TrustedClientRecord> clients) {
    return Future<void>.error(StateError('disk unavailable'));
  }
}
