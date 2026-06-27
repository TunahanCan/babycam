import 'dart:convert';

import '../../analysis/alert/alert_event.dart';
import '../../analysis/alert/alert_type.dart';
import '../../core/mimicam_protocol.dart';
import '../../core/protocol/alert_event_dto.dart';

class AlertProtocolAdapter {
  static List<int> toLegacyAlertPacket(AlertEvent event) =>
      MimiCamProtocol.alertFrame(event.message);

  static String toJsonText(AlertEvent event) =>
      jsonEncode(toDto(event).toJson());

  static AlertEventDto toDto(AlertEvent event) => AlertEventDto(
        id: event.id,
        type: event.type.name,
        severity: event.severity.name,
        messageKey: _messageKey(event),
        message: event.message,
        score: event.score,
        timestampMs: event.timestampMs,
        sourceDeviceId: 'server',
        metadata: event.metadata,
      );

  static String _messageKey(AlertEvent event) {
    if (event.metadata['event'] == 'baby_event') {
      final durationMs = event.metadata['durationMs'];
      final cryScore = event.metadata['cryScore'];
      final resolved = event.metadata['resolved'] == true;
      if (cryScore is num && cryScore > 0.8 && durationMs is num) {
        if (durationMs > 15000) return 'parentEpisodeHighCryAlert';
      }
      if (resolved && durationMs is num && durationMs < 5000) {
        return 'parentEpisodeShortSoundAlert';
      }
      return 'parentEpisodeCryAlert';
    }
    return switch (event.type) {
      AlertType.cryDetected => 'parentCryAlert',
      AlertType.loudSound => 'parentLoudSoundAlert',
      AlertType.motionDetected => 'parentMotionAlert',
      AlertType.globalLightChange => 'parentLightChangeAlert',
      AlertType.systemWarning => 'legacyAlert',
    };
  }
}
