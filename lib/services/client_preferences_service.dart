import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClientPreferencesService {
  ClientPreferencesService(this._preferences);

  static const _localeLanguageKey = 'client.locale.language';
  static const _localeCountryKey = 'client.locale.country';
  static const _keepScreenAwakeKey = 'client.keep_screen_awake';

  final SharedPreferences _preferences;

  Locale? get locale {
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

  Future<void> setLocale(Locale? locale) async {
    if (locale == null) {
      await _preferences.remove(_localeLanguageKey);
      await _preferences.remove(_localeCountryKey);
      return;
    }
    await _preferences.setString(_localeLanguageKey, locale.languageCode);
    final countryCode = locale.countryCode;
    if (countryCode == null || countryCode.isEmpty) {
      await _preferences.remove(_localeCountryKey);
    } else {
      await _preferences.setString(_localeCountryKey, countryCode);
    }
  }

  Future<void> setKeepScreenAwake(bool enabled) =>
      _preferences.setBool(_keepScreenAwakeKey, enabled);
}
