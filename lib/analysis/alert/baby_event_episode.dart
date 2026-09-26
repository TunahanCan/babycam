import '../../core/alerts/alert_severity.dart';
import '../../core/media/adaptive_media_profile.dart';

enum BabyEventEpisodeState {
  quiet,
  suspectedCry,
  confirmedCry,
  ongoingCry,
  resolved,
}

class BabyEventEpisode {
  const BabyEventEpisode({
    required this.episodeId,
    required this.startedAtMs,
    required this.lastUpdatedAtMs,
    required this.totalCryDurationMs,
    required this.maxCryScore,
    required this.avgCryScore,
    required this.motionBursts,
    this.lastMotionAtMs,
    this.streamQualityTier = NetworkQualityTier.unknown,
    this.audioReliable = true,
    this.videoReliable = true,
    this.severity = AlertSeverity.info,
    this.intensity = 'low',
    this.resolved = false,
    this.confirmed = false,
    this.activeEvidenceRatio = 0,
  });

  final String episodeId;
  final int startedAtMs;
  final int lastUpdatedAtMs;
  final int totalCryDurationMs;
  final double maxCryScore;
  final double avgCryScore;
  final int motionBursts;
  final int? lastMotionAtMs;
  final NetworkQualityTier streamQualityTier;
  final bool audioReliable;
  final bool videoReliable;
  final AlertSeverity severity;
  final String intensity;
  final bool resolved;
  final bool confirmed;
  final double activeEvidenceRatio;

  int? lastMotionAgoMs() =>
      lastMotionAtMs == null ? null : lastUpdatedAtMs - lastMotionAtMs!;

  Map<String, Object?> toJson() => {
        'event': 'baby_event',
        'episodeId': episodeId,
        'startedAtMs': startedAtMs,
        'lastUpdatedAtMs': lastUpdatedAtMs,
        'durationMs': totalCryDurationMs,
        'cryScore': maxCryScore,
        'avgCryScore': avgCryScore,
        'motionDetected': motionBursts > 0,
        'motionBursts': motionBursts,
        'lastMotionAgoMs': lastMotionAgoMs(),
        'audioReliable': audioReliable,
        'videoReliable': videoReliable,
        'networkTier': streamQualityTier.name,
        'severity': severity.wireValue,
        'intensity': intensity,
        'resolved': resolved,
        'confirmed': confirmed,
        'activeEvidenceRatio': activeEvidenceRatio,
      };
}
