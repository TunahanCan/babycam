import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/async/serialized_async_executor.dart';

class ClientPreferencesService {
  ClientPreferencesService(this._preferences);

  static const _localeLanguageKey = 'client.locale.language';
  static const _localeCountryKey = 'client.locale.country';
  static const _localeKey = 'client.locale';
  static const _keepScreenAwakeKey = 'client.keep_screen_awake';

  final SharedPreferences _preferences;
  final _writes = SerializedAsyncExecutor();

  Locale? get locale {
    final saved = _preferences.getString(_localeKey);
    if (saved != null) {
      // A single value makes language/region/script changes atomic. Empty
      // explicitly selects the system locale over any legacy preferences.
      if (saved.isEmpty) return null;
      try {
        final value = jsonDecode(saved) as Map<String, dynamic>;
        return Locale.fromSubtags(
          languageCode: value['language'] as String,
          scriptCode: value['script'] as String?,
          countryCode: value['country'] as String?,
        );
      } catch (_) {
        // Older installs still have separate language and region keys.
      }
    }
    final languageCode = _preferences.getString(_localeLanguageKey);
    if (languageCode == null || languageCode.isEmpty) return null;
    final countryCode = _preferences.getString(_localeCountryKey);
    // English used to be stored without a region. The active English pack is
    // now explicitly American English, so legacy installs should resolve to
    // the same canonical locale instead of showing an unselected duplicate.
    if (languageCode == 'en' && (countryCode == null || countryCode.isEmpty)) {
      return const Locale('en', 'US');
    }
    return Locale.fromSubtags(
      languageCode: languageCode,
      countryCode:
          countryCode == null || countryCode.isEmpty ? null : countryCode,
    );
  }

  bool get keepScreenAwake => _preferences.getBool(_keepScreenAwakeKey) ?? true;

  Future<void> setLocale(Locale? locale) => _write(() => _preferences.setString(
        _localeKey,
        locale == null
            ? ''
            : jsonEncode({
                'language': locale.languageCode,
                'script': locale.scriptCode,
                'country': locale.countryCode,
              }),
      ));

  Future<void> setKeepScreenAwake(bool enabled) =>
      _write(() => _preferences.setBool(_keepScreenAwakeKey, enabled));

  Future<void> _write(Future<bool> Function() operation) =>
      _writes.run(() async {
        try {
          if (!await operation()) {
            throw StateError('Client preferences could not be saved.');
          }
        } catch (_) {
          // SharedPreferences updates its local cache before disk confirms a
          // write. Restore durable values before reporting a failed save.
          try {
            await _preferences.reload();
          } catch (_) {}
          rethrow;
        }
      });
}
