import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/app/install_integrity_guard.dart';
import 'package:miucam/app/role_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('failed role write cannot report or cache a successful role switch',
      () async {
    final preferences = _Preferences({'app_role': 'server'})
      ..failKey = 'app_role';
    final roles = SharedPreferencesRoleRepository(preferences);
    await expectLater(roles.saveRole(AppRole.client), throwsStateError);
    expect(await roles.loadRole(), AppRole.server);
    expect(preferences.durable['app_role'], 'server');
  });

  test('a failed clear cannot resurrect a different legacy room role',
      () async {
    final preferences = _Preferences({'app_role': 'client', 'mode': 'server'})
      ..failKey = 'app_role';
    final roles = SharedPreferencesRoleRepository(preferences);
    await expectLater(roles.clearRole(), throwsStateError);
    expect(await roles.loadRole(), AppRole.client);
    expect(preferences.durable['app_role'], 'client');
    expect(preferences.durable.containsKey('mode'), isFalse);
    preferences.failKey = null;
    await roles.clearRole();
    expect(await roles.loadRole(), isNull);
  });

  test('legacy role migrates to a single authoritative record', () async {
    final preferences = _Preferences({'mode': 'server'});
    final roles = SharedPreferencesRoleRepository(preferences);
    expect(await roles.loadRole(), AppRole.server);
    await roles.saveRole(AppRole.client);
    expect(await roles.loadRole(), AppRole.client);
    await roles.clearRole();
    expect(await roles.loadRole(), isNull);
  });

  test('unsaved fresh-install preparation remains gated and can retry',
      () async {
    final preferences = _Preferences({})
      ..failKey = InstallIntegrityGuard.markerKey;
    var clears = 0;
    const guard = InstallIntegrityGuard();
    await expectLater(
      guard.prepare(preferences, clearSecureStorage: () async => clears++),
      throwsStateError,
    );
    expect(preferences.getBool(InstallIntegrityGuard.markerKey), isNull);
    preferences.failKey = null;
    await guard.prepare(preferences, clearSecureStorage: () async => clears++);
    expect(clears, 2);
    expect(preferences.durable[InstallIntegrityGuard.markerKey], isTrue);
  });
}

class _Preferences implements SharedPreferences {
  _Preferences(Map<String, Object> initial)
      : durable = Map.of(initial),
        cache = Map.of(initial);

  final Map<String, Object> durable;
  final Map<String, Object> cache;
  String? failKey;

  @override
  String? getString(String key) => cache[key] as String?;
  @override
  bool? getBool(String key) => cache[key] as bool?;
  @override
  Set<String> getKeys() => cache.keys.toSet();
  @override
  Future<bool> setString(String key, String value) => _write(key, value);
  @override
  Future<bool> setBool(String key, bool value) => _write(key, value);
  Future<bool> _write(String key, Object value) async {
    cache[key] = value;
    if (key == failKey) return false;
    durable[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    cache.remove(key);
    if (key == failKey) return false;
    durable.remove(key);
    return true;
  }

  @override
  Future<void> reload() async => cache
    ..clear()
    ..addAll(durable);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
