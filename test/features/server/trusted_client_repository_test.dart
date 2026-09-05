import 'dart:async';
import 'dart:convert';

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
    expect(first.trustedClients.single.clientName, 'Parent');

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
    await first.revokeClientPersisted(token.clientId);
    expect(first.trustedClients, isEmpty);

    final restarted = PairingTokenService(
      trustedClientRepository: SharedPreferencesTrustedClientRepository(
        preferences,
      ),
    );

    expect(restarted.validateTrustedClientToken(token.token), isNull);
    expect(restarted.pairedClientCount, 0);
  });

  test('a damaged saved record does not forget other remembered devices',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesTrustedClientRepository(preferences);
    final service = PairingTokenService(trustedClientRepository: repository);
    final first = await service.issueTrustedClientTokenPersisted(
      clientName: 'Anne',
      deviceId: 'parent-1',
    );
    final second = await service.issueTrustedClientTokenPersisted(
      clientName: 'Baba',
      deviceId: 'parent-2',
    );
    final records = repository.readAll().map((record) => record.toJson());
    await preferences.setString(
      repository.storageKey,
      jsonEncode({
        'version': 1,
        'clients': [
          records.first,
          {'clientId': 'broken'},
          records.last
        ],
      }),
    );

    final restarted = PairingTokenService(trustedClientRepository: repository);
    expect(restarted.validateSessionToken(first.token), isTrue);
    expect(restarted.validateSessionToken(second.token), isTrue);
    expect(restarted.pairedClientCount, 2);
  });

  test('conflicting stored identities are rejected without forgetting others',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesTrustedClientRepository(preferences);
    final service = PairingTokenService(trustedClientRepository: repository);
    final first = await service.issueTrustedClientTokenPersisted(
      clientName: 'Anne',
      deviceId: 'parent-1',
    );
    final second = await service.issueTrustedClientTokenPersisted(
      clientName: 'Baba',
      deviceId: 'parent-2',
    );
    final records = repository.readAll();
    await preferences.setString(
      repository.storageKey,
      jsonEncode({
        'version': 1,
        'clients': [
          records.first.toJson(),
          records.first.copyWith(revokedAtMs: 1).toJson(),
          records.last.toJson(),
        ],
      }),
    );

    final restarted = PairingTokenService(trustedClientRepository: repository);
    expect(restarted.validateSessionToken(first.token), isFalse);
    expect(restarted.validateSessionToken(second.token), isTrue);
  });

  test('storage capacity keeps remembered devices before deleted history',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesTrustedClientRepository(
      preferences,
      maxStoredRecords: 2,
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final remembered = TrustedClientRecord(
      clientId: 'remembered',
      clientName: 'Anne',
      tokenHash: 'a' * 64,
      createdAtMs: nowMs,
      lastSeenAtMs: nowMs,
      expiresAtMs: nowMs + const Duration(days: 30).inMilliseconds,
    );
    final deleted = [
      for (var index = 0; index < 3; index++)
        TrustedClientRecord(
          clientId: 'deleted-$index',
          clientName: 'Old phone',
          tokenHash: 'b' * 64,
          createdAtMs: nowMs,
          lastSeenAtMs: nowMs + index + 1,
          expiresAtMs: remembered.expiresAtMs,
          revokedAtMs: nowMs,
        ),
    ];
    await repository.replaceAll([remembered, ...deleted]);

    expect(repository.readAll().map((record) => record.clientId),
        contains('remembered'));
    expect(repository.readAll(), hasLength(2));
  });

  test('a false SharedPreferences write result is a persistence failure',
      () async {
    final repository = SharedPreferencesTrustedClientRepository(
      _RejectedWritePreferences(),
    );
    await expectLater(repository.replaceAll([]), throwsStateError);
  });

  test('failed deletion stays denied and visible for retry until durably saved',
      () async {
    final repository = _ToggleTrustedClientRepository();
    final service = PairingTokenService(trustedClientRepository: repository);
    final token = await service.issueTrustedClientTokenPersisted(
      clientName: 'Anne',
      deviceId: 'parent-1',
    );
    final stream = service.issueStreamToken(clientId: token.clientId);
    repository.rejectWrites = true;

    await expectLater(service.revokeClientPersisted(token.clientId),
        throwsA(isA<TrustedClientPersistenceException>()));

    expect(service.validateSessionToken(token.token), isFalse);
    expect(service.validateStreamToken(stream.token), isNull);
    expect(service.pairedClientCount, 0);
    expect(service.trustedClients.single.revoked, isTrue);
    expect(service.pendingRevocationClientIds, {token.clientId});

    repository.rejectWrites = false;
    await service.revokeClientPersisted(token.clientId);
    expect(service.pendingRevocationClientIds, isEmpty);
    expect(service.trustedClients, isEmpty);
    final restarted = PairingTokenService(trustedClientRepository: repository);
    expect(restarted.validateSessionToken(token.token), isFalse);
  });

  test('room owner name survives reconnect renewal and server restart',
      () async {
    var now = DateTime(2026);
    final repository = InMemoryTrustedClientRepository();
    final service = PairingTokenService(
      now: () => now,
      trustedClientRepository: repository,
    );
    final token = await service.issueTrustedClientTokenPersisted(
      clientName: 'Generic phone',
      deviceId: 'parent-1',
    );
    final pairedAt = service.trustedClients.single.createdAtMs;
    await service.renameTrustedClientPersisted(token.clientId, '  Anne  ');
    now = now.add(const Duration(days: 54));
    final renewed = await service.renewTrustedClientTokenPersisted(token.token);
    expect(renewed, isNotNull);
    final restarted = PairingTokenService(
      now: () => now,
      trustedClientRepository: repository,
    );

    expect(restarted.validateSessionToken(token.token), isFalse);
    expect(restarted.validateSessionToken(renewed!.token), isTrue);
    expect(restarted.trustedClients.single.clientName, 'Anne');
    expect(restarted.trustedClients.single.createdAtMs, pairedAt);
    expect(restarted.trustedClients.single.lastSeenAtMs,
        now.millisecondsSinceEpoch);
  });

  test('failed owner rename restores durable name without reviving access',
      () async {
    final repository = _BlockingTrustedClientRepository();
    final service = PairingTokenService(trustedClientRepository: repository);
    final token = await service.issueTrustedClientTokenPersisted(
      clientName: 'Anne',
      deviceId: 'parent-1',
    );
    repository.blockNextWrite();
    final renamed =
        service.renameTrustedClientPersisted(token.clientId, 'Baba');
    await repository.blockedWriteStarted;
    service.revokeClient(token.clientId);
    repository.failBlockedWrite(StateError('disk unavailable'));

    await expectLater(
        renamed, throwsA(isA<TrustedClientPersistenceException>()));
    await service.flushPersistence();
    expect(service.recordForClient(token.clientId)?.clientName, 'Anne');
    expect(service.validateSessionToken(token.token), isFalse);
    expect(repository.records.single.clientName, 'Anne');
    expect(repository.records.single.revoked, isTrue);
  });

  test('remembered device changes notify without a screen restart', () async {
    final service = PairingTokenService();
    var changes = 0;
    final subscription = service.trustedClientsChanged.listen((_) => changes++);
    addTearDown(subscription.cancel);
    addTearDown(service.dispose);
    final token = await service.issueTrustedClientTokenPersisted(
      clientName: 'Phone',
      deviceId: 'parent-1',
    );
    await Future<void>.delayed(Duration.zero);
    expect(changes, greaterThan(0));
    final afterPairing = changes;
    await service.renameTrustedClientPersisted(token.clientId, 'Anne');
    await Future<void>.delayed(Duration.zero);
    expect(changes, greaterThan(afterPairing));
    final afterRename = changes;
    await service.revokeClientPersisted(token.clientId);
    await Future<void>.delayed(Duration.zero);
    expect(changes, greaterThan(afterRename));
  });

  test('tüm güvenilen cihazlar kalıcı olarak iptal edilebilir', () async {
    final repository = InMemoryTrustedClientRepository();
    final service = PairingTokenService(trustedClientRepository: repository);
    await service.issueTrustedClientTokenPersisted(
      clientName: 'Parent one',
      deviceId: 'parent-1',
    );
    await service.issueTrustedClientTokenPersisted(
      clientName: 'Parent two',
      deviceId: 'parent-2',
    );

    expect(service.trustedClients.map((client) => client.clientId),
        containsAll(['parent-1', 'parent-2']));

    await service.revokeAllPersisted();

    expect(service.trustedClients, isEmpty);
    expect(repository.readAll().every((client) => client.revoked), isTrue);
  });

  test(
      'failed remove-all does not bring already deleted phones back to the list',
      () async {
    final repository = _ToggleTrustedClientRepository();
    final service = PairingTokenService(trustedClientRepository: repository);
    final old = await service.issueTrustedClientTokenPersisted(
      clientName: 'Deleted phone',
      deviceId: 'old',
    );
    await service.revokeClientPersisted(old.clientId);
    final current = await service.issueTrustedClientTokenPersisted(
      clientName: 'Anne',
      deviceId: 'current',
    );
    repository.rejectWrites = true;

    await expectLater(service.revokeAllPersisted(),
        throwsA(isA<TrustedClientPersistenceException>()));

    expect(service.trustedClients.map((record) => record.clientId),
        [current.clientId]);
    expect(service.pendingRevocationClientIds, {current.clientId});
    expect(service.validateSessionToken(current.token), isFalse);
    expect(service.validateSessionToken(old.token), isFalse);
    repository.rejectWrites = false;
    await service.revokeAllPersisted();
    expect(service.trustedClients, isEmpty);
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

  test('durable removal denies access while a previous rename write is blocked',
      () async {
    final repository = _BlockingTrustedClientRepository();
    final service = PairingTokenService(trustedClientRepository: repository);
    final token = await service.issueTrustedClientTokenPersisted(
      clientName: 'Anne',
      deviceId: 'parent-1',
    );
    repository.blockNextWrite();
    final rename = service.renameTrustedClientPersisted(token.clientId, 'Baba');
    await repository.blockedWriteStarted;

    final removal = service.revokeClientPersisted(token.clientId);
    expect(service.validateSessionToken(token.token), isFalse);
    repository.failBlockedWrite(StateError('disk unavailable'));
    await expectLater(
        rename, throwsA(isA<TrustedClientPersistenceException>()));
    await removal;
    expect(repository.records.single.revoked, isTrue);
    expect(service.trustedClients, isEmpty);
  });
}

class _RejectedWritePreferences implements SharedPreferences {
  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
