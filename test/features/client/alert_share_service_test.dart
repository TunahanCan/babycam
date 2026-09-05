import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';
import 'package:miucam/features/client/alerts/alert_share_service.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  for (final locale in AppStrings.supportedLocales) {
    test('share text uses selected parent language $locale', () {
      final strings = AppStrings(locale);
      final event = AlertEventDto(
        id: 'share-motion',
        type: 'motionDetected',
        severity: 'info',
        messageKey: 'parentMotionAlert',
        message: 'SERVER LANGUAGE MUST NOT LEAK',
        score: .7,
        timestampMs: DateTime(2026, 9, 5, 14, 8).millisecondsSinceEpoch,
        sourceDeviceId: 'room-device-42',
      );
      final text = AlertShareService().buildShareText(event, strings: strings);
      expect(text, contains(event.localizedMessage(strings)));
      expect(text, contains(strings.formatPercent(70)));
      expect(
          text, contains(strings.formatDateTime(DateTime(2026, 9, 5, 14, 8))));
      expect(text, contains('room-device-42'));
      expect(text, isNot(contains('SERVER LANGUAGE')));
      if (!strings.isTurkish) {
        expect(text, isNot(contains('MiuCam uyarısı:')));
        expect(text, isNot(contains('Cihaz:')));
      }
    });
  }
}
