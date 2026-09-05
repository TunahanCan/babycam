import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/analysis/alert/alert_event.dart';
import 'package:miucam/analysis/alert/alert_severity.dart';
import 'package:miucam/analysis/alert/alert_type.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/server/alert_protocol_adapter.dart';

void main() {
  test('semantic message keys keep filtering and translated copy consistent',
      () {
    const alert = AlertEventDto(
      id: 'older-generic-envelope',
      type: 'systemWarning',
      severity: 'warning',
      messageKey: 'parentMotionAlert',
      message: 'SERVER_LANGUAGE_MUST_NOT_LEAK',
      score: .5,
      timestampMs: 1,
      sourceDeviceId: 'server',
    );
    expect(alert.category, AlertCategory.motion);
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings(locale);
      expect(
          alert.localizedTitle(strings),
          strings.alertNotificationTitle(
              type: 'motionDetected', messageKey: 'parentMotionAlert'));
      expect(
          alert.localizedMessage(strings),
          strings.alertNotificationBody(
              type: 'motionDetected', messageKey: 'parentMotionAlert'));
      expect(
          alert.localizedMessage(strings), isNot(contains('SERVER_LANGUAGE')));
    }
  });

  test('unknown legacy messages stay localized without rewriting wire data',
      () {
    const alert = AlertEventDto(
      id: 'old-protocol',
      type: 'legacyAlert',
      severity: 'info',
      messageKey: 'legacyAlert',
      message: 'SUNUCU DİLİNDE UYARI',
      score: 0,
      timestampMs: 1,
      sourceDeviceId: 'server',
    );
    for (final locale in AppStrings.supportedLocales) {
      final strings = AppStrings(locale);
      expect(alert.localizedMessage(strings), strings.alertDetailsUnavailable);
      expect(alert.localizedNotificationBody(strings),
          strings.alertDetailsUnavailable);
    }
    expect(AlertEventDto.fromJson(alert.toJson())!.message, alert.message);
  });

  test('alert kategorileri event tipinden kesin olarak belirlenir', () {
    expect(_categoryOf('cryDetected', 'parentCryAlert'), AlertCategory.audio);
    expect(
        _categoryOf('loudSound', 'parentLoudSoundAlert'), AlertCategory.audio);
    expect(_categoryOf('motionDetected', 'parentMotionAlert'),
        AlertCategory.motion);
    expect(
      _categoryOf('globalLightChange', 'parentLightChangeAlert'),
      AlertCategory.motion,
    );
    expect(_categoryOf('systemWarning', 'legacyAlert'), AlertCategory.system);
    expect(_categoryOf('batteryLow', 'batteryLow'), AlertCategory.system);
  });

  test('toJson transport şemasını korur', () {
    const dto = AlertEventDto(
      id: 'alert-1',
      type: 'cryDetected',
      severity: 'warning',
      messageKey: 'parentCryAlert',
      message: 'Cry detected',
      score: 0.82,
      timestampMs: 1234,
      sourceDeviceId: 'server',
      metadata: {'cryScore': 0.82},
    );

    expect(dto.toJson(), {
      'schemaVersion': 1,
      'id': 'alert-1',
      'type': 'cryDetected',
      'severity': 'warning',
      'messageKey': 'parentCryAlert',
      'message': 'Cry detected',
      'score': 0.82,
      'timestampMs': 1234,
      'sourceDeviceId': 'server',
      'metadata': {'cryScore': 0.82},
    });
  });

  test('fromJson ve localizedMessage client locale metni üretir', () {
    final dto = AlertEventDto.fromJson({
      'schemaVersion': 1,
      'id': 'alert-2',
      'type': 'motionDetected',
      'severity': 'info',
      'messageKey': 'parentMotionAlert',
      'message': 'Motion detected',
      'score': 0.64,
      'timestampMs': 99,
      'sourceDeviceId': 'server',
      'metadata': {
        'scorePercent': 64,
        'activeAreaPercent': 12,
        'meanDiff': 7.4,
      },
    });

    expect(dto, isNotNull);
    final message = dto!.localizedMessage(AppStrings(const Locale('es', 'ES')));
    expect(message, contains('movimiento'));
    expect(message, isNot(contains('Motion detected')));
  });

  test('eksik analiz metadata sayi uydurmadan ebeveyn dilinde gösterilir', () {
    const dto = AlertEventDto(
      id: 'legacy-cry',
      type: 'cryDetected',
      severity: 'warning',
      messageKey: 'parentCryAlert',
      message:
          'Anne, odada ağlama benzeri bir ses duyuldu; lütfen görüntüyü kontrol et.',
      score: .8,
      timestampMs: 42,
      sourceDeviceId: 'server',
    );

    final strings = AppStrings(const Locale('en'));
    expect(
        dto.localizedMessage(strings), dto.localizedNotificationBody(strings));
    expect(dto.localizedMessage(strings), isNot(contains('Anne')));
    expect(dto.localizedMessage(strings), isNot(contains('0%')));
    expect(dto.toJson()['message'], dto.message);
  });

  test('yanlış tipte veya aralık dışı metadata güvenli mesaja düşer', () {
    const invalidCry = AlertEventDto(
      id: 'invalid-cry',
      type: 'cryDetected',
      severity: 'warning',
      messageKey: 'parentCryAlert',
      message: 'Server fallback message',
      score: .8,
      timestampMs: 42,
      sourceDeviceId: 'server',
      metadata: {
        'confidencePercent': '82',
        'ambientDeltaDb': 14.2,
        'cryBandPercent': 168,
        'isCalibrated': true,
      },
    );
    const invalidEpisode = AlertEventDto(
      id: 'invalid-episode',
      type: 'cryDetected',
      severity: 'attention',
      messageKey: 'parentEpisodeCryAlert',
      message: 'Episode fallback message',
      score: .8,
      timestampMs: 43,
      sourceDeviceId: 'server',
      metadata: {'durationMs': 9000, 'networkTier': 7},
    );
    final strings = AppStrings(AppStrings.fallbackLocale);

    expect(invalidCry.localizedMessage(strings),
        invalidCry.localizedNotificationBody(strings));
    expect(invalidEpisode.localizedMessage(strings),
        invalidEpisode.localizedNotificationBody(strings));
    expect(invalidCry.localizedMessage(strings),
        isNot(contains('Server fallback')));
    expect(invalidEpisode.localizedMessage(strings),
        isNot(contains('Episode fallback')));
  });

  test('hareket zamanı null olan uzun ağlama olayı client dilinde kalır', () {
    const dto = AlertEventDto(
      id: 'episode-without-motion',
      type: 'cryDetected',
      severity: 'attention',
      messageKey: 'parentEpisodeHighCryAlert',
      message: 'Sunucunun ham mesajı',
      score: .91,
      timestampMs: 44,
      sourceDeviceId: 'server',
      metadata: {
        'durationMs': 18000,
        'networkTier': 'good',
        'lastMotionAgoMs': null,
      },
    );
    final localized = dto.localizedMessage(
      AppStrings(AppStrings.fallbackLocale),
    );

    expect(localized, isNot(dto.message));
    expect(localized, contains('No recent camera movement'));
  });

  test('alert title and native body follow message type and client locale', () {
    const dto = AlertEventDto(
      id: 'motion-title',
      type: 'motionDetected',
      severity: 'info',
      messageKey: 'parentMotionAlert',
      message: 'Motion detected',
      score: .64,
      timestampMs: 99,
      sourceDeviceId: 'server',
      metadata: {
        'scorePercent': 64,
        'activeAreaPercent': 12,
        'meanDiff': 7.4,
      },
    );
    final strings = AppStrings(const Locale('es'));

    expect(
        dto.localizedTitle(strings), 'Movimiento detectado en la habitación');
    expect(dto.localizedNotificationBody(strings), startsWith('Mamá,'));
    expect(dto.localizedNotificationBody(strings), isNot(contains('7,4')));
    expect(dto.localizedMessage(strings), contains('7,4'));
  });

  test('system notification body follows client locale instead of server text',
      () {
    const dto = AlertEventDto(
      id: 'system-locale',
      type: 'systemWarning',
      severity: 'info',
      messageKey: 'legacyAlert',
      message: 'MiuCam test bildirimi',
      score: 0,
      timestampMs: 100,
      sourceDeviceId: 'server',
    );
    final strings = AppStrings(AppStrings.fallbackLocale);

    expect(dto.localizedTitle(strings), 'Nursery status update');
    expect(dto.localizedNotificationBody(strings), startsWith('Mom,'));
    expect(
      dto.localizedNotificationBody(strings),
      isNot(contains('test bildirimi')),
    );
    expect(
        dto.localizedMessage(strings), dto.localizedNotificationBody(strings));
    expect(dto.toJson()['message'], dto.message);
  });

  test('opsiyonel alert alanlari geriye uyumlu round-trip edilir', () {
    const dto = AlertEventDto(
      id: 'alert-optional',
      type: 'batteryLow',
      severity: 'warning',
      messageKey: 'legacyAlert',
      message: 'Battery low',
      score: 1,
      timestampMs: 42,
      sourceDeviceId: 'server',
      snapshotAvailable: true,
      battery: {'levelPercent': 12, 'isLow': true},
      transport: 'wifi_lan',
      childId: 'server-a',
      metadata: {'event': 'battery'},
    );

    final parsed = AlertEventDto.fromJson(dto.toJson());

    expect(parsed?.snapshotAvailable, isTrue);
    expect(parsed?.battery?['levelPercent'], 12);
    expect(parsed?.transport, 'wifi_lan');
    expect(parsed?.childId, 'server-a');
  });

  test('AlertProtocolAdapter optional metadata alanlarini DTOya tasir', () {
    const event = AlertEvent(
      id: 'alert-optional-adapter',
      type: AlertType.systemWarning,
      severity: AlertSeverity.warning,
      message: 'Battery low',
      score: 1,
      timestampMs: 42,
      metadata: {
        'snapshotAvailable': true,
        'battery': {'levelPercent': 9, 'isCritical': true},
        'transport': 'hotspot_lan',
        'childId': 'server-b',
      },
    );

    final json = jsonDecode(AlertProtocolAdapter.toJsonText(event))
        as Map<String, Object?>;

    expect(json['snapshotAvailable'], isTrue);
    expect((json['battery'] as Map)['levelPercent'], 9);
    expect(json['transport'], 'hotspot_lan');
    expect(json['childId'], 'server-b');
  });

  test('AlertProtocolAdapter JSON transportu messageKey ve metadata taşır', () {
    const event = AlertEvent(
      id: 'alert-3',
      type: AlertType.cryDetected,
      severity: AlertSeverity.warning,
      message: 'Ağlama algılandı',
      score: .91,
      timestampMs: 123,
      metadata: {
        'confidencePercent': 91,
        'ambientDeltaDb': 14.2,
        'cryBandPercent': 68,
        'isCalibrated': true,
      },
    );

    final json = jsonDecode(AlertProtocolAdapter.toJsonText(event))
        as Map<String, Object?>;

    expect(json['schemaVersion'], 1);
    expect(json['messageKey'], 'parentCryAlert');
    expect((json['metadata'] as Map)['confidencePercent'], 91);
  });
}

AlertCategory _categoryOf(String type, String messageKey) => AlertEventDto(
      id: 'category-test',
      type: type,
      severity: 'info',
      messageKey: messageKey,
      message: 'test',
      score: 0,
      timestampMs: 0,
      sourceDeviceId: 'server',
    ).category;
