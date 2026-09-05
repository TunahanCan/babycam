import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/pairing/pairing_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
      'remembered room lookup preserves selected child and never borrows its token',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureTokenStore();
    final store = PairingSessionStore(preferences, secureTokens: secure);
    final a = _session('token-a', serverId: 'room-a');
    final b = _session('token-b', serverId: 'room-b');
    await store.save(a);
    await store.save(b);
    final remembered = await store.loadForPayload(a.payload);
    expect(remembered?.sessionToken, 'token-a');
    expect((await store.loadSelected())?.deviceId, 'room-b');
    secure.values.remove('pairing_child_token.room-a');
    expect(await store.loadForPayload(a.payload), isNull);
    expect(
        await store
            .loadForPayload(_session('unknown', serverId: 'unknown').payload),
        isNull);
    expect((await store.loadSelected())?.sessionToken, 'token-b');
  });

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
    final children = await store.loadChildren();
    expect(children, hasLength(1));
    expect(children.single.selected, isTrue);
  });

  test('coklu child profilleri tokenlari secure storage icinde saklar',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureTokenStore();
    final store = PairingSessionStore(preferences, secureTokens: secure);

    await store.save(_session('token-a', serverId: 'server-a'));
    await store.saveChild(_session('token-b', serverId: 'server-b'));

    final children = await store.loadChildren();
    final selected = await store.loadSelected();

    expect(children.map((child) => child.id),
        containsAll(['server-a', 'server-b']));
    expect(selected?.payload.deviceId, 'server-b');
    expect(selected?.sessionToken, 'token-b');
    expect(secure.values['pairing_child_token.server-a'], 'token-a');
    expect(secure.values['pairing_child_token.server-b'], 'token-b');

    await store.selectChild('server-a');
    final reselected = await store.loadSelected();

    expect(reselected?.payload.deviceId, 'server-a');
    expect(reselected?.sessionToken, 'token-a');
  });

  test('child profile sayisi dort ile sinirlanir', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = PairingSessionStore(
      preferences,
      secureTokens: _FakeSecureTokenStore(),
    );

    for (var index = 0; index < 4; index++) {
      await store.saveChild(
        _session('token-$index', serverId: 'server-$index'),
        selected: index == 0,
      );
    }

    expect(
      () => store.saveChild(_session('token-4', serverId: 'server-4')),
      throwsA(isA<ChildProfileLimitException>()),
    );
    await expectLater(
      store.ensureCanSavePayload(_payload(deviceId: 'server-4')),
      throwsA(isA<ChildProfileLimitException>()),
    );
    await store.ensureCanSavePayload(_payload(deviceId: 'server-0'));
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

PairingSession _session(String token, {String serverId = 'server'}) =>
    PairingSession(
      payload: _payload(deviceId: serverId),
      sessionToken: token,
      clientId: 'client-1',
      trustedClientTokenExpiresAtMs: 12345,
      pairedAtMs: 67890,
    );

PairingPayload _payload({String deviceId = 'server'}) => PairingPayload(
      schemaVersion: MiuCamProtocolV2.schemaVersion,
      host: '127.0.0.1',
      port: 8080,
      deviceId: deviceId,
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
