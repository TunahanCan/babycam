import '../../core/alerts/alert_severity.dart';
import '../../core/media/adaptive_media_profile.dart';
import '../audio/audio_analysis_result.dart';
import '../audio/audio_calibration_state.dart';
import '../video/motion_analysis_result.dart';
import 'baby_event_episode.dart';
import 'episode_notification_policy.dart';

// Preserve the original public import path while keeping episode data,
// aggregation, and localized notification text in separate libraries.
export 'baby_event_episode.dart';
export 'notification_composer.dart';

class EpisodeBasedNotificationAggregator {
  EpisodeBasedNotificationAggregator({
    this.cryThreshold = 0.4,
    this.suspectedCryMs = 2000,
    this.confirmedCryMs = 5000,
    this.resolveQuietMs = 10000,
    this.maxActiveGapMs = 1500,
    this.minActiveEvidenceRatio = 0.70,
  })  : assert(cryThreshold >= 0 && cryThreshold <= 1),
        assert(suspectedCryMs >= 0),
        assert(confirmedCryMs >= suspectedCryMs),
        assert(resolveQuietMs >= 0),
        assert(maxActiveGapMs > 0),
        assert(minActiveEvidenceRatio >= 0 && minActiveEvidenceRatio <= 1);

  final double cryThreshold;
  final int suspectedCryMs;
  final int confirmedCryMs;
  final int resolveQuietMs;
  final int maxActiveGapMs;
  final double minActiveEvidenceRatio;
  static const _motionAssociationWindowMs = 5000;

  BabyEventEpisodeState _state = BabyEventEpisodeState.quiet;
  int _sequence = 0;
  int? _episodeStartedAtMs;
  int? _lastCryAtMs;
  int? _lastSampleAtMs;
  int? _lastMotionAtMs;
  int _totalCryDurationMs = 0;
  int _motionBursts = 0;
  int _sampleCount = 0;
  double _scoreSum = 0;
  double _maxScore = 0;
  bool _confirmedDelivered = false;
  bool _lastSampleWasActive = false;
  bool _motionActive = false;

  BabyEventEpisodeState get state => _state;

  void onMotionResult(MotionAnalysisResult result) {
    if (result.skippedByFrameRateGate) return;
    if (result.invalidFrame) {
      markVideoDiscontinuity();
      return;
    }
    if (!result.isMotion || result.isGlobalLightChange) {
      _motionActive = false;
      return;
    }
    // Motion is only evidence for the current audio episode. Keep a short
    // pending window for a camera burst that arrives just before its audio
    // window, but never carry stale motion into a later episode.
    final episodeStartedAtMs = _episodeStartedAtMs;
    if (episodeStartedAtMs == null &&
        _lastMotionAtMs != null &&
        result.timestampMs - _lastMotionAtMs! > _motionAssociationWindowMs) {
      _motionBursts = 0;
      _motionActive = false;
    }
    if (!_motionActive) _motionBursts++;
    _motionActive = true;
    _lastMotionAtMs = result.timestampMs;
  }

  BabyEventEpisode? onAudioResult(
    AudioAnalysisResult result, {
    NetworkQualityTier streamQualityTier = NetworkQualityTier.unknown,
    bool audioReliable = true,
    bool videoReliable = true,
  }) {
    if (!videoReliable) markVideoDiscontinuity();
    // Ambient calibration is part of the signal contract. Before it finishes,
    // a loud room, microphone gain change, or startup transient must not start
    // an episode that can later be promoted to a phone notification.
    if (!audioReliable ||
        result.invalidChunk ||
        result.isClipped ||
        !result.isCalibrated ||
        result.calibrationState != AudioCalibrationState.calibrated) {
      if (_state != BabyEventEpisodeState.quiet) reset();
      return null;
    }
    final nowMs = result.timestampMs;
    final lastSampleAtMs = _lastSampleAtMs;
    if (lastSampleAtMs != null && nowMs < lastSampleAtMs) {
      // A capture restart or clock reset must not turn old and new evidence
      // into one continuous episode.
      reset();
    }
    // CryAudioAnalyzerV2 already owns feature extraction and score smoothing.
    // Re-scoring the same window here made screen thresholds behave
    // differently from the analyzer and could apply the duration gate twice.
    final cryScore = result.cryScore.clamp(0.0, 1.0).toDouble();
    final active = cryScore >= cryThreshold || result.isCryLikely;

    if (active) {
      final previousCryAtMs = _lastCryAtMs;
      if (previousCryAtMs != null && nowMs - previousCryAtMs > maxActiveGapMs) {
        // Missing packets are not evidence of continuous crying. Start a new
        // episode instead of turning two isolated sounds into one alert.
        reset();
      }
      _startIfNeeded(nowMs);
      final previousSampleAtMs = _lastSampleAtMs;
      if (_lastSampleWasActive &&
          previousSampleAtMs != null &&
          nowMs >= previousSampleAtMs) {
        final activeIntervalMs = nowMs - previousSampleAtMs;
        if (activeIntervalMs <= maxActiveGapMs) {
          _totalCryDurationMs += activeIntervalMs;
        }
      }
      _lastSampleAtMs = nowMs;
      _lastSampleWasActive = true;
      _lastCryAtMs = nowMs;
      _sampleCount++;
      _scoreSum += cryScore;
      if (cryScore > _maxScore) _maxScore = cryScore;
      final activeRatio = _activeEvidenceRatio(nowMs);
      if (_totalCryDurationMs >= confirmedCryMs &&
          activeRatio >= minActiveEvidenceRatio) {
        _state = _confirmedDelivered
            ? BabyEventEpisodeState.ongoingCry
            : BabyEventEpisodeState.confirmedCry;
        if (!_confirmedDelivered) {
          return _episode(
            nowMs,
            streamQualityTier: streamQualityTier,
            audioReliable: audioReliable,
            videoReliable: videoReliable,
          );
        }
      } else if (_totalCryDurationMs >= suspectedCryMs &&
          activeRatio >= minActiveEvidenceRatio) {
        _state = BabyEventEpisodeState.suspectedCry;
      }
      return null;
    }

    _lastSampleAtMs = nowMs;
    _lastSampleWasActive = false;
    final lastCryAtMs = _lastCryAtMs;
    if (_episodeStartedAtMs != null &&
        lastCryAtMs != null &&
        nowMs - lastCryAtMs >= resolveQuietMs) {
      final resolved = _episode(
        nowMs,
        streamQualityTier: streamQualityTier,
        audioReliable: audioReliable,
        videoReliable: videoReliable,
        resolved: true,
      );
      reset();
      return resolved;
    }
    return null;
  }

