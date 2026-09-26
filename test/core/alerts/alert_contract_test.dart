import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/analysis/alert/alert_severity.dart' as analysis;
import 'package:miucam/analysis/alert/alert_type.dart' as analysis;
import 'package:miucam/core/alerts/alert_message_key.dart';
import 'package:miucam/core/alerts/alert_severity.dart';
import 'package:miucam/core/alerts/alert_type.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';

void main() {
  test('analysis compatibility exports retain the shared enum identity', () {
    expect(analysis.AlertType.cryDetected, same(AlertType.cryDetected));
    expect(analysis.AlertSeverity.warning, same(AlertSeverity.warning));
    expect(AlertType.values.map((type) => type.wireValue), [
      'cryDetected',
      'motionDetected',
      'loudSound',
      'globalLightChange',
      'systemWarning',
    ]);
    expect(AlertSeverity.values.map((severity) => severity.wireValue),
        ['info', 'attention', 'warning', 'critical']);
  });

  test('known message keys retain their persisted wire representation', () {
    expect(
        AlertType.values
            .map(AlertMessageKey.forType)
            .map((key) => key.wireValue),
        [
          'parentCryAlert',
          'parentMotionAlert',
          'parentLoudSoundAlert',
          'parentLightChangeAlert',
          'legacyAlert'
        ]);
    expect(AlertMessageKey.tryParse('parentEpisodeHighCryAlert'),
        AlertMessageKey.highCryEpisode);
    expect(AlertMessageKey.tryParse(' PARENTEPISODEHIGHCRYALERT '), isNull);
    expect(AlertMessageKey.tryParseNormalized(' PARENTEPISODEHIGHCRYALERT '),
        AlertMessageKey.highCryEpisode);
  });

  test('legacy severity aliases keep their interruption policy', () {
    expect(AlertSeverity.tryParse(' HIGH '), AlertSeverity.critical);
    expect(AlertSeverity.tryParse('medium'), AlertSeverity.warning);
    expect(AlertSeverity.tryParse('low'), AlertSeverity.info);
    for (final severity in [
      'attention',
      'warning',
      'critical',
      'high',
      'medium'
    ]) {
      expect(AlertSeverity.tryParse(severity)?.isInterruptive, isTrue);
    }
    expect(AlertSeverity.tryParse('info')?.isInterruptive, isFalse);
    expect(AlertSeverity.tryParse('custom-high-state'), isNull);
    expect(AlertSeverity.fromLegacyLabel('custom-high-state'),
        AlertSeverity.critical,
        reason: 'Historical descriptive badges retain their existing label.');
    expect(AlertSeverity.fromLegacyLabel('future-severity'), isNull);
  });

  test(
      'unknown wire values survive round-trip without a typed fallback rewrite',
      () {
    const dto = AlertEventDto(
      id: 'future-peer',
      type: 'futureType',
      severity: 'futureSeverity',
      messageKey: 'futureMessage',
      message: 'Original peer text',
      score: .4,
      timestampMs: 42,
      sourceDeviceId: 'server',
      metadata: {'future': true},
    );
    final restored = AlertEventDto.fromJson(dto.toJson())!;
    expect(restored.toJson(), dto.toJson());
    expect(restored.knownType, isNull);
    expect(restored.knownSeverity, isNull);
    expect(restored.knownMessageKey, isNull);
    expect(restored.category, AlertCategory.system);
  });
}
