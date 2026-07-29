import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/client_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('client UI preferences persist locale and live-watch wakelock',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final service = ClientPreferencesService(preferences);

    expect(service.locale, isNull);
    expect(service.keepScreenAwake, isTrue);

    await service.setLocale(const Locale('ar', 'QA'));
    await service.setKeepScreenAwake(false);

    final restored = ClientPreferencesService(preferences);
    expect(restored.locale, const Locale('ar', 'QA'));
    expect(restored.keepScreenAwake, isFalse);

    await restored.setLocale(null);
    expect(restored.locale, isNull);
  });

  test('American English round-trips and legacy English is normalized',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final service = ClientPreferencesService(preferences);

    await service.setLocale(const Locale('en', 'US'));
    expect(service.locale, const Locale('en', 'US'));

    await preferences.setString('client.locale.language', 'en');
    await preferences.remove('client.locale.country');
    expect(service.locale, const Locale('en', 'US'));
  });
}
