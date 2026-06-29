import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/pairing/pairing_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('session token secure storage icinde tutulur', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureTokenStore();
    final store = PairingSessionStore(preferences, secureTokens: secure);

    await store.save(_session('secure-token'));

    final raw = preferences.getString('pairing_session');
    expect(raw, isNotNull);
    expect(jsonDecode(raw!) as Map, isNot(contains('token')));
    expect(secure.values['pairing_session_token'], 'secure-token');

    final loaded = await store.load();

    expect(loaded?.sessionToken, 'secure-token');
    expect(loaded?.payload.deviceName, 'Bebek Odası');
  });

  test('legacy SharedPreferences token secure storagea migrate edilir',
      () async {
    final legacy = {
      'payload': _payload().toJson(),
      'token': 'legacy-token',
      'clientId': 'client-legacy',
      'trustedClientTokenExpiresAtMs': 12345,
      'pairedAtMs': 67890,
    };
    SharedPreferences.setMockInitialValues({
      'pairing_session': jsonEncode(legacy),
    });
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureTokenStore();
    final store = PairingSessionStore(preferences, secureTokens: secure);

    final loaded = await store.load();

    expect(loaded?.sessionToken, 'legacy-token');
    expect(loaded?.clientId, 'client-legacy');
    expect(secure.values['pairing_session_token'], 'legacy-token');
    final migrated = jsonDecode(preferences.getString('pairing_session')!)
        as Map<String, Object?>;
    expect(migrated.containsKey('token'), isFalse);
  });

  test('bozuk session kaydi crash yerine temizlenir', () async {
    SharedPreferences.setMockInitialValues({
      'pairing_session': '{not valid json',
    });
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureTokenStore()
      ..values['pairing_session_token'] = 'stale-token';
    final store = PairingSessionStore(preferences, secureTokens: secure);

    final loaded = await store.load();

    expect(loaded, isNull);
    expect(preferences.getString('pairing_session'), isNull);
    expect(secure.values.containsKey('pairing_session_token'), isFalse);
  });
}

PairingSession _session(String token) => PairingSession(
      payload: _payload(),
      sessionToken: token,
      clientId: 'client-1',
      trustedClientTokenExpiresAtMs: 12345,
      pairedAtMs: 67890,
    );

PairingPayload _payload() => PairingPayload(
      schemaVersion: MimiCamProtocolV2.schemaVersion,
      host: '127.0.0.1',
      port: 8080,
      deviceId: 'server',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {'transport': 'http_ws'},
    );

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
