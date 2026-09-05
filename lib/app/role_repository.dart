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
    final value =
        _preferences.getString(storageKey) ?? _preferences.getString('mode');
    return switch (value) {
      'server' => AppRole.server,
      'client' => AppRole.client,
      _ => null,
    };
  }

  @override
  Future<void> saveRole(AppRole role) async {
    // A single canonical write avoids a half-saved role when the legacy
    // compatibility write fails. Old installations still load through mode.
    await _requireSaved(_preferences.setString(storageKey, role.name));
  }

  @override
  Future<void> clearRole() async {
    // Retire the fallback first so a failed canonical clear keeps the current
    // role, instead of resurrecting an older role at the next launch.
    await _requireSaved(_preferences.remove('mode'));
    await _requireSaved(_preferences.remove(storageKey));
  }

  Future<void> _requireSaved(Future<bool> operation) async {
    try {
      if (!await operation) {
        throw StateError('The application role was not saved.');
      }
    } catch (_) {
      // SharedPreferences updates its in-memory cache before the device write.
      try {
        await _preferences.reload();
      } catch (_) {}
      rethrow;
    }
  }
}