  /// Marks a confirmed episode as delivered only after the outer cooldown
  /// policy accepted it. Rejected episodes remain eligible once cooldown ends.
  void acknowledgeNotification(BabyEventEpisode episode) {
    if (episode.resolved ||
        episode.episodeId != 'episode-$_sequence' ||
        _episodeStartedAtMs == null) {
      return;
    }
    _confirmedDelivered = true;
    _state = BabyEventEpisodeState.ongoingCry;
  }

  /// Drops camera evidence without disturbing an in-progress audio episode.
  void markVideoDiscontinuity() {
    _lastMotionAtMs = null;
    _motionBursts = 0;
    _motionActive = false;
  }

  void reset() {
    _state = BabyEventEpisodeState.quiet;
    _episodeStartedAtMs = null;
    _lastCryAtMs = null;
    _lastSampleAtMs = null;
    _lastMotionAtMs = null;
    _totalCryDurationMs = 0;
    _motionBursts = 0;
    _sampleCount = 0;
    _scoreSum = 0;
    _maxScore = 0;
    _confirmedDelivered = false;
    _lastSampleWasActive = false;
    _motionActive = false;
  }

  void _startIfNeeded(int nowMs) {
    if (_episodeStartedAtMs != null) return;
    if (_lastMotionAtMs == null ||
        nowMs < _lastMotionAtMs! ||
        nowMs - _lastMotionAtMs! > _motionAssociationWindowMs) {
      _motionBursts = 0;
      _lastMotionAtMs = null;
      _motionActive = false;
    }
    _episodeStartedAtMs = nowMs;
    _state = BabyEventEpisodeState.suspectedCry;
    _sequence++;
  }

  BabyEventEpisode _episode(
    int nowMs, {
    required NetworkQualityTier streamQualityTier,
    required bool audioReliable,
    required bool videoReliable,
    bool resolved = false,
  }) {
    final durationMs = _episodeStartedAtMs == null ? 0 : _totalCryDurationMs;
    final avgScore = _sampleCount == 0 ? 0.0 : _scoreSum / _sampleCount;
    final intensity = EpisodeNotificationPolicy.intensityForScore(_maxScore);
    final severity = EpisodeNotificationPolicy.isStrongProlongedCry(
      cryScore: _maxScore,
      durationMs: durationMs,
    )
        ? AlertSeverity.warning
        : durationMs >= confirmedCryMs
            ? AlertSeverity.attention
            : AlertSeverity.info;
    final activeEvidenceRatio = _activeEvidenceRatio(nowMs);
    final confirmed = _confirmedDelivered ||
        _state == BabyEventEpisodeState.confirmedCry ||
        _state == BabyEventEpisodeState.ongoingCry ||
        (durationMs >= confirmedCryMs &&
            activeEvidenceRatio >= minActiveEvidenceRatio);
    return BabyEventEpisode(
      episodeId: 'episode-$_sequence',
      startedAtMs: _episodeStartedAtMs ?? nowMs,
      lastUpdatedAtMs: nowMs,
      totalCryDurationMs: durationMs,
      maxCryScore: _maxScore,
      avgCryScore: avgScore,
      motionBursts: _motionBursts,
      lastMotionAtMs: _lastMotionAtMs,
      streamQualityTier: streamQualityTier,
      audioReliable: audioReliable,
      videoReliable: videoReliable,
      severity: severity,
      intensity: intensity,
      resolved: resolved,
      confirmed: confirmed,
      activeEvidenceRatio: activeEvidenceRatio,
    );
  }

  double _activeEvidenceRatio(int nowMs) {
    final startedAtMs = _episodeStartedAtMs;
    if (startedAtMs == null || nowMs <= startedAtMs) {
      return _lastSampleWasActive ? 1 : 0;
    }
    return (_totalCryDurationMs / (nowMs - startedAtMs))
        .clamp(0.0, 1.0)
        .toDouble();
  }
}
