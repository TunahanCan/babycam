import '../../core/media/adaptive_media_profile.dart';
import '../../l10n/app_strings.dart';
import '../audio/audio_analysis_result.dart';
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

class LowCostCryScorer {
  const LowCostCryScorer();

  double scoreFeatures({
    required double normalizedEnergy,
    required double voicedRatio,
    required double harmonicRatio,
    required double consecutiveF0,
    required double durationScore,
  }) {
    return (0.30 * normalizedEnergy +
            0.25 * voicedRatio +
            0.20 * harmonicRatio +
            0.15 * consecutiveF0 +
            0.10 * durationScore)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double score(AudioAnalysisResult result, {required int cryDurationMs}) {
    final normalizedEnergy =
        (result.ambientDeltaDb / 24).clamp(0.0, 1.0).toDouble();
    final voicedRatio =
        _trapezoid(result.zeroCrossingRate, 0.02, 0.05, 0.22, 0.34);
    final harmonicRatio = result.cryBandRatio.clamp(0.0, 1.0).toDouble();
    final consecutiveF0 = result.spectralFlux < 0.02 ? harmonicRatio : 0.0;
    final durationScore = (cryDurationMs / 15000).clamp(0.0, 1.0).toDouble();
    return scoreFeatures(
      normalizedEnergy: normalizedEnergy,
      voicedRatio: voicedRatio,
      harmonicRatio: harmonicRatio,
      consecutiveF0: consecutiveF0,
      durationScore: durationScore,
    );
  }

  double _trapezoid(double value, double a, double b, double c, double d) {
    if (value <= a || value >= d) return 0;
    if (value >= b && value <= c) return 1;
    if (value < b) return ((value - a) / (b - a)).clamp(0.0, 1.0).toDouble();
    return ((d - value) / (d - c)).clamp(0.0, 1.0).toDouble();
  }
}

class EpisodeBasedNotificationAggregator {
  EpisodeBasedNotificationAggregator({
    this.cryThreshold = 0.4,
    this.suspectedCryMs = 2000,
    this.confirmedCryMs = 5000,
    this.resolveQuietMs = 10000,
    LowCostCryScorer scorer = const LowCostCryScorer(),
  }) : _scorer = scorer;

  final double cryThreshold;
  final int suspectedCryMs;
  final int confirmedCryMs;
  final int resolveQuietMs;
  final LowCostCryScorer _scorer;

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
  bool _confirmedEmitted = false;

  BabyEventEpisodeState get state => _state;

  void onMotionResult(MotionAnalysisResult result) {
    if (!result.isMotion) return;
    _motionBursts++;
    _lastMotionAtMs = result.timestampMs;
  }

  BabyEventEpisode? onAudioResult(
    AudioAnalysisResult result, {
    NetworkQualityTier streamQualityTier = NetworkQualityTier.unknown,
    bool audioReliable = true,
    bool videoReliable = true,
  }) {
    final nowMs = result.timestampMs;
    final durationMs =
        _episodeStartedAtMs == null ? 0 : nowMs - _episodeStartedAtMs!;
    final cryScore = _scorer.score(result, cryDurationMs: durationMs);
    final active = cryScore > cryThreshold || result.isCryLikely;

    if (active) {
      _startIfNeeded(nowMs);
      if (_lastCryAtMs != null && nowMs >= _lastCryAtMs!) {
        _totalCryDurationMs += nowMs - _lastCryAtMs!;
      }
      _lastCryAtMs = nowMs;
      _sampleCount++;
      _scoreSum += cryScore;
      if (cryScore > _maxScore) _maxScore = cryScore;
      final activeDuration = nowMs - _episodeStartedAtMs!;
      if (activeDuration >= confirmedCryMs) {
        _state = _confirmedEmitted
            ? BabyEventEpisodeState.ongoingCry
            : BabyEventEpisodeState.confirmedCry;
        if (!_confirmedEmitted) {
          _confirmedEmitted = true;
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
    _confirmedEmitted = false;
  }

  void _startIfNeeded(int nowMs) {
    if (_episodeStartedAtMs != null) return;
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
      return 'Yaklaşık $seconds sn süren yüksek ağlama algılandı. Son hareket $motionText. Yayın ${episode.streamQualityTier.label} modunda.';
    }
    if (episode.resolved && episode.totalCryDurationMs < 5000) {
      return 'Kısa süreli ses yükselmesi algılandı. Devam ederse tekrar bildirilecek.';
    }
    return 'Yaklaşık $seconds sn süren ağlama sinyali algılandı. Yayın ${episode.streamQualityTier.label} modunda.';
  }
}
