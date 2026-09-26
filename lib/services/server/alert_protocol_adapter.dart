import 'dart:convert';

import '../../analysis/alert/alert_event.dart';
import '../../analysis/alert/episode_notification_policy.dart';
import '../../core/alerts/alert_message_key.dart';
import '../../core/miucam_protocol.dart';
import '../../core/protocol/alert_event_dto.dart';

class AlertProtocolAdapter {
  static List<int> toLegacyAlertPacket(AlertEvent event) =>
      MiuCamProtocol.alertFrame(event.message);

  static String toJsonText(AlertEvent event) =>
      jsonEncode(toDto(event).toJson());

  static AlertEventDto toDto(AlertEvent event) => AlertEventDto(
        id: event.id,
        type: event.type.wireValue,
        severity: event.severity.wireValue,
        messageKey: _messageKey(event).wireValue,
        message: event.message,
        score: event.score,
        timestampMs: event.timestampMs,
        sourceDeviceId: 'server',
        snapshotAvailable: event.metadata['snapshotAvailable'] is bool
            ? event.metadata['snapshotAvailable'] as bool
            : null,
        battery: event.metadata['battery'] is Map
            ? Map<String, Object?>.from(event.metadata['battery'] as Map)
            : null,
        transport: event.metadata['transport']?.toString(),
        childId: event.metadata['childId']?.toString(),
        metadata: event.metadata,
      );

  static AlertMessageKey _messageKey(AlertEvent event) {
    if (event.metadata['event'] == 'baby_event') {
      final durationMs = event.metadata['durationMs'];
      final cryScore = event.metadata['cryScore'];
      final resolved = event.metadata['resolved'] == true;
      if (cryScore is num &&
          durationMs is num &&
          EpisodeNotificationPolicy.isStrongProlongedCry(
              cryScore: cryScore, durationMs: durationMs)) {
        return AlertMessageKey.highCryEpisode;
      }
      if (durationMs is num &&
          EpisodeNotificationPolicy.isShortResolvedSound(
              resolved: resolved, durationMs: durationMs)) {
        return AlertMessageKey.shortSoundEpisode;
      }
      return AlertMessageKey.cryEpisode;
    }
    return AlertMessageKey.forType(event.type);
  }
}
