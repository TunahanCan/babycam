import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/l10n/src/app_ui_text_catalog.dart';

void main() {
  test('Chinese locale is supported and loaded', () async {
    const delegate = AppStrings.delegate;

    expect(AppStrings.supportedLocales, contains(const Locale('zh')));
    expect(delegate.isSupported(const Locale('zh')), isTrue);

    final strings = await delegate.load(const Locale('zh'));

    expect(strings.isChinese, isTrue);
    expect(strings.notificationTitle, 'MimiCam 提醒');
    expect(strings.cameraNotFound, '未找到摄像头。');
  });

  test('Hindi, Spanish, French, German and Arabic locales are supported',
      () async {
    const delegate = AppStrings.delegate;

    for (final locale in [
      const Locale('hi'),
      const Locale('es'),
      const Locale('fr'),
      const Locale('de'),
      const Locale('ar', 'SA'),
      const Locale('ar', 'QA'),
    ]) {
      expect(AppStrings.supportedLocales, contains(locale));
      expect(delegate.isSupported(locale), isTrue);
    }

    final hindi = await delegate.load(const Locale('hi'));
    final spanish = await delegate.load(const Locale('es'));
    final french = await delegate.load(const Locale('fr'));
    final german = await delegate.load(const Locale('de'));
    final arabicSaudi = await delegate.load(const Locale('ar', 'SA'));
    final arabicQatar = await delegate.load(const Locale('ar', 'QA'));

    expect(hindi.isHindi, isTrue);
    expect(hindi.notificationTitle, 'MimiCam अलर्ट');
    expect(spanish.isSpanish, isTrue);
    expect(spanish.cameraNotFound, 'No se encontró la cámara.');
    expect(french.isFrench, isTrue);
    expect(french.reset, 'Réinitialiser');
    expect(german.isGerman, isTrue);
    expect(german.notificationTitle, 'MimiCam Warnung');
    expect(arabicSaudi.isArabic, isTrue);
    expect(arabicSaudi.notificationTitle, 'تنبيه MimiCam');
    expect(arabicSaudi.locale.countryCode, 'SA');
    expect(arabicQatar.isArabic, isTrue);
    expect(arabicQatar.locale.countryCode, 'QA');
  });

  test('unsupported locale falls back to English', () async {
    const delegate = AppStrings.delegate;

    final strings = await delegate.load(const Locale('ru'));

    expect(strings.locale, const Locale('en'));
    expect(strings.reset, 'Reset');
  });

  test('UI labels follow locale and unsupported locales use English', () async {
    const delegate = AppStrings.delegate;

    expect(AppStrings(const Locale('es')).ui('scanQr'), 'Escanear QR');
    expect(AppStrings(const Locale('fr')).ui('navSettings'), 'Réglages');
    expect(AppStrings(const Locale('de')).ui('scanQr'), 'QR scannen');
    expect(AppStrings(const Locale('ar', 'SA')).ui('scanQr'), 'مسح QR');
    expect(AppStrings(const Locale('hi')).ui('parentDeviceTitle'),
        'माता-पिता का डिवाइस');

    final fallback = await delegate.load(const Locale('ru'));

    expect(fallback.ui('scanQr'), 'Scan QR');
    expect(fallback.ui('roleSelectionTitle'), 'What will this device be?');
  });

  test('UI catalog tüm desteklenen diller için değer taşır', () {
    const baseLanguageCodes = {'tr', 'en', 'zh', 'hi', 'es', 'fr'};

    for (final entry in appUiTextCatalog.entries) {
      expect(
        entry.value.keys.toSet(),
        containsAll(baseLanguageCodes),
        reason: '${entry.key} eksik locale içeriyor',
      );
    }
  });

  test('rapor dillerinde UI metinleri İngilizce fallback kullanmaz', () {
    const allowedSameAsEnglish = {
      'clientRoleTitle',
      'navQrIp',
      'temperatureHumidity',
      'turkishShort',
    };

    for (final entry in appUiTextCatalog.entries) {
      for (final languageCode in ['tr', 'zh', 'es', 'fr', 'de', 'ar']) {
        if (allowedSameAsEnglish.contains(entry.key)) continue;
        final localized = AppStrings(Locale(languageCode)).ui(entry.key);
        expect(
          localized,
          isNot(entry.value['en']),
          reason: '${entry.key} $languageCode İngilizce fallback gibi duruyor',
        );
      }
    }
  });

  test('Almanca ve Arapça ek katalogda eksik anahtar yoktur', () {
    for (final key in appUiTextCatalog.keys) {
      expect(AppStrings(const Locale('de')).ui(key),
          isNot(startsWith('Nicht übersetzt:')));
      expect(AppStrings(const Locale('ar', 'SA')).ui(key),
          isNot(startsWith('غير مترجم:')));
      expect(AppStrings(const Locale('ar', 'QA')).ui(key),
          isNot(startsWith('غير مترجم:')));
    }
  });

  test('rapor dillerinde bildirim helper metinleri yerelleştirilir', () {
    final samples = {
      'tr': AppStrings(const Locale('tr')).parentEpisodeCryAlert(
        seconds: 9,
        networkTier: 'zayıf',
      ),
      'zh': AppStrings(const Locale('zh')).parentEpisodeCryAlert(
        seconds: 9,
        networkTier: '弱',
      ),
      'es': AppStrings(const Locale('es')).parentEpisodeCryAlert(
        seconds: 9,
        networkTier: 'débil',
      ),
      'fr': AppStrings(const Locale('fr')).parentEpisodeCryAlert(
        seconds: 9,
        networkTier: 'faible',
      ),
      'de': AppStrings(const Locale('de')).parentEpisodeCryAlert(
        seconds: 9,
        networkTier: 'schwach',
      ),
      'ar': AppStrings(const Locale('ar', 'SA')).parentEpisodeCryAlert(
        seconds: 9,
        networkTier: 'ضعيف',
      ),
    };

    expect(samples['tr'], contains('ağlama'));
    expect(samples['zh'], contains('哭声'));
    expect(samples['es'], contains('llanto'));
    expect(samples['fr'], contains('pleurs'));
    expect(samples['de'], contains('Weinsignal'));
    expect(samples['ar'], contains('البكاء'));
    for (final entry in samples.entries) {
      expect(entry.value, isNot(contains('Crying signal')));
      expect(entry.value, isNot(contains('Stream is in')));
    }
  });

  test('uiFormat placeholder değerlerini locale metnine uygular', () {
    final spanish = AppStrings(const Locale('es'));

    expect(
      spanish.uiFormat('pairedMessage', {'name': 'Bebek Odası'}),
      contains('Bebek Odası'),
    );
    expect(
      spanish.uiFormat('pairingFailed', {'error': 'timeout'}),
      contains('timeout'),
    );
  });

  test('parent alert messages include evidence and suggested action', () {
    final strings = AppStrings(const Locale('en'));

    final message = strings.parentCryAlert(
      confidencePercent: 82,
      ambientDeltaDb: 14.5,
      cryBandPercent: 61,
      calibrated: true,
    );

    expect(message, contains('Cry likelihood is high'));
    expect(message, contains('14.5 dB above ambient'));
    expect(message, contains('hunger'));
    expect(message, contains('diaper'));
  });

  test('parent alert messages use deterministic variants', () {
    final strings = AppStrings(const Locale('en'));

    final first = strings.parentCryAlert(
      confidencePercent: 82,
      ambientDeltaDb: 14.5,
      cryBandPercent: 61,
      calibrated: true,
    );
    final second = strings.parentCryAlert(
      confidencePercent: 83,
      ambientDeltaDb: 14.5,
      cryBandPercent: 61,
      calibrated: true,
    );

    expect(first, isNot(second));
    expect(first, contains('Cry likelihood'));
    expect(second, contains('Baby sounds likely'));
  });

  test('parent alert messages are localized for new languages', () {
    final hindi = AppStrings(const Locale('hi')).parentCryAlert(
      confidencePercent: 82,
      ambientDeltaDb: 14.5,
      cryBandPercent: 61,
      calibrated: true,
    );
    final spanish = AppStrings(const Locale('es')).parentMotionAlert(
      scorePercent: 72,
      activeAreaPercent: 18,
      meanDiff: 12.4,
    );
    final french = AppStrings(const Locale('fr')).parentLoudSoundAlert(
      dbfs: -18.2,
      ambientDeltaDb: 21.7,
    );

    expect(hindi, contains('रोने की संभावना'));
    expect(hindi, contains('डायपर'));
    expect(spanish, contains('Movimiento detectado'));
    expect(spanish, contains('posición del bebé'));
    expect(french, contains('Son fort soudain détecté'));
    expect(french, contains('source de bruit inattendue'));
  });

  test('episode alert helper messages are localized', () {
    final english = AppStrings(const Locale('en')).parentEpisodeHighCryAlert(
      seconds: 18,
      motionAgo: '4 sec ago',
      networkTier: 'Weak',
    );
    final spanish = AppStrings(const Locale('es')).parentEpisodeShortSoundAlert(
      seconds: 3,
    );
    final hindi = AppStrings(const Locale('hi')).parentEpisodeCryAlert(
      seconds: 7,
      networkTier: 'कमज़ोर',
    );

    expect(english, contains('crying'));
    expect(english, contains('Weak'));
    expect(spanish, contains('sonido'));
    expect(hindi, contains('रोने'));
  });
}
