import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:mimicam/analysis/alert/alert_severity.dart';
import 'package:mimicam/analysis/alert/episode_notification_aggregator.dart';
import 'package:mimicam/analysis/audio/audio_analysis_result.dart';
import 'package:mimicam/analysis/audio/audio_calibration_state.dart';
import 'package:mimicam/analysis/video/motion_analysis_result.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/l10n/app_strings.dart';

void main() {
  test('LowCostCryScorer enerji ve voiced/harmonic oranlardan skor üretir', () {
    const scorer = LowCostCryScorer();

    final score = scorer.scoreFeatures(
      normalizedEnergy: 1,
      voicedRatio: 0.8,
      harmonicRatio: 0.7,
      consecutiveF0: 0.6,
      durationScore: 0.5,
    );

    expect(score, closeTo(0.78, 0.01));
  });

  test('cry episode suspected -> confirmed ve metadata üretir', () {
    final aggregator = EpisodeBasedNotificationAggregator();

    aggregator.onMotionResult(_motion(timestampMs: 2500));
    expect(
      aggregator.onAudioResult(_audio(timestampMs: 1000)),
      isNull,
    );
    expect(aggregator.state, BabyEventEpisodeState.suspectedCry);
    final episode = aggregator.onAudioResult(
      _audio(timestampMs: 7000),
      streamQualityTier: NetworkQualityTier.weak,
      audioReliable: true,
      videoReliable: false,
    );

    expect(episode, isNotNull);
    expect(episode!.severity, AlertSeverity.attention);
    expect(episode.streamQualityTier, NetworkQualityTier.weak);
    expect(episode.videoReliable, isFalse);
    expect(episode.motionBursts, 1);
    expect(episode.toJson()['event'], 'baby_event');
    expect(episode.toJson()['lastMotionAgoMs'], 4500);
  });

  test('10 saniye sessizlik kısa ses yükselmesi episodeunu resolve eder', () {
    final aggregator = EpisodeBasedNotificationAggregator();
    const composer = NotificationComposer();

    aggregator.onAudioResult(_audio(timestampMs: 1000));
    aggregator.onAudioResult(_audio(timestampMs: 3000));
    final resolved = aggregator.onAudioResult(
      _audio(timestampMs: 14000, active: false),
    );

    expect(resolved, isNotNull);
    expect(resolved!.resolved, isTrue);
    expect(composer.compose(resolved), contains('Kısa süreli ses yükselmesi'));
    expect(aggregator.state, BabyEventEpisodeState.quiet);
  });

  test('NotificationComposer episode mesajını locale ile üretir', () {
    const composer = NotificationComposer();
    const episode = BabyEventEpisode(
      episodeId: 'episode-1',
      startedAtMs: 1000,
      lastUpdatedAtMs: 21000,
      totalCryDurationMs: 18000,
      maxCryScore: 0.9,
      avgCryScore: 0.7,
      motionBursts: 1,
      lastMotionAtMs: 17000,
      streamQualityTier: NetworkQualityTier.weak,
      audioReliable: true,
      videoReliable: false,
      severity: AlertSeverity.warning,
      intensity: 'high',
    );

    final english = composer.compose(
      episode,
      strings: AppStrings(const Locale('en')),
    );
    final french = composer.compose(
      episode,
      strings: AppStrings(const Locale('fr')),
    );

    expect(english, contains('crying'));
    expect(english, contains('Weak'));
    expect(french.toLowerCase(), contains('pleurs'));
    expect(french, isNot(contains('Yayın')));
  });
}

AudioAnalysisResult _audio({
  required int timestampMs,
  bool active = true,
}) =>
    AudioAnalysisResult(
      timestampMs: timestampMs,
      cryScore: active ? 0.85 : 0.05,
      rawCryScore: active ? 0.85 : 0.05,
      isCryLikely: false,
      isCalibrated: true,
      calibrationState: AudioCalibrationState.calibrated,
      rms: active ? 0.2 : 0.01,
      dbfs: active ? -25 : -60,
      peak: active ? 0.3 : 0.02,
      zeroCrossingRate: active ? 0.1 : 0.01,
      ambientDbfs: -55,
      ambientDeltaDb: active ? 30 : 0,
      cryBandRatio: active ? 0.8 : 0.05,
      lowBandRatio: 0.2,
      highBandRatio: 0.2,
      spectralCentroid: 1200,
      spectralEntropy: 0.4,
      spectralFlux: active ? 0.01 : 0.2,
      invalidChunk: false,
      processingTimeMicros: 10,
    );

MotionAnalysisResult _motion({required int timestampMs}) =>
    MotionAnalysisResult(
      timestampMs: timestampMs,
      score: 0.5,
      rawScore: 0.5,
      activeAreaRatio: 0.1,
      meanDiff: 0.08,
      currentMeanLuma: 120,
      backgroundMeanLuma: 100,
      globalLumaShift: 0,
      isMotion: true,
      isGlobalLightChange: false,
      skippedByFrameRateGate: false,
      invalidFrame: false,
      processingTimeMicros: 10,
    );
