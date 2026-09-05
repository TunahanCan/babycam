import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';

void main() {
  test('en fazla 5 trusted client eşleşebilir, revoke slot açar', () {
    final service = PairingTokenService();

    for (var index = 0; index < 5; index++) {
      service.issueTrustedClientToken(
        clientName: 'Client $index',
        deviceId: 'client_$index',
      );
    }

    expect(service.pairedClientCount, 5);
    expect(
      () => service.issueTrustedClientToken(
        clientName: 'Client 6',
        deviceId: 'client_6',
      ),
      throwsA(isA<TrustedClientLimitException>()),
    );

    service.revokeClient('client_0');
    final token = service.issueTrustedClientToken(
      clientName: 'Client 6',
      deviceId: 'client_6',
    );

    expect(token.clientId, 'client_6');
    expect(service.pairedClientCount, 5);
  });

  test('same device re-pairs at capacity only with its remembered secret',
      () async {
    final service = PairingTokenService();
    final first = await service.issueTrustedClientTokenPersisted(
      clientName: 'Anne',
      deviceId: 'parent-1',
    );
    for (var index = 2; index <= 5; index++) {
      await service.issueTrustedClientTokenPersisted(
        clientName: 'Phone $index',
        deviceId: 'parent-$index',
      );
    }
    await expectLater(
      service.issueTrustedClientTokenPersisted(
        clientName: 'Duplicate ID',
        deviceId: first.clientId,
      ),
      throwsA(isA<TrustedClientLimitException>()),
    );
    expect(service.validateSessionToken(first.token), isTrue);

    final rePaired = await service.issueTrustedClientTokenPersisted(
      clientName: 'Default app name',
      deviceId: first.clientId,
      existingTrustedClientToken: first.token,
    );

    expect(rePaired.clientId, first.clientId);
    expect(service.pairedClientCount, 5);
    expect(service.validateSessionToken(first.token), isFalse);
    expect(service.validateSessionToken(rePaired.token), isTrue);
    expect(service.recordForClient(first.clientId)?.clientName, 'Anne');
  });

  test('an unproven ID collision cannot take over a remembered device', () {
    final service = PairingTokenService();
    final first = service.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'parent-1',
    );
    final second = service.issueTrustedClientToken(
      clientName: 'Another phone',
      deviceId: first.clientId,
      existingTrustedClientToken: 'incorrect-secret',
    );
    expect(second.clientId, isNot(first.clientId));
    expect(service.validateTrustedClientToken(first.token)?.clientId,
        first.clientId);
    expect(service.validateTrustedClientToken(second.token)?.clientId,
        second.clientId);
    expect(service.pairedClientCount, 2);
  });

  test('a different remembered device token cannot prove ownership', () {
    final service = PairingTokenService();
    final first = service.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'parent-1',
    );
    final second = service.issueTrustedClientToken(
      clientName: 'Baba',
      deviceId: 'parent-2',
    );
    final third = service.issueTrustedClientToken(
      clientName: 'Duplicate',
      deviceId: first.clientId,
      existingTrustedClientToken: second.token,
    );
    expect(third.clientId, isNot(first.clientId));
    expect(third.clientId, isNot(second.clientId));
    expect(service.validateSessionToken(first.token), isTrue);
    expect(service.validateSessionToken(second.token), isTrue);
  });

  test('an expired old ID cannot bypass the five-device capacity', () {
    var now = DateTime(2026);
    final service = PairingTokenService(now: () => now);
    final old = service.issueTrustedClientToken(
      clientName: 'Old phone',
      deviceId: 'old-phone',
    );
    now = now.add(const Duration(days: 61));
    for (var index = 0; index < 5; index++) {
      service.issueTrustedClientToken(
        clientName: 'New phone $index',
        deviceId: 'new-$index',
      );
    }

    expect(service.pairedClientCount, 5);
    expect(
      () => service.issueTrustedClientToken(
        clientName: 'Old phone again',
        deviceId: old.clientId,
        existingTrustedClientToken: old.token,
      ),
      throwsA(isA<TrustedClientLimitException>()),
    );
    expect(service.validateSessionToken(old.token), isFalse);
  });

  test('simultaneous durable pairing requests cannot allocate a sixth slot',
      () async {
    final service = PairingTokenService();
    final results = await Future.wait([
      for (var index = 0; index < 6; index++)
        service
            .issueTrustedClientTokenPersisted(
              clientName: 'Phone $index',
              deviceId: 'phone-$index',
            )
            .then<Object>((token) => token, onError: (Object error) => error),
    ]);

    expect(results.whereType<TrustedClientLimitException>(), hasLength(1));
    expect(service.pairedClientCount, 5);
  });
}
