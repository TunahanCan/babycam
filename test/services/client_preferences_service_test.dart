import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/client_preferences_service.dart';
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
}
