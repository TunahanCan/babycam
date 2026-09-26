/// Classification shared by episode severity, notification text, and protocol
/// message selection. These rules do not control whether an episode is emitted.
abstract final class EpisodeNotificationPolicy {
  static const _highIntensityCryScore = 0.8;
  static const _mediumIntensityCryScore = 0.55;
  static const _prolongedCryDurationMs = 15000;
  static const _shortSoundDurationMs = 5000;

  // Intensity includes the boundary; a warning requires a score above it.
  static String intensityForScore(double cryScore) =>
      cryScore >= _highIntensityCryScore
          ? 'high'
          : cryScore >= _mediumIntensityCryScore
              ? 'medium'
              : 'low';

  static bool isStrongProlongedCry({
    required num cryScore,
    required num durationMs,
  }) =>
      cryScore > _highIntensityCryScore && durationMs > _prolongedCryDurationMs;

  static bool isShortResolvedSound({
    required bool resolved,
    required num durationMs,
  }) =>
      resolved && durationMs < _shortSoundDurationMs;
}
