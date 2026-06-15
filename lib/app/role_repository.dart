import 'package:shared_preferences/shared_preferences.dart';

import 'app_role.dart';

abstract class RoleRepository {
  Future<AppRole?> loadRole();
  Future<void> saveRole(AppRole role);
  Future<void> clearRole();
}

class SharedPreferencesRoleRepository implements RoleRepository {
  SharedPreferencesRoleRepository(this._preferences);
  static const storageKey = 'app_role';
  final SharedPreferences _preferences;

  @override
  Future<AppRole?> loadRole() async {
    final value = _preferences.getString(storageKey) ?? _preferences.getString('mode');
    return switch (value) {
      'server' => AppRole.server,
      'client' => AppRole.client,
      _ => null,
    };
  }

  @override
  Future<void> saveRole(AppRole role) async {
    await _preferences.setString(storageKey, role.name);
    await _preferences.setString('mode', role.name);
  }

  @override
  Future<void> clearRole() async {
    await _preferences.remove(storageKey);
    await _preferences.remove('mode');
  }
}
