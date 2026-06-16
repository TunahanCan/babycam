import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/l10n/app_strings.dart';

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

  test('Hindi, Spanish and French locales are supported and loaded', () async {
    const delegate = AppStrings.delegate;

    for (final locale in [
      const Locale('hi'),
      const Locale('es'),
      const Locale('fr'),
    ]) {
      expect(AppStrings.supportedLocales, contains(locale));
      expect(delegate.isSupported(locale), isTrue);
    }

    final hindi = await delegate.load(const Locale('hi'));
    final spanish = await delegate.load(const Locale('es'));
    final french = await delegate.load(const Locale('fr'));

    expect(hindi.isHindi, isTrue);
    expect(hindi.notificationTitle, 'MimiCam अलर्ट');
    expect(spanish.isSpanish, isTrue);
    expect(spanish.cameraNotFound, 'No se encontró la cámara.');
    expect(french.isFrench, isTrue);
    expect(french.reset, 'Réinitialiser');
  });

  test('unsupported locale falls back to English', () async {
    const delegate = AppStrings.delegate;

    final strings = await delegate.load(const Locale('de'));

    expect(strings.locale, const Locale('en'));
    expect(strings.reset, 'Reset');
  });

  test('UI labels follow locale and unsupported locales use English', () async {
    const delegate = AppStrings.delegate;

    expect(AppStrings(const Locale('es')).ui('scanQr'), 'Escanear QR');
    expect(AppStrings(const Locale('fr')).ui('navSettings'), 'Réglages');
    expect(AppStrings(const Locale('hi')).ui('parentDeviceTitle'),
        'माता-पिता का डिवाइस');

    final fallback = await delegate.load(const Locale('de'));

    expect(fallback.ui('scanQr'), 'Scan QR');
    expect(fallback.ui('roleSelectionTitle'), 'What will this device be?');
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
}
