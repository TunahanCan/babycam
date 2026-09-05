import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/l10n/src/app_ui_text_catalog.dart';

void main() {
  test('American English is the canonical English locale', () async {
    const delegate = AppStrings.delegate;
    const locale = Locale('en', 'US');

    expect(AppStrings.supportedLocales, contains(locale));
    expect(delegate.isSupported(locale), isTrue);

    final strings = await delegate.load(locale);

    expect(strings.locale, locale);
    expect(strings.notificationTitle, 'MiuCam · Nursery');
    expect(
      strings.alertNotificationTitle(
        type: 'cryDetected',
        messageKey: 'parentCryAlert',
      ),
      'Your baby may be crying',
    );

    final britishEnglish = await delegate.load(const Locale('en', 'GB'));
    expect(britishEnglish.locale, locale);
  });

  test('Chinese locale is supported and loaded', () async {
    const delegate = AppStrings.delegate;

    expect(AppStrings.supportedLocales, contains(const Locale('zh')));
    expect(delegate.isSupported(const Locale('zh')), isTrue);

    final strings = await delegate.load(const Locale('zh'));

    expect(strings.isChinese, isTrue);
    expect(strings.notificationTitle, 'MiuCam · 宝宝房');
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
    expect(hindi.notificationTitle, 'MiuCam · बच्चे का कमरा');
    expect(spanish.isSpanish, isTrue);
    expect(spanish.cameraNotFound, 'No se encontró la cámara.');
    expect(french.isFrench, isTrue);
    expect(french.reset, 'Réinitialiser');
    expect(german.isGerman, isTrue);
    expect(german.notificationTitle, 'MiuCam · Babyzimmer');
    expect(arabicSaudi.isArabic, isTrue);
    expect(arabicSaudi.notificationTitle, 'MiuCam · غرفة الطفل');
    expect(arabicSaudi.locale.countryCode, 'SA');
    expect(arabicQatar.isArabic, isTrue);
    expect(arabicQatar.locale.countryCode, 'QA');
  });

  test('unsupported locale falls back to English', () async {
    const delegate = AppStrings.delegate;

    final strings = await delegate.load(const Locale('ru'));

    expect(strings.locale, AppStrings.fallbackLocale);
    expect(strings.reset, 'Reset');
  });

  test('UI labels follow locale and unsupported locales use English', () async {
    const delegate = AppStrings.delegate;

    expect(AppStrings(const Locale('es')).ui('scanQr'), 'Escanear QR');
    expect(AppStrings(const Locale('fr')).ui('navSettings'), 'Réglages');
    expect(AppStrings(const Locale('de')).ui('scanQr'), 'QR scannen');
    expect(AppStrings(const Locale('ar', 'SA')).ui('scanQr'), 'مسح QR');
    expect(
      AppStrings(const Locale('hi')).ui('parentDeviceTitle'),
      'अपने पास रखें',
    );

    final fallback = await delegate.load(const Locale('ru'));

    expect(fallback.ui('scanQr'), 'Scan QR');
    expect(fallback.ui('roleSelectionTitle'), 'How will you use MiuCam?');
  });

  test('server service copy is user-facing in every app language', () {
    const expectedAlertConnection = {
      'tr': 'Uyarı bağlantısı',
      'en': 'Alert connection',
      'zh': '提醒连接',
      'hi': 'चेतावनी कनेक्शन',
      'es': 'Conexión de alertas',
      'fr': 'Connexion des alertes',
      'de': 'Warnverbindung',
      'ar': 'اتصال التنبيهات',
    };
    const expectedBackgroundTitle = {
      'tr': 'Arka planda çalışma',
      'en': 'Background operation',
      'zh': '后台运行',
      'hi': 'बैकग्राउंड में संचालन',
      'es': 'Funcionamiento en segundo plano',
      'fr': 'Fonctionnement en arrière-plan',
      'de': 'Hintergrundbetrieb',
      'ar': 'التشغيل في الخلفية',
    };
    const locales = [
      Locale('tr'),
      Locale('en', 'US'),
      Locale('zh'),
      Locale('hi'),
      Locale('es'),
      Locale('fr'),
      Locale('de'),
      Locale('ar', 'SA'),
    ];
    const technicalTerms = [
      'WebSocket',
      'foreground service',
      'Vordergrunddienst',
      '前台服务',
      'फ़ोरग्राउंड सेवा',
      'servicio en primer plano',
      'service Android au premier plan',
      'خدمة Android الأمامية',
      'runtime contract',
      'çalışma sözleşmesi',
      'Laufzeitvertrag',
      'عقد التشغيل',
    ];

    for (final locale in locales) {
      final strings = AppStrings(locale);
      final languageCode = locale.languageCode;
      expect(
        strings.ui('alertConnection'),
        expectedAlertConnection[languageCode],
      );
      expect(
        strings.ui('platformRuntimeContractTitle'),
        expectedBackgroundTitle[languageCode],
      );

      final serviceCopy = [
        strings.ui('serviceStatusSubtitle'),
        strings.uiFormat('eventClientsCount', {'count': 2}),
        strings.ui('clientCount'),
        strings.ui('androidServiceActiveContract'),
        strings.ui('androidServiceInactiveContract'),
        strings.ui('sentToClientDevice'),
      ].join(' ');
      for (final term in technicalTerms) {
        expect(
          serviceCopy,
          isNot(contains(term)),
          reason: '${locale.toLanguageTag()} still exposes "$term"',
        );
      }
      expect(
        strings.ui('sentToClientDevice').toLowerCase(),
        isNot(contains('client')),
      );
    }
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
      'serverRoleTitle',
      'navQrIp',
      'temperatureHumidity',
      'turkishShort',
    };

    for (final entry in appUiTextCatalog.entries) {
      for (final languageCode in ['tr', 'zh', 'hi', 'es', 'fr', 'de', 'ar']) {
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

  test('all localized UI templates preserve the same placeholders', () {
    const locales = [
      Locale('tr'),
      Locale('en', 'US'),
      Locale('zh'),
      Locale('hi'),
      Locale('es'),
      Locale('fr'),
      Locale('de'),
      Locale('ar', 'SA'),
      Locale('ar', 'QA'),
    ];

    final mismatches = <String>[];
    for (final entry in appUiTextCatalog.entries) {
      final expected = _placeholderNames(entry.value['en'] ?? '');
      for (final locale in locales) {
        final actual = _placeholderNames(AppStrings(locale).ui(entry.key));
        if (actual.join('\u0000') != expected.join('\u0000')) {
          mismatches.add(
            '${entry.key} ${locale.toLanguageTag()}: '
            'expected $expected, actual $actual',
          );
        }
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
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

    expect(samples['tr'], contains('Ağlama'));
    expect(samples['zh'], contains('哭声'));
    expect(samples['es'], contains('llanto'));
    expect(samples['fr'], contains('pleurs'));
    expect(samples['de'], contains('Weinähnlicher'));
    expect(samples['ar'], contains('البكاء'));
    for (final entry in samples.entries) {
      expect(entry.value, isNot(contains('Crying signal')));
      expect(entry.value, isNot(contains('Stream is in')));
    }
  });

  test('Almanca ve Arapça bildirim şablonları İngilizceye düşmez', () {
    final german = AppStrings(const Locale('de'));
    final arabic = AppStrings(const Locale('ar', 'SA'));
    final samples = [
      german.alertWebSocketDisconnected,
      german.serverAlertLog('x'),
      german.audioAlert('Ton erkannt', 82, 'Bitte prüfen.'),
      german.parentCryAlert(
        confidencePercent: 82,
        ambientDeltaDb: 14.5,
        cryBandPercent: 61,
        calibrated: true,
      ),
      arabic.alertWebSocketDisconnected,
      arabic.serverAlertLog('x'),
      arabic.audioAlert('تم رصد صوت', 82, 'يرجى التحقق.'),
      arabic.parentCryAlert(
        confidencePercent: 82,
        ambientDeltaDb: 14.5,
        cryBandPercent: 61,
        calibrated: true,
      ),
    ];

    for (final message in samples) {
      expect(message, isNot(contains('Alert WebSocket connection was lost')));
      expect(message, isNot(contains('Server alert')));
      expect(message, isNot(contains('Confidence')));
      expect(message, isNot(contains('room-calibrated')));
      expect(message, isNot(contains('..')));
    }
  });

  test('desteklenen dillerde durum ve analiz metinleri fallback yapmaz', () {
    final samples = {
      'tr': AppStrings(const Locale('tr')).audioSummary(
        dbfs: -22.4,
        ambientDbfs: -37.1,
        f0: '440 Hz',
        centroidHz: 2100,
        bandwidthHz: 1200,
        zcr: 0.14,
        entropy: 0.62,
        cryPercent: 71,
        moanPercent: 12,
      ),
      'zh': AppStrings(const Locale('zh')).cryLikeReason(', 基频 440 Hz', 2100),
      'hi': AppStrings(const Locale('hi')).moanLikeReason(
        ', मूल आवृत्ति 220 Hz',
        900,
      ),
      'es': AppStrings(const Locale('es')).waitingForServer,
      'fr': AppStrings(const Locale('fr')).serverActiveStatus('http://x'),
      'de': AppStrings(const Locale('de')).clientActiveStatus,
      'ar': AppStrings(const Locale('ar', 'QA')).serverAddressLabel,
    };

    for (final sample in samples.values) {
      expect(sample, isNot(contains('unknown')));
      expect(sample, isNot(contains('No sound')));
      expect(sample, isNot(contains('Waiting for server')));
      expect(sample, isNot(contains('Server is active')));
      expect(sample, isNot(contains('Client mode is active')));
      expect(sample, isNot(contains('Cry-like vocal sound')));
      expect(sample, isNot(contains('Moan-like low-frequency')));
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

  test('yayın kalan süresi seçili locale göre kısaltılır', () {
    final english = AppStrings(const Locale('en'));
    final turkish = AppStrings(const Locale('tr'));

    expect(
      english.uiFormat(
        'durationHoursMinutesShort',
        {'hours': 1, 'minutes': 25},
      ),
      '1 hr 25 min',
    );
    expect(
      turkish.uiFormat(
        'durationHoursMinutesShort',
        {'hours': 1, 'minutes': 25},
      ),
      '1 sa 25 dk',
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

    expect(message, contains('Baby may be crying'));
    expect(message, contains('14.5 dB above the room level'));
    expect(message, contains('feeding'));
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
    expect(first, contains('Baby may be crying'));
    expect(second, contains('A gentle room check'));
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

    expect(hindi, contains('बच्चा रो रहा'));
    expect(hindi, contains('डायपर'));
    expect(spanish, contains('cambio suave'));
    expect(spanish, contains('bebé esté cómodo'));
    expect(french, contains('Brève hausse sonore'));
    expect(french, contains('bébé va bien'));
  });

  test('episode alert helper messages are localized', () {
    final strings = AppStrings(AppStrings.fallbackLocale);
    final motionAgo = strings.parentMotionAgo(4000);
    final english = strings.parentEpisodeHighCryAlert(
      seconds: 18,
      motionAgo: motionAgo,
      networkTier: 'Weak',
    );
    final spanish = AppStrings(const Locale('es')).parentEpisodeShortSoundAlert(
      seconds: 3,
    );
    final hindi = AppStrings(const Locale('hi')).parentEpisodeCryAlert(
      seconds: 7,
      networkTier: 'कमज़ोर',
    );

    expect(english, contains('cry-like'));
    expect(english, contains('Weak'));
    expect(english, contains('The last camera movement was 4 sec ago.'));
    expect(english, isNot(contains('Last camera motion The last')));
    expect(spanish, contains('sonido'));
    expect(hindi, contains('बेचैनी'));
  });

  test('uyarı mesajları annenin dilinde doğal hitapla başlar', () {
    const expected = {
      'tr': 'Anne,',
      'en': 'Mom,',
      'zh': '妈妈，',
      'hi': 'माँ,',
      'es': 'Mamá,',
      'fr': 'Maman,',
      'de': 'Mama,',
      'ar': 'ماما،',
    };

    for (final entry in expected.entries) {
      final strings = AppStrings(Locale(entry.key));
      expect(
        strings.parentMotionAlert(
          scorePercent: 72,
          activeAreaPercent: 18,
          meanDiff: 12.4,
        ),
        startsWith(entry.value),
        reason: entry.key,
      );
      expect(
        strings.parentEpisodeCryAlert(seconds: 7, networkTier: 'Good'),
        startsWith(entry.value),
        reason: entry.key,
      );
    }
  });

  test('native notification copy is short, warm, and localized', () {
    const expected = <String, ({String title, String prefix})>{
      'tr': (title: 'Bebeğin ağlıyor olabilir', prefix: 'Anne,'),
      'en': (title: 'Your baby may be crying', prefix: 'Mom,'),
      'zh': (title: '宝宝可能在哭', prefix: '妈妈，'),
      'hi': (title: 'शायद बच्चा रो रहा है', prefix: 'माँ,'),
      'es': (title: 'Puede que tu bebé esté llorando', prefix: 'Mamá,'),
      'fr': (title: 'Bébé pleure peut-être', prefix: 'Maman,'),
      'de': (title: 'Dein Baby weint vielleicht', prefix: 'Mama,'),
      'ar': (title: 'قد يكون طفلك يبكي', prefix: 'ماما،'),
    };

    for (final entry in expected.entries) {
      final strings = AppStrings(Locale(entry.key));
      final title = strings.alertNotificationTitle(
        type: 'cryDetected',
        messageKey: 'parentCryAlert',
      );
      final body = strings.alertNotificationBody(
        type: 'cryDetected',
        messageKey: 'parentCryAlert',
      );

      expect(title, entry.value.title, reason: entry.key);
      expect(body, startsWith(entry.value.prefix), reason: entry.key);
      expect(body!.length, lessThan(180), reason: entry.key);
      expect(body, isNot(contains('dBFS')), reason: entry.key);
      expect(body, isNot(contains('{')), reason: entry.key);

      final systemBody = strings.alertNotificationBody(
        type: 'systemWarning',
        messageKey: 'legacyAlert',
      );
      expect(systemBody, startsWith(entry.value.prefix), reason: entry.key);
      expect(systemBody!.length, lessThan(180), reason: entry.key);
    }
  });

  test('notification count uses locale-aware singular and plural forms', () {
    expect(
        AppStrings(AppStrings.fallbackLocale).notificationCount(1), '1 alert');
    expect(
        AppStrings(AppStrings.fallbackLocale).notificationCount(2), '2 alerts');
    expect(AppStrings(const Locale('es')).notificationCount(1), '1 alerta');
    expect(AppStrings(const Locale('de')).notificationCount(2), '2 Hinweise');
    expect(
        AppStrings(const Locale('ar', 'SA')).notificationCount(2), 'تنبيهان');
  });
}

List<String> _placeholderNames(String value) => (RegExp(r'\{([^{}]+)\}')
    .allMatches(value)
    .map((match) => match.group(1)!)
    .toList()
  ..sort());
