import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/security/secure_random_token_generator.dart';
import 'package:miucam/features/client/pairing/client_identity_store.dart';
import 'package:miucam/features/client/pairing/pairing_session_store.dart';

void main() {
  test('client id secure storage icinde kalici uretilir', () async {
    final secure = _FakeSecureTokenStore();
    final store = ClientIdentityStore(
      secureTokens: secure,
      tokenGenerator: SecureRandomTokenGenerator(random: Random(1)),
    );

    final first = await store.clientId();
    final second = await store.clientId();

    expect(first, startsWith('client_'));
    expect(second, first);
    expect(secure.values['miucam_client_id'], first);
  });

  test('legacy client_local degeri yenilenir', () async {
    final secure = _FakeSecureTokenStore()
      ..values['miucam_client_id'] = 'client_local';
    final store = ClientIdentityStore(
      secureTokens: secure,
      tokenGenerator: SecureRandomTokenGenerator(random: Random(2)),
    );

    final id = await store.clientId();

    expect(id, startsWith('client_'));
    expect(id, isNot('client_local'));
    expect(secure.values['miucam_client_id'], id);
  });
}

class _FakeSecureTokenStore implements SecureTokenStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
