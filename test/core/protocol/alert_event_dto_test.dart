import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/analysis/alert/alert_event.dart';
import 'package:mimicam/analysis/alert/alert_severity.dart';
import 'package:mimicam/analysis/alert/alert_type.dart';
import 'package:mimicam/core/protocol/alert_event_dto.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/server/alert_protocol_adapter.dart';

void main() {
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
