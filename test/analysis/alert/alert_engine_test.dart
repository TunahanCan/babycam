import 'package:mimicam/analysis/alert/alert_config.dart';
import 'package:mimicam/analysis/alert/alert_engine.dart';
import 'package:mimicam/analysis/alert/alert_event.dart';
import 'package:mimicam/analysis/alert/alert_severity.dart';
import 'package:mimicam/analysis/alert/alert_type.dart';
import 'package:mimicam/analysis/audio/audio_analysis_result.dart';
import 'package:mimicam/analysis/audio/audio_calibration_state.dart';
import 'package:mimicam/analysis/video/motion_analysis_result.dart';
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

      expect(engine.onAudioResult(fakeAudioResult(timestampMs: 1000)), isNotNull);
      expect(engine.onAudioResult(fakeAudioResult(timestampMs: 1500)), isNull);
      expect(engine.onAudioResult(fakeAudioResult(timestampMs: 2000)), isNotNull);
    });

    test('metadata contains basic audio features', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      final event = engine.onAudioResult(fakeAudioResult())!;

      expect(event.metadata.keys, containsAll(<String>[
        'cryScore',
        'rawCryScore',
        'dbfs',
        'ambientDbfs',
        'ambientDeltaDb',
        'cryBandRatio',
        'zeroCrossingRate',
        'spectralCentroid',
        'isCalibrated',
      ]));
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
      expect(engine.onMotionResult(fakeMotionResult(timestampMs: 1500)), isNull);
    });

    test('metadata contains basic motion features', () {
      final engine = AlertEngine();
      addTearDown(engine.dispose);

      final event = engine.onMotionResult(fakeMotionResult())!;

      expect(event.metadata.keys, containsAll(<String>[
        'activeAreaRatio',
        'meanDiff',
        'globalLumaShift',
      ]));
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
}

AudioAnalysisResult fakeAudioResult({
  int timestampMs = 1000,
  double cryScore = 0.8,
  bool isCryLikely = true,
  double dbfs = -30,
  bool isLoudSound = false,
}) =>
    AudioAnalysisResult(
      timestampMs: timestampMs,
      cryScore: cryScore,
      rawCryScore: cryScore,
      isCryLikely: isCryLikely,
      isCalibrated: true,
      calibrationState: AudioCalibrationState.calibrated,
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
      skippedByFrameRateGate: false,
      invalidFrame: false,
      processingTimeMicros: 10,
    );
