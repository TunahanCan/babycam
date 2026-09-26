import 'dart:async';

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

  test('legacy locales migrate atomically including explicit system locale',
      () async {
    SharedPreferences.setMockInitialValues({
      'client.locale.language': 'ar',
      'client.locale.country': 'QA',
    });
    final preferences = await SharedPreferences.getInstance();
    final service = ClientPreferencesService(preferences);
    expect(service.locale, const Locale('ar', 'QA'));
    const locale = Locale.fromSubtags(
        languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW');
    await service.setLocale(locale);
    expect(ClientPreferencesService(preferences).locale, locale);
    await service.setLocale(null);
    expect(ClientPreferencesService(preferences).locale, isNull);
  });

  for (final throws in [false, true]) {
    test('failed preferences save restores the durable cache (throws=$throws)',
        () async {
      final preferences = _FailingPreferences()..throws = throws;
      final service = ClientPreferencesService(preferences);
      await expectLater(service.setKeepScreenAwake(false), throwsStateError);
      expect(service.keepScreenAwake, isTrue);
      await expectLater(
          service.setLocale(const Locale('ar', 'QA')), throwsStateError);
      expect(service.locale, const Locale('tr'));
      expect(preferences.reloads, 2);
    });
  }

  test('a delayed failing write cannot roll back a later successful save',
      () async {
    final preferences = _FailingPreferences()..release = Completer<void>();
    final service = ClientPreferencesService(preferences);
    final failure =
        expectLater(service.setKeepScreenAwake(false), throwsStateError);
    final second = service.setLocale(const Locale('en', 'US'));
    await Future<void>.delayed(Duration.zero);
    expect(preferences.writes, 1);
    preferences.release!.complete();
    await failure;
    await second;
    expect(service.keepScreenAwake, isTrue);
    expect(service.locale, const Locale('en', 'US'));
  });
}

class _FailingPreferences implements SharedPreferences {
  final saved = <String, Object>{'client.locale.language': 'tr'};
  late Map<String, Object> cache = Map.of(saved);
  bool throws = false;
  Completer<void>? release;
  int reloads = 0;
  int writes = 0;

  @override
  String? getString(String key) => cache[key] as String?;

  @override
  bool? getBool(String key) => cache[key] as bool?;

  @override
  Future<bool> setString(String key, String value) => _write(key, value);

  @override
  Future<bool> setBool(String key, bool value) => _write(key, value);

  Future<bool> _write(String key, Object value) async {
    cache[key] = value;
    writes++;
    if (release != null) {
      if (writes == 1) {
        await release!.future;
      } else {
        saved[key] = value;
        return true;
      }
    }
    if (throws) throw StateError('Disk unavailable');
    return false;
  }

  @override
  Future<void> reload() async {
    reloads++;
    cache = Map.of(saved);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
