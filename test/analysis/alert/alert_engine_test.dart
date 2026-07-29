import 'package:miucam/analysis/alert/alert_config.dart';
import 'package:miucam/analysis/alert/alert_engine.dart';
import 'package:miucam/analysis/alert/alert_event.dart';
import 'package:miucam/analysis/alert/alert_severity.dart';
import 'package:miucam/analysis/alert/alert_type.dart';
import 'package:miucam/analysis/alert/episode_notification_aggregator.dart';
import 'package:miucam/analysis/audio/audio_analysis_result.dart';
import 'package:miucam/analysis/audio/audio_calibration_state.dart';
import 'package:miucam/analysis/video/motion_analysis_result.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlertEngine cry alerts', () {
    test('isCryLikely false produces no event', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      expect(engine.onAudioResult(fakeAudioResult(isCryLikely: false)), isNull);
    });

    test('isCryLikely true over threshold produces cry event', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      final event = engine.onAudioResult(fakeAudioResult());

      expect(event, isNotNull);
      expect(event!.type, AlertType.cryDetected);
      expect(event.severity, AlertSeverity.warning);
      expect(event.message, 'Ağlama algılandı');
      expect(event.id, 'cryDetected-1000-0');
    });

    test('cooldown suppresses second cry and permits later cry', () {
      final engine = AlertEngine(
        config: const AlertConfig(cryCooldownMs: 1000),
      );
      addTearDown(engine.dispose);

      expect(
          engine.onAudioResult(fakeAudioResult(timestampMs: 1000)), isNotNull);
      expect(engine.onAudioResult(fakeAudioResult(timestampMs: 1500)), isNull);
      expect(
          engine.onAudioResult(fakeAudioResult(timestampMs: 2000)), isNotNull);
    });

    test(
        'cooldown bitince devam eden doğrulanmış episode tekrar değerlendirilir',
        () {
      final engine = AlertEngine(
        config: const AlertConfig(cryCooldownMs: 5000),
        episodeAggregator: EpisodeBasedNotificationAggregator(
          suspectedCryMs: 500,
          confirmedCryMs: 1000,
          maxActiveGapMs: 600,
        ),
      );
      addTearDown(engine.dispose);
      final emittedAt = <int>[];

      for (final timestampMs in [1000, 1500, 2000, 4000, 4500, 5000]) {
        final event =
            engine.onAudioResult(fakeAudioResult(timestampMs: timestampMs));
        if (event != null) emittedAt.add(event.timestampMs);
      }
      expect(emittedAt, [2000]);

      for (final timestampMs in [5500, 6000, 6500, 7000]) {
        final event =
            engine.onAudioResult(fakeAudioResult(timestampMs: timestampMs));
        if (event != null) emittedAt.add(event.timestampMs);
      }

      expect(emittedAt, [2000, 7000]);
    });

    test('metadata contains basic audio features', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      final event = engine.onAudioResult(fakeAudioResult())!;

      expect(
          event.metadata.keys,
          containsAll(<String>[
            'cryScore',
            'rawCryScore',
            'dbfs',
            'ambientDbfs',
            'ambientDeltaDb',
            'cryBandRatio',
            'zeroCrossingRate',
            'spectralCentroid',
            'isCalibrated',
            'confidencePercent',
            'cryBandPercent',
            'suggestedChecks',
          ]));
    });

    test('kalibrasyon tamamlanmadan loud sound bildirimi üretmez', () {
      final engine = AlertEngine(
        config: const AlertConfig(emitLoudSoundAlerts: true),
      );
      addTearDown(engine.dispose);

      final event = engine.onAudioResult(
        fakeAudioResult(
          isCryLikely: false,
          isLoudSound: true,
          isCalibrated: false,
          calibrationState: AudioCalibrationState.calibrating,
        ),
      );

      expect(event, isNull);
    });

    test('localized parent message explains evidence without diagnosis', () {
      final engine = AlertEngine(strings: AppStrings(const Locale('zh')));
      addTearDown(engine.dispose);

      final event = engine.onAudioResult(fakeAudioResult())!;

      expect(event.message, contains('宝宝可能在哭'));
      expect(event.message, contains('请平静查看'));
      expect(event.message, isNot(contains('诊断')));
      expect(event.metadata['confidencePercent'], 80);
      expect(event.metadata['cryBandPercent'], 60);
      expect(event.metadata['suggestedChecks'], contains('diaper'));
    });

    test('dispose makes future handling a safe no-op', () async {
      final engine = AlertEngine();
      await engine.dispose();

      expect(() => engine.onAudioResult(fakeAudioResult()), returnsNormally);
      expect(engine.onAudioResult(fakeAudioResult()), isNull);
    });
  });

  group('AlertEngine motion alerts', () {
    test('isMotion false produces no event', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      expect(engine.onMotionResult(fakeMotionResult(isMotion: false)), isNull);
    });

    test('skipped or invalid video frame produces no event', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      expect(
        engine.onMotionResult(fakeMotionResult(skippedByFrameRateGate: true)),
        isNull,
      );
      expect(
        engine.onMotionResult(fakeMotionResult(invalidFrame: true)),
        isNull,
      );
    });

    test('unreliable media does not create a parent notification', () {
      final engine = AlertEngine(
        audioReliableProvider: () => false,
        videoReliableProvider: () => false,
      );
      addTearDown(engine.dispose);

      expect(engine.onAudioResult(fakeAudioResult()), isNull);
      expect(engine.onMotionResult(fakeMotionResult()), isNull);
    });

    test('isMotion true over threshold produces motion event', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      final event = engine.onMotionResult(fakeMotionResult());

      expect(event, isNotNull);
      expect(event!.type, AlertType.motionDetected);
      expect(event.message, 'Hareket algılandı');
    });

    test('global light change does not become motion event', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      expect(
        engine.onMotionResult(fakeMotionResult(isGlobalLightChange: true)),
        isNull,
      );
    });

    test('global light change info can be emitted explicitly', () {
      final engine = AlertEngine(
        config: const AlertConfig(emitGlobalLightChangeInfo: true),
      );
      addTearDown(engine.dispose);

      final event = engine.onMotionResult(
        fakeMotionResult(isGlobalLightChange: true),
      );

      expect(event, isNotNull);
      expect(event!.type, AlertType.globalLightChange);
      expect(event.severity, AlertSeverity.info);
    });

    test('cooldown suppresses second motion event', () {
      final engine = AlertEngine(
        config: const AlertConfig(motionCooldownMs: 1000),
      );
      addTearDown(engine.dispose);

      expect(
        engine.onMotionResult(fakeMotionResult(timestampMs: 1000)),
        isNotNull,
      );
      expect(
          engine.onMotionResult(fakeMotionResult(timestampMs: 1500)), isNull);
    });

    test('metadata contains basic motion features', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      final event = engine.onMotionResult(fakeMotionResult())!;

      expect(
          event.metadata.keys,
          containsAll(<String>[
            'activeAreaRatio',
            'activeAreaPercent',
            'scorePercent',
            'meanDiff',
            'globalLumaShift',
          ]));
    });

    test('localized motion message includes area and practical check', () {
      final engine = AlertEngine(strings: AppStrings(const Locale('tr')));
      addTearDown(engine.dispose);

      final event = engine.onMotionResult(fakeMotionResult())!;

      expect(event.message, contains('Görüntünün yaklaşık %10'));
      expect(event.message, contains('rahat pozisyonda'));
      expect(event.metadata['activeAreaPercent'], 10);
    });

    test('mesajlar algılamayı kesin teşhis gibi sunmaz', () {
      final engine = AlertEngine(strings: AppStrings(const Locale('tr')));
      addTearDown(engine.dispose);

      final event = engine.onAudioResult(
        fakeAudioResult(timestampMs: 1000, isCryLikely: true),
      )!;

      expect(event.message, contains('olabilir'));
      expect(event.message, isNot(contains('doğrulandı')));
    });
  });

  group('AlertEngine stream', () {
    test('alerts stream publishes emitted events', () async {
      final engine = AlertEngine();
      addTearDown(engine.dispose);
      final firstEvent = expectLater(
        engine.alerts,
        emits(
          isA<AlertEvent>().having(
            (event) => event.type,
            'type',
            AlertType.cryDetected,
          ),
        ),
      );

      engine.onAudioResult(fakeAudioResult());

      await firstEvent;
    });

    test('broadcast stream supports multiple listeners', () async {
      final engine = AlertEngine();
      addTearDown(engine.dispose);
      final listener1 = expectLater(engine.alerts, emits(isA<AlertEvent>()));
      final listener2 = expectLater(engine.alerts, emits(isA<AlertEvent>()));

      engine.onMotionResult(fakeMotionResult());

      await listener1;
      await listener2;
    });

    test('dispose closes stream', () async {
      final engine = AlertEngine();
      final done = expectLater(engine.alerts, emitsDone);

      await engine.dispose();

      await done;
    });
  });

  test('drainPending and diagnostics expose emitted alerts', () {
    final engine = AlertEngine();
    addTearDown(engine.dispose);

    engine.onAudioResult(fakeAudioResult());

    expect(engine.drainPending(), hasLength(1));
    expect(engine.drainPending(), isEmpty);
    expect(engine.diagnostics()['alertsProduced'], 1);
    expect(engine.diagnostics()['lastAlertType'], 'cryDetected');
  });

  test('pending buffer keeps only recent alerts and stays bounded', () {
    final engine = AlertEngine(
      config: const AlertConfig(motionCooldownMs: 0),
    );
    addTearDown(engine.dispose);
    const overflow = 10;

    for (var index = 0;
        index < AlertEngine.maxPendingAlerts + overflow;
        index++) {
      expect(
        engine.onMotionResult(fakeMotionResult(timestampMs: 1000 + index)),
        isNotNull,
      );
    }

    final diagnostics = engine.diagnostics();
    final pending = engine.drainPending();
    expect(pending, hasLength(AlertEngine.maxPendingAlerts));
    expect(pending.first.timestampMs, 1000 + overflow);
    expect(
      diagnostics['alertsProduced'],
      AlertEngine.maxPendingAlerts + overflow,
    );
    expect(diagnostics['pendingAlerts'], AlertEngine.maxPendingAlerts);
    expect(diagnostics['pendingAlertsDropped'], overflow);
    expect(engine.diagnostics()['pendingAlerts'], 0);
  });
}

