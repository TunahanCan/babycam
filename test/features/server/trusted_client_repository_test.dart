import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
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

  test('yenileme yazılamazsa eski token bellekte geçerli kalır', () async {
    final repository = _ToggleTrustedClientRepository();
    final service = PairingTokenService(
      trustedClientRepository: repository,
    );
    final original = await service.issueTrustedClientTokenPersisted(
      clientName: 'Parent',
      deviceId: 'parent-1',
    );
    final originalHash = service.hashToken(original.token);
    repository.rejectWrites = true;

    await expectLater(
      service.renewTrustedClientTokenPersisted(original.token),
      throwsA(isA<TrustedClientPersistenceException>()),
    );

    expect(
      service.validateTrustedClientToken(original.token)?.clientId,
      original.clientId,
    );
    expect(service.recordForClient(original.clientId)?.tokenHash, originalHash);
  });

  test('yenileme rollbacki eşzamanlı revoke işlemini geri alamaz', () async {
    final repository = _BlockingTrustedClientRepository();
    final service = PairingTokenService(
      trustedClientRepository: repository,
    );
    final original = await service.issueTrustedClientTokenPersisted(
      clientName: 'Parent',
      deviceId: 'parent-1',
    );
    final originalHash = service.hashToken(original.token);
    repository.blockNextWrite();

    final renewal = service.renewTrustedClientTokenPersisted(original.token);
    await repository.blockedWriteStarted;
    service.revokeSession(original.token);
    repository.failBlockedWrite(StateError('disk unavailable'));

    await expectLater(
      renewal,
      throwsA(isA<TrustedClientPersistenceException>()),
    );
    await service.flushPersistence();

    final record = service.recordForClient(original.clientId);
    expect(record?.tokenHash, originalHash);
    expect(record?.revoked, isTrue);
    expect(service.validateTrustedClientToken(original.token), isNull);
    expect(repository.records.single.tokenHash, originalHash);
    expect(repository.records.single.revoked, isTrue);
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

class _ToggleTrustedClientRepository implements TrustedClientRepository {
  bool rejectWrites = false;
  List<TrustedClientRecord> records = const [];

  @override
  List<TrustedClientRecord> readAll() => List.of(records);

  @override
  Future<void> replaceAll(List<TrustedClientRecord> clients) async {
    if (rejectWrites) throw StateError('disk unavailable');
    records = List.of(clients);
  }
}

class _BlockingTrustedClientRepository implements TrustedClientRepository {
  List<TrustedClientRecord> records = const [];
  Completer<void>? _writeStarted;
  Completer<void>? _writeGate;
  Object? _blockedError;

  Future<void> get blockedWriteStarted => _writeStarted!.future;

  void blockNextWrite() {
    _writeStarted = Completer<void>();
    _writeGate = Completer<void>();
    _blockedError = null;
  }

  void failBlockedWrite(Object error) {
    _blockedError = error;
    _writeGate!.complete();
  }

  @override
  List<TrustedClientRecord> readAll() => List.of(records);

  @override
  Future<void> replaceAll(List<TrustedClientRecord> clients) async {
    final gate = _writeGate;
    if (gate != null) {
      if (!(_writeStarted?.isCompleted ?? true)) _writeStarted!.complete();
      await gate.future;
      final error = _blockedError;
      _writeStarted = null;
      _writeGate = null;
      _blockedError = null;
      if (error != null) throw error;
    }
    records = List.of(clients);
  }
}
