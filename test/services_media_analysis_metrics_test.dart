import 'package:flutter_test/flutter_test.dart';

import 'package:mimicam/analysis/alert/alert_event.dart';
import 'package:mimicam/analysis/alert/alert_severity.dart';
import 'package:mimicam/analysis/alert/alert_type.dart';
import 'package:mimicam/analysis/audio/audio_analysis_result.dart';
import 'package:mimicam/analysis/audio/audio_calibration_state.dart';
import 'package:mimicam/analysis/video/motion_analysis_result.dart';
import 'package:mimicam/services/server/media_analysis_metrics.dart';

void main() {
  group('MediaAnalysisMetrics', () {
    test('records motion counters and EMA', () {
      final metrics = MediaAnalysisMetrics(motionTargetFps: 3);

      metrics.recordVideoFrameReceived();
      metrics.recordMotion(_motionResult(score: 0.5, processingTimeMicros: 1000));
      metrics.recordMotion(_motionResult(score: 0.7, processingTimeMicros: 3000));
      metrics.recordMotionSkippedByFpsGate();
      metrics.recordMotionDroppedBecauseBusy();

      final json = metrics.toJson();
      final motion = json['motion']! as Map<String, Object?>;
      expect(motion['targetFps'], 3);
      expect(motion['framesReceived'], 1);
      expect(motion['framesAnalyzed'], 2);
      expect(motion['framesSkippedByFpsGate'], 1);
      expect(motion['framesDroppedBecauseBusy'], 1);
      expect(motion['lastScore'], 0.7);
      expect(motion['processingAvgMs'], closeTo(1.2, 0.001));
    });

    test('records audio counters, alert state, and reset', () {
      final metrics = MediaAnalysisMetrics(motionTargetFps: 3);

      metrics.recordAudioChunkReceived();
      metrics.recordAudio(_audioResult(score: 0.4, processingTimeMicros: 2000));
      metrics.recordAudio(_audioResult(score: 0.8, processingTimeMicros: 4000));
      metrics.recordAudioChunkDropped();
      metrics.recordAlert(const AlertEvent(
        id: 'cry-1',
        type: AlertType.cryDetected,
        severity: AlertSeverity.warning,
        message: 'Ağlama algılandı',
        score: 0.8,
        timestampMs: 42,
      ));

      var json = metrics.toJson();
      final audio = json['audio']! as Map<String, Object?>;
      final alerts = json['alerts']! as Map<String, Object?>;
      expect(audio['chunksReceived'], 1);
      expect(audio['windowsAnalyzed'], 2);
      expect(audio['chunksDropped'], 1);
      expect(audio['lastCryScore'], 0.8);
      expect(audio['processingAvgMs'], closeTo(2.2, 0.001));
      expect(alerts['alertsProduced'], 1);
      expect(alerts['lastAlertType'], 'cryDetected');
      expect(alerts['lastAlertAt'], 42);

      metrics.reset();
      json = metrics.toJson();
      expect((json['alerts']! as Map<String, Object?>)['alertsProduced'], 0);
      expect((json['audio']! as Map<String, Object?>)['windowsAnalyzed'], 0);
    });
  });
}

MotionAnalysisResult _motionResult({required double score, required int processingTimeMicros}) => MotionAnalysisResult(
      timestampMs: 100,
      score: score,
      rawScore: score,
      activeAreaRatio: score,
      meanDiff: 10,
      currentMeanLuma: 100,
      backgroundMeanLuma: 90,
      globalLumaShift: 0,
      isMotion: score > 0.6,
      isGlobalLightChange: false,
      skippedByFrameRateGate: false,
      invalidFrame: false,
      processingTimeMicros: processingTimeMicros,
    );

AudioAnalysisResult _audioResult({required double score, required int processingTimeMicros}) => AudioAnalysisResult(
      timestampMs: 200,
      cryScore: score,
      rawCryScore: score,
      isCryLikely: score > 0.6,
      isCalibrated: true,
      calibrationState: AudioCalibrationState.calibrated,
      rms: 0.1,
      dbfs: -20,
      peak: 0.2,
      zeroCrossingRate: 0.1,
      ambientDbfs: -50,
      ambientDeltaDb: 30,
      cryBandRatio: 0.5,
      lowBandRatio: 0.2,
      highBandRatio: 0.3,
      spectralCentroid: 1000,
      spectralEntropy: 0.5,
      spectralFlux: 0.1,
      invalidChunk: false,
      processingTimeMicros: processingTimeMicros,
    );