AudioAnalysisResult fakeAudioResult({
  int timestampMs = 1000,
  double cryScore = 0.8,
  bool isCryLikely = true,
  bool isCalibrated = true,
  AudioCalibrationState calibrationState = AudioCalibrationState.calibrated,
  double dbfs = -30,
  bool isLoudSound = false,
}) =>
    AudioAnalysisResult(
      timestampMs: timestampMs,
      cryScore: cryScore,
      rawCryScore: cryScore,
      isCryLikely: isCryLikely,
      isCalibrated: isCalibrated,
      calibrationState: calibrationState,
      rms: 0.1,
      dbfs: dbfs,
      peak: 0.2,
      zeroCrossingRate: 0.3,
      ambientDbfs: -45,
      ambientDeltaDb: 15,
      cryBandRatio: 0.6,
      lowBandRatio: 0.2,
      highBandRatio: 0.2,
      spectralCentroid: 1200,
      spectralEntropy: 0.4,
      spectralFlux: 0.5,
      invalidChunk: false,
      processingTimeMicros: 10,
      isLoudSound: isLoudSound,
    );

MotionAnalysisResult fakeMotionResult({
  int timestampMs = 1000,
  double score = 0.5,
  bool isMotion = true,
  bool isGlobalLightChange = false,
  bool skippedByFrameRateGate = false,
  bool invalidFrame = false,
}) =>
    MotionAnalysisResult(
      timestampMs: timestampMs,
      score: score,
      rawScore: score,
      activeAreaRatio: 0.1,
      meanDiff: 12,
      currentMeanLuma: 100,
      backgroundMeanLuma: 90,
      globalLumaShift: 10,
      isMotion: isMotion,
      isGlobalLightChange: isGlobalLightChange,
      skippedByFrameRateGate: skippedByFrameRateGate,
      invalidFrame: invalidFrame,
      processingTimeMicros: 10,
    );
