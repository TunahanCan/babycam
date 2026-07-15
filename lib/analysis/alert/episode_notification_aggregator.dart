import '../../core/media/adaptive_media_profile.dart';
import '../../l10n/app_strings.dart';
import '../audio/audio_analysis_result.dart';
import '../audio/audio_calibration_state.dart';
import '../video/motion_analysis_result.dart';
import 'alert_severity.dart';

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
        'severity': severity.name,
        'intensity': intensity,
        'resolved': resolved,
      };
}

class EpisodeBasedNotificationAggregator {
  EpisodeBasedNotificationAggregator({
    this.cryThreshold = 0.4,
    this.suspectedCryMs = 2000,
    this.confirmedCryMs = 5000,
    this.resolveQuietMs = 10000,
    this.maxActiveGapMs = 1500,
  })  : assert(cryThreshold >= 0 && cryThreshold <= 1),
        assert(suspectedCryMs >= 0),
        assert(confirmedCryMs >= suspectedCryMs),
        assert(resolveQuietMs >= 0),
        assert(maxActiveGapMs > 0);

  final double cryThreshold;
  final int suspectedCryMs;
  final int confirmedCryMs;
  final int resolveQuietMs;
  final int maxActiveGapMs;
  static const _motionAssociationWindowMs = 5000;

  BabyEventEpisodeState _state = BabyEventEpisodeState.quiet;
  int _sequence = 0;
  int? _episodeStartedAtMs;
  int? _lastCryAtMs;
  int? _lastMotionAtMs;
  int _totalCryDurationMs = 0;
  int _motionBursts = 0;
  int _sampleCount = 0;
  double _scoreSum = 0;
  double _maxScore = 0;
  bool _confirmedDelivered = false;

  BabyEventEpisodeState get state => _state;

  void onMotionResult(MotionAnalysisResult result) {
    if (!result.isMotion) return;
    // Motion is only evidence for the current audio episode. Keep a short
    // pending window for a camera burst that arrives just before its audio
    // window, but never carry stale motion into a later episode.
    final episodeStartedAtMs = _episodeStartedAtMs;
    if (episodeStartedAtMs == null &&
        _lastMotionAtMs != null &&
        result.timestampMs - _lastMotionAtMs! > _motionAssociationWindowMs) {
      _motionBursts = 0;
    }
    _motionBursts++;
    _lastMotionAtMs = result.timestampMs;
  }

  BabyEventEpisode? onAudioResult(
    AudioAnalysisResult result, {
    NetworkQualityTier streamQualityTier = NetworkQualityTier.unknown,
    bool audioReliable = true,
    bool videoReliable = true,
  }) {
    // Ambient calibration is part of the signal contract. Before it finishes,
    // a loud room, microphone gain change, or startup transient must not start
    // an episode that can later be promoted to a phone notification.
    if (result.invalidChunk ||
        !result.isCalibrated ||
        result.calibrationState != AudioCalibrationState.calibrated) {
      if (_state != BabyEventEpisodeState.quiet) reset();
      return null;
    }
    final nowMs = result.timestampMs;
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
      final lastCryAtMs = _lastCryAtMs;
      if (lastCryAtMs != null && nowMs >= lastCryAtMs) {
        _totalCryDurationMs += nowMs - lastCryAtMs;
      }
      _lastCryAtMs = nowMs;
      _sampleCount++;
      _scoreSum += cryScore;
      if (cryScore > _maxScore) _maxScore = cryScore;
      final activeDuration = nowMs - _episodeStartedAtMs!;
      if (activeDuration >= confirmedCryMs) {
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
      } else if (activeDuration >= suspectedCryMs) {
        _state = BabyEventEpisodeState.suspectedCry;
      }
      return null;
    }

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

  void reset() {
    _state = BabyEventEpisodeState.quiet;
    _episodeStartedAtMs = null;
    _lastCryAtMs = null;
    _lastMotionAtMs = null;
    _totalCryDurationMs = 0;
    _motionBursts = 0;
    _sampleCount = 0;
    _scoreSum = 0;
    _maxScore = 0;
    _confirmedDelivered = false;
  }

  void _startIfNeeded(int nowMs) {
    if (_episodeStartedAtMs != null) return;
    if (_lastMotionAtMs == null ||
        nowMs - _lastMotionAtMs! > _motionAssociationWindowMs) {
      _motionBursts = 0;
      _lastMotionAtMs = null;
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
    final intensity = _maxScore >= 0.8
        ? 'high'
        : _maxScore >= 0.55
            ? 'medium'
            : 'low';
    final severity = _maxScore > 0.8 && durationMs > 15000
        ? AlertSeverity.warning
        : durationMs >= confirmedCryMs
            ? AlertSeverity.attention
            : AlertSeverity.info;
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
    );
  }
}

class NotificationComposer {
  const NotificationComposer();

  String compose(BabyEventEpisode episode, {AppStrings? strings}) {
    final seconds = (episode.totalCryDurationMs / 1000).round();
    final localized = strings;
    if (localized != null) {
      final networkTier = localized.networkQualityLabel(
        episode.streamQualityTier,
      );
      if (episode.maxCryScore > 0.8 && episode.totalCryDurationMs > 15000) {
        return localized.parentEpisodeHighCryAlert(
          seconds: seconds,
          motionAgo: localized.parentMotionAgo(episode.lastMotionAgoMs()),
          networkTier: networkTier,
        );
      }
      if (episode.resolved && episode.totalCryDurationMs < 5000) {
        return localized.parentEpisodeShortSoundAlert(seconds: seconds);
      }
      return localized.parentEpisodeCryAlert(
        seconds: seconds,
        networkTier: networkTier,
      );
    }
    if (episode.maxCryScore > 0.8 && episode.totalCryDurationMs > 15000) {
      final ago = episode.lastMotionAgoMs();
      final motionText =
          ago == null ? 'hareket yok' : '${(ago / 1000).round()} sn önce';
      return 'Yaklaşık $seconds sn süren güçlü ağlama benzeri ses algılandı. Son kamera hareketi $motionText. Yayın ${episode.streamQualityTier.label} modunda.';
    }
    if (episode.resolved && episode.totalCryDurationMs < 5000) {
      return 'Kısa süreli ses yükselmesi algılandı. Devam ederse tekrar bildirilecek.';
    }
    return 'Yaklaşık $seconds sn süren ağlama benzeri sinyal algılandı. Yayın ${episode.streamQualityTier.label} modunda.';
  }
}
