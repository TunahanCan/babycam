import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/adaptive_media_profile.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  const semanticWords = {
    'en': (cry: 'crying', motion: 'movement', loud: 'loud', short: 'sound'),
    'tr': (cry: 'ağlıyor', motion: 'hareket', loud: 'yüksek', short: 'ses'),
    'zh': (cry: '哭', motion: '动静', loud: '较大', short: '声音'),
    'hi': (cry: 'रो', motion: 'हलचल', loud: 'तेज़', short: 'आवाज़'),
    'es': (
      cry: 'llorando',
      motion: 'movimiento',
      loud: 'fuerte',
      short: 'sonido'
    ),
    'fr': (cry: 'pleure', motion: 'mouvement', loud: 'fort', short: 'son'),
    'de': (cry: 'weint', motion: 'bewegung', loud: 'lautes', short: 'geräusch'),
    'ar': (cry: 'يبكي', motion: 'حركة', loud: 'عال', short: 'صوت'),
  };

  for (final locale in AppStrings.supportedLocales) {
    final strings = AppStrings(locale);
    final tag = locale.toLanguageTag();

    test('$tag preserves cry, movement, loud sound and short sound meaning',
        () {
      final words = semanticWords[locale.languageCode]!;
      final cases = [
        (key: 'parentCryAlert', type: 'cryDetected', word: words.cry),
        (key: 'parentEpisodeCryAlert', type: 'cryDetected', word: words.cry),
        (
          key: 'parentEpisodeHighCryAlert',
          type: 'cryDetected',
          word: words.cry
        ),
        (key: 'parentMotionAlert', type: 'motionDetected', word: words.motion),
        (key: 'parentLoudSoundAlert', type: 'loudSound', word: words.loud),
        (
          key: 'parentEpisodeShortSoundAlert',
          type: 'cryDetected',
          word: words.short
        ),
      ];
      final titles = <String, String>{};
      for (final sample in cases) {
        final title = strings.alertNotificationTitle(
          type: sample.type,
          messageKey: sample.key,
        );
        titles[sample.key] = title;
        expect(title.toLowerCase(), contains(sample.word), reason: sample.key);
        expect(
            strings.alertNotificationBody(
                type: sample.type, messageKey: sample.key),
            isNotEmpty,
            reason: sample.key);
        // Known message metadata also survives a legacy/mismatched type.
        expect(
            strings.alertNotificationTitle(
                type: 'systemWarning', messageKey: sample.key),
            title,
            reason: sample.key);
      }
      expect(titles['parentLoudSoundAlert'],
          isNot(titles['parentEpisodeShortSoundAlert']));
      expect(titles['parentCryAlert'],
          isNot(titles['parentEpisodeShortSoundAlert']));
      expect(
          strings.alertNotificationTitle(
              type: 'cryDetected', messageKey: 'parentMotionAlert'),
          titles['parentMotionAlert']);
    });

    test(
        '$tag stream, room controls, analysis pause and severity copy is complete',
        () {
      const keys = [
        'babyRoomName',
        'watchReconnectingSubtitle',
        'watchStartingSubtitle',
        'watchStreamUnavailableTitle',
        'watchConnectionErrorSubtitle',
        'roomControlFailed',
        'microphonePermissionRequired',
        'roomAudioDetectionHelp',
        'roomAudioDetectionPaused',
        'roomAudioDetectionResumeHelp',
        'comfortAudio',
        'playComfort',
        'pauseComfort',
        'holdToTalk',
        'talkingNow',
        'talkHelp',
        'talkAccessibilityHint',
        'roomVolume',
        'motion',
        'audio',
        'system',
        'important',
        'warning',
        'info',
        'notificationsInAppOnly',
        'notificationOff',
      ];
      final english = AppStrings(AppStrings.fallbackLocale);
      for (final key in keys) {
        final text = strings.ui(key);
        expect(text, isNot(key), reason: key);
        expect(text, isNotEmpty, reason: key);
        expect(text, isNot(contains('{')), reason: key);
        if (locale.languageCode != 'en') {
          // Audio is also the native French/German term.
          if (key == 'audio' && ['fr', 'de'].contains(locale.languageCode)) {
            continue;
          }
          expect(text, isNot(english.ui(key)), reason: key);
        }
      }
      expect(strings.alertDetailsUnavailable, isNotEmpty);
      if (locale.languageCode != 'en') {
        expect(strings.alertDetailsUnavailable,
            isNot(english.alertDetailsUnavailable));
      }
    });

    test(
        '$tag share text localizes labels, date and score without changing device identity',
        () {
      const deviceId = 'camera-42-{time}';
      const message = 'Nursery {score}';
      final time = DateTime(2026, 9, 5, 13, 7);
      final text = strings.alertShareText(
        message: message,
        time: time,
        score: 0.825,
        deviceId: deviceId,
      );
      expect(text.split('\n'), hasLength(4));
      expect(text, contains(message));
      expect(text, contains(deviceId));
      expect(text, contains(strings.formatDateTime(time)));
      expect(text, contains(strings.formatPercent(82.5)));
      if (locale.languageCode != 'en') {
        expect(text, isNot(contains('MiuCam alert:')));
        expect(text, isNot(contains('Device:')));
      }
    });
  }

  test(
      'number formatting follows decimal and grouping rules without changing protocols',
      () {
    const expected = {
      'en': '1234.5',
      'tr': '1234,5',
      'zh': '1234.5',
      'hi': '1234.5',
      'es': '1234,5',
      'fr': '1234,5',
      'de': '1234,5',
      'ar': '١٢٣٤٫٥',
    };
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings(locale);
      expect(strings.formatNumber(1234.5, decimalDigits: 1),
          expected[locale.languageCode],
          reason: locale.toLanguageTag());
      expect(strings.uiFormat('pairedMessage', {'name': 'room-12.34'}),
          contains('room-12.34'));
    }
    expect(
        AppStrings(const Locale('hi'))
            .formatNumber(123456.7, useGrouping: true),
        '1,23,456.7');
    expect(AppStrings(const Locale('tr')).formatPercent(82), '%82');
    expect(AppStrings(const Locale('en', 'US')).formatPercent(82), '82%');
  });

  test(
      'both Gulf locales use Arabic-Indic digits in alert metadata and durations',
      () {
    for (final locale in [const Locale('ar', 'SA'), const Locale('ar', 'QA')]) {
      final strings = AppStrings(locale);
      expect(strings.formatPercent(82), contains('٨٢٪'));
      expect(strings.parentMotionAgo(12000), contains('١٢'));
      expect(
          strings.parentEpisodeCryAlert(
              seconds: 12,
              networkTier:
                  strings.networkQualityLabel(NetworkQualityTier.weak)),
          contains('١٢'));
      expect(
          strings.uiFormat(
              'durationHoursMinutesShort', {'hours': 1, 'minutes': 25}),
          '١ س ٢٥ د');
      final summary = strings.audioSummary(
          dbfs: -22.4,
          ambientDbfs: -37.1,
          f0: strings.pitchSuffix(440),
          centroidHz: 2100,
          bandwidthHz: 1200,
          zcr: 0.14,
          entropy: 0.62,
          cryPercent: 71,
          moanPercent: 12);
      expect(summary, contains('٢٢٫٤'));
      expect(summary, contains('٠٫١٤'));
      expect(summary, contains('٧١٪'));
      expect(strings.formatDateTime(DateTime(2026, 9, 5, 13, 7)),
          contains('٢٠٢٦'));
    }
  });

  test(
      'French and Arabic notification counts use the correct plural categories',
      () {
    final french = AppStrings(const Locale('fr'));
    expect(french.notificationCount(0), '0 alerte');
    expect(french.notificationCount(2), '2 alertes');
    final arabic = AppStrings(const Locale('ar', 'QA'));
    expect(arabic.notificationCount(0), 'لا توجد تنبيهات');
    expect(arabic.notificationCount(1), 'تنبيه واحد');
    expect(arabic.notificationCount(2), 'تنبيهان');
    expect(arabic.notificationCount(3), '٣ تنبيهات');
    expect(arabic.notificationCount(11), '١١ تنبيهاً');
    expect(arabic.notificationCount(100), '١٠٠ تنبيه');
  });

  test(
      'numeric UI placeholders and freeform names are substituted exactly once',
      () {
    final strings = AppStrings(const Locale('fr'));
    expect(strings.uiFormat('motionCalmScore', {'score': 0.125}),
        contains('0,125'));
    expect(
        strings.uiFormat(
            'pairedMessage', {'name': 'Nursery {error}', 'error': 'REPLACED'}),
        contains('Nursery {error}'));
    expect(strings.formatNumber(double.nan), '—');
    expect(strings.formatPercent(double.infinity), '—');
  });
}
