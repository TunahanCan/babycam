import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/alert_event_dto.dart';

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
}
