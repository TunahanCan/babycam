import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/analysis/alert/alert_config.dart';
import 'package:miucam/analysis/alert/alert_engine.dart';
import 'package:miucam/analysis/alert/alert_event.dart';
import 'package:miucam/analysis/alert/episode_notification_aggregator.dart';
import 'package:miucam/analysis/audio/audio_analysis_config.dart';
import 'package:miucam/analysis/audio/audio_chunk.dart';
import 'package:miucam/analysis/audio/cry_audio_analyzer_v2.dart';
import 'package:miucam/analysis/video/luma_frame.dart';
import 'package:miucam/analysis/video/motion_analysis_config.dart';
import 'package:miucam/analysis/video/motion_analyzer_v2.dart';
import 'package:miucam/services/server/media_analysis_coordinator.dart';
import 'package:miucam/services/server/media_analysis_metrics.dart';

import '../../analysis/audio/test_audio_generators.dart';

void main() {
  test(
      'son kullanıcı zinciri fan, sabit ton ve kısa transienti susturup sürekli cry sinyalini bir kez bildirir',
      () async {
    const sampleRate = 16000;
    final audioAnalyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        sampleRate: sampleRate,
        calibrationMs: 1000,
        cryOnThreshold: .50,
        cryOffThreshold: .35,
        minCryDurationMs: 0,
        smoothingAlpha: .6,
        ambientUpdateAlpha: .05,
      ),
    )..startCalibration(timestampMs: 0);
    final alertEngine = AlertEngine(
      config: const AlertConfig(cryCooldownMs: 60000),
      episodeAggregator: EpisodeBasedNotificationAggregator(
        cryThreshold: .50,
        suspectedCryMs: 750,
        confirmedCryMs: 1500,
      ),
    );
    final coordinator = MediaAnalysisCoordinator(
      motionAnalyzer: MotionAnalyzerV2(),
      audioAnalyzer: audioAnalyzer,
      alertEngine: alertEngine,
      metrics: MediaAnalysisMetrics(motionTargetFps: 3),
    );
    addTearDown(coordinator.dispose);
    final alerts = <AlertEvent>[];
    final subscription = coordinator.alerts.listen(alerts.add);
    addTearDown(subscription.cancel);

    coordinator.onAudioChunk(AudioChunk(
      pcm16le: generateSinePcm16le(
        sampleRate: sampleRate,
        frequencyHz: 440,
        durationMs: 1000,
        amplitude: 0,
      ),
      sampleRate: sampleRate,
      channels: 1,
      timestampMs: 1000,
    ));
    coordinator.onAudioChunk(AudioChunk(
      pcm16le: generateNoisePcm16le(
        sampleRate: sampleRate,
        durationMs: 12000,
        amplitude: .03,
        seed: 11,
      ),
      sampleRate: sampleRate,
      channels: 1,
      timestampMs: 13000,
    ));
    coordinator.onAudioChunk(AudioChunk(
      pcm16le: generateSinePcm16le(
        sampleRate: sampleRate,
        frequencyHz: 600,
        durationMs: 4000,
        amplitude: .8,
      ),
      sampleRate: sampleRate,
      channels: 1,
      timestampMs: 17000,
    ));
    coordinator.onAudioChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sampleRate,
        durationMs: 500,
        amplitude: .9,
      ),
      sampleRate: sampleRate,
      channels: 1,
      timestampMs: 17500,
    ));
    coordinator.onAudioChunk(AudioChunk(
      pcm16le: generateNoisePcm16le(
        sampleRate: sampleRate,
        durationMs: 12000,
        amplitude: .03,
        seed: 12,
      ),
      sampleRate: sampleRate,
      channels: 1,
      timestampMs: 29500,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(alerts, isEmpty);

    coordinator.onAudioChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sampleRate,
        durationMs: 4000,
        amplitude: .8,
      ),
      sampleRate: sampleRate,
      channels: 1,
      timestampMs: 33500,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(alerts, hasLength(1));
    expect(alerts.single.type.name, 'cryDetected');
    expect(alerts.single.metadata['confirmed'], isTrue);
    expect(alerts.single.metadata['activeEvidenceRatio'],
        greaterThanOrEqualTo(.7));
  });

  test(
      'kamera zinciri startup ve ışık değişimini susturup sürekli lokal hareketi bir kez bildirir',
      () async {
    const width = 80;
    const height = 60;
    final alertEngine = AlertEngine(
      config: const AlertConfig(
        motionAlertThreshold: .25,
        motionCooldownMs: 60000,
      ),
    );
    final coordinator = MediaAnalysisCoordinator(
      motionAnalyzer: MotionAnalyzerV2(
        config: const MotionAnalysisConfig(
          downsampleWidth: 40,
          downsampleHeight: 30,
          analysisFps: 30,
          motionOnThreshold: .25,
          motionOffThreshold: .12,
          minMotionDurationMs: 500,
          smoothingAlpha: .6,
          stableBackgroundAlpha: .01,
          initializationAlpha: .05,
        ),
      ),
      audioAnalyzer: CryAudioAnalyzerV2(),
      alertEngine: alertEngine,
      metrics: MediaAnalysisMetrics(motionTargetFps: 30),
    );
    addTearDown(coordinator.dispose);
    final alerts = <AlertEvent>[];
    final subscription = coordinator.alerts.listen(alerts.add);
    addTearDown(subscription.cancel);

    for (var index = 0; index < 5; index++) {
      coordinator.onCameraFrame(
        _frame(_uniformLuma(width, height, 80), width, height, index * 100),
      );
    }
    coordinator.onCameraFrame(
      _frame(_uniformLuma(width, height, 160), width, height, 600),
    );
    coordinator.onCameraFrame(
      _frame(_uniformLuma(width, height, 160), width, height, 900),
    );
    await Future<void>.delayed(Duration.zero);
    expect(alerts, isEmpty);

    for (final timestampMs in [1200, 1500, 1800]) {
      final data = _uniformLuma(width, height, 160);
      _drawRect(data, width, height, 10, 10, 30, 20, 70);
      coordinator.onCameraFrame(
        _frame(data, width, height, timestampMs),
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(alerts, hasLength(1));
    expect(alerts.single.type.name, 'motionDetected');
  });
}

Uint8List _uniformLuma(int width, int height, int value) =>
    Uint8List.fromList(List<int>.filled(width * height, value));

void _drawRect(
  Uint8List frame,
  int width,
  int height,
  int left,
  int top,
  int rectWidth,
  int rectHeight,
  int value,
) {
  for (var y = top; y < top + rectHeight && y < height; y++) {
    for (var x = left; x < left + rectWidth && x < width; x++) {
      frame[y * width + x] = value;
    }
  }
}

LumaFrame _frame(
  Uint8List data,
  int width,
  int height,
  int timestampMs,
) =>
    LumaFrame(
      yPlane: data,
      width: width,
      height: height,
      rowStride: width,
      pixelStride: 1,
      timestampMs: timestampMs,
      monotonicTimestampMs: timestampMs,
    );
