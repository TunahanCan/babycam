import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:miucam/analysis/alert/alert_severity.dart';
import 'package:miucam/analysis/alert/episode_notification_aggregator.dart';
import 'package:miucam/analysis/audio/audio_analysis_result.dart';
import 'package:miucam/analysis/audio/audio_calibration_state.dart';
import 'package:miucam/analysis/video/motion_analysis_result.dart';
import 'package:miucam/core/media/adaptive_media_profile.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  test('cry episode suspected -> confirmed ve metadata üretir', () {
    final aggregator = EpisodeBasedNotificationAggregator();

    aggregator.onMotionResult(_motion(timestampMs: 2500));
    BabyEventEpisode? episode;
    for (var timestampMs = 1000; timestampMs <= 6000; timestampMs += 1000) {
      episode = aggregator.onAudioResult(
            _audio(timestampMs: timestampMs),
            streamQualityTier: NetworkQualityTier.weak,
            audioReliable: true,
            videoReliable: false,
          ) ??
          episode;
    }

    expect(episode, isNotNull);
    expect(episode!.severity, AlertSeverity.attention);
    expect(episode.streamQualityTier, NetworkQualityTier.weak);
    expect(episode.videoReliable, isFalse);
    expect(episode.motionBursts, 1);
    expect(episode.confirmed, isTrue);
    expect(episode.activeEvidenceRatio, 1);
    expect(episode.toJson()['event'], 'baby_event');
    expect(episode.toJson()['lastMotionAgoMs'], 3500);
  });

  test('10 saniye sessizlik kısa ses yükselmesi episodeunu resolve eder', () {
    final aggregator = EpisodeBasedNotificationAggregator();
    const composer = NotificationComposer();

    aggregator.onAudioResult(_audio(timestampMs: 1000));
    aggregator.onAudioResult(_audio(timestampMs: 2000));
    aggregator.onAudioResult(_audio(timestampMs: 3000));
    final resolved = aggregator.onAudioResult(
      _audio(timestampMs: 14000, active: false),
    );

    expect(resolved, isNotNull);
    expect(resolved!.resolved, isTrue);
    expect(composer.compose(resolved), contains('Kısa süreli ses yükselmesi'));
    expect(aggregator.state, BabyEventEpisodeState.quiet);
  });

  test('eski kamera hareketi yeni ses episodeuna taşınmaz', () {
    final aggregator = EpisodeBasedNotificationAggregator();

    aggregator.onMotionResult(_motion(timestampMs: 1000));
    BabyEventEpisode? confirmed;
    for (var timestampMs = 10000; timestampMs <= 15000; timestampMs += 1000) {
      confirmed = aggregator.onAudioResult(_audio(timestampMs: timestampMs)) ??
          confirmed;
    }

    expect(confirmed, isNotNull);
    expect(confirmed!.motionBursts, 0);
    expect(confirmed.lastMotionAtMs, isNull);
  });

  test('kalibrasyon tamamlanmadan ses episodeu başlatılmaz', () {
    final aggregator = EpisodeBasedNotificationAggregator();
    final result = _audio(
      timestampMs: 1000,
      isCalibrated: false,
      calibrationState: AudioCalibrationState.calibrating,
    );

    expect(aggregator.onAudioResult(result), isNull);
    expect(aggregator.state, BabyEventEpisodeState.quiet);
  });

  test('clipped PCM önceki cry adayını temizler', () {
    final aggregator = EpisodeBasedNotificationAggregator(
      suspectedCryMs: 500,
      confirmedCryMs: 1500,
    );

    aggregator.onAudioResult(_audio(timestampMs: 1000));
    aggregator.onAudioResult(_audio(timestampMs: 1500));
    aggregator.onAudioResult(_audio(timestampMs: 2000, isClipped: true));

    expect(aggregator.state, BabyEventEpisodeState.quiet);
  });

  test('uzun audio paket boşluğu iki sesi tek episode gibi birleştirmez', () {
    final aggregator = EpisodeBasedNotificationAggregator(
      confirmedCryMs: 2000,
      suspectedCryMs: 1000,
      maxActiveGapMs: 500,
    );

    expect(
      aggregator.onAudioResult(_audio(timestampMs: 1000)),
      isNull,
    );
    expect(
      aggregator.onAudioResult(_audio(timestampMs: 3000)),
      isNull,
    );

    expect(aggregator.state, BabyEventEpisodeState.suspectedCry);
  });

  test('aralıklı seslerin sessiz araları aktif ağlama süresine eklenmez', () {
    final aggregator = EpisodeBasedNotificationAggregator(
      suspectedCryMs: 500,
      confirmedCryMs: 1000,
      maxActiveGapMs: 1500,
      minActiveEvidenceRatio: .70,
    );
    BabyEventEpisode? episode;

    for (var timestampMs = 1000; timestampMs <= 4000; timestampMs += 250) {
      final active = ((timestampMs - 1000) ~/ 250).isEven;
      episode = aggregator.onAudioResult(
            _audio(timestampMs: timestampMs, active: active),
          ) ??
          episode;
    }

    expect(episode, isNull);
    expect(aggregator.state, isNot(BabyEventEpisodeState.confirmedCry));
    expect(aggregator.state, isNot(BabyEventEpisodeState.ongoingCry));
  });

  test('ekran profilinden gelen eşik ve süre bildirim kararını değiştirir', () {
    final sensitive = EpisodeBasedNotificationAggregator(
      cryThreshold: .50,
      suspectedCryMs: 500,
      confirmedCryMs: 1000,
    );
    final fewerAlerts = EpisodeBasedNotificationAggregator(
      cryThreshold: .78,
      suspectedCryMs: 1250,
      confirmedCryMs: 2500,
    );

    BabyEventEpisode? sensitiveEvent;
    BabyEventEpisode? fewerAlertsEvent;
    for (var timestampMs = 1000; timestampMs <= 2000; timestampMs += 500) {
      final sample = _audio(
        timestampMs: timestampMs,
        cryScore: .60,
        isCryLikely: false,
      );
      sensitiveEvent = sensitive.onAudioResult(sample) ?? sensitiveEvent;
      fewerAlertsEvent = fewerAlerts.onAudioResult(sample) ?? fewerAlertsEvent;
    }

    expect(sensitiveEvent, isNotNull);
    expect(fewerAlertsEvent, isNull);
  });

  test('self-audio kesintisi önceki cry adayını sonraki sesle birleştirmez',
      () {
    final aggregator = EpisodeBasedNotificationAggregator(
      cryThreshold: .50,
      suspectedCryMs: 500,
      confirmedCryMs: 1000,
    );

    expect(aggregator.onAudioResult(_audio(timestampMs: 1000)), isNull);
    expect(aggregator.onAudioResult(_audio(timestampMs: 1500)), isNull);
    aggregator.reset();
    expect(aggregator.onAudioResult(_audio(timestampMs: 2000)), isNull);
    expect(aggregator.onAudioResult(_audio(timestampMs: 2500)), isNull);
    expect(aggregator.state, BabyEventEpisodeState.suspectedCry);
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

    expect(english, contains('cry-like'));
    expect(english, contains('Weak'));
    expect(french.toLowerCase(), contains('pleurs'));
    expect(french, isNot(contains('Yayın')));
  });
}

AudioAnalysisResult _audio({
  required int timestampMs,
  bool active = true,
  double? cryScore,
  bool isCryLikely = false,
  bool isCalibrated = true,
  bool isClipped = false,
  AudioCalibrationState calibrationState = AudioCalibrationState.calibrated,
}) =>
    AudioAnalysisResult(
      timestampMs: timestampMs,
      cryScore: cryScore ?? (active ? 0.85 : 0.05),
      rawCryScore: cryScore ?? (active ? 0.85 : 0.05),
      isCryLikely: isCryLikely,
      isCalibrated: isCalibrated,
      calibrationState: calibrationState,
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
      isClipped: isClipped,
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
