import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/analysis/alert/alert_engine.dart';
import 'package:miucam/analysis/audio/audio_analysis_config.dart';
import 'package:miucam/analysis/audio/audio_calibration_state.dart';
import 'package:miucam/analysis/audio/audio_chunk.dart';
import 'package:miucam/analysis/audio/cry_audio_analyzer_v2.dart';
import 'package:miucam/analysis/video/luma_frame.dart';
import 'package:miucam/analysis/video/motion_analyzer_v2.dart';
import 'package:miucam/services/server/media_analysis_coordinator.dart';
import 'package:miucam/services/server/media_analysis_metrics.dart';

void main() {
  test(
      'disabled analysis does no feature work and audio/video enable separately',
      () async {
    var audioEnabled = false;
    var videoEnabled = false;
    final audio = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(calibrationMs: 1000),
    )..startCalibration();
    final metrics = MediaAnalysisMetrics(motionTargetFps: 3);
    final coordinator = MediaAnalysisCoordinator(
      motionAnalyzer: MotionAnalyzerV2(),
      audioAnalyzer: audio,
      alertEngine: AlertEngine(),
      metrics: metrics,
      audioAnalysisEnabled: () => audioEnabled,
      videoAnalysisEnabled: () => videoEnabled,
    );
    addTearDown(coordinator.dispose);
    final pcm = Uint8List(640);
    final luma = Uint8List(640 * 480);
    void feedSecond(int offsetMs) {
      for (var index = 0; index < 50; index++) {
        coordinator.onAudioChunk(AudioChunk(
          pcm16le: pcm,
          sampleRate: 16000,
          channels: 1,
          timestampMs: offsetMs + (index + 1) * 20,
        ));
        coordinator.onCameraFrame(LumaFrame(
          yPlane: luma,
          width: 640,
          height: 480,
          rowStride: 640,
          pixelStride: 1,
          timestampMs: offsetMs + (index + 1) * 20,
        ));
      }
    }

    feedSecond(0);
    expect(metrics.audioWindowsAnalyzed, 0);
    expect(metrics.videoFramesAnalyzed, 0);
    expect(audio.diagnostics()['calibrationAcceptedMs'], 0);
    expect(audio.calibrationState, AudioCalibrationState.calibrating);

    videoEnabled = true;
    feedSecond(1000);
    expect(metrics.videoFramesAnalyzed, 3);
    expect(metrics.audioWindowsAnalyzed, 0);

    videoEnabled = false;
    audioEnabled = true;
    feedSecond(2000);
    expect(metrics.videoFramesAnalyzed, 3);
    expect(metrics.audioWindowsAnalyzed, 1);
    expect(audio.calibrationState, AudioCalibrationState.calibrated);
  });

  test('30 FPS 640x480 input performs only the configured 3 full analyses', () {
    final analyzer = MotionAnalyzerV2();
    final yPlane = Uint8List(640 * 480);
    for (var index = 0; index < yPlane.length; index++) {
      yPlane[index] = 80 + index % 32;
    }

    var analyzed = 0;
    var skipped = 0;
    for (var frameIndex = 0; frameIndex <= 30; frameIndex++) {
      final timestampMs = (frameIndex * 1000 / 30).round();
      final result = analyzer.analyze(
        LumaFrame(
          yPlane: yPlane,
          width: 640,
          height: 480,
          rowStride: 640,
          pixelStride: 1,
          timestampMs: timestampMs,
          monotonicTimestampMs: timestampMs,
        ),
      );
      expect(result.invalidFrame, isFalse);
      if (result.skippedByFrameRateGate) {
        skipped++;
      } else {
        analyzed++;
      }
    }

    expect(analyzed, 3);
    expect(skipped, 28);
    expect(analyzer.diagnostics()['analyzedFrames'], 3);
  });

  test('16 kHz audio stays within four feature passes per second', () {
    final analyzer = CryAudioAnalyzerV2()..restoreCalibratedAmbient(-45);
    final pcm = _generateModulatedPcm16le(durationMs: 20);
    var firstTenSecondWindows = 0;
    var steadyTenSecondWindows = 0;
    for (var chunkIndex = 1; chunkIndex <= 1000; chunkIndex++) {
      final results = analyzer.addChunk(
        AudioChunk(
          pcm16le: pcm,
          sampleRate: 16000,
          channels: 1,
          timestampMs: chunkIndex * 20,
        ),
      );
      expect(results.every((result) => !result.invalidChunk), isTrue);
      if (chunkIndex <= 500) {
        firstTenSecondWindows += results.length;
      } else {
        steadyTenSecondWindows += results.length;
      }
    }

    // The first one-second window delays startup. Twenty-millisecond capture
    // chunks do not divide the 250 ms hop exactly, so allow the safe 12/13
    // chunk scheduling variants while preventing per-chunk feature work.
    expect(firstTenSecondWindows, inInclusiveRange(35, 37));
    expect(steadyTenSecondWindows, inInclusiveRange(38, 40));
    expect(
      analyzer.diagnostics().values.whereType<Iterable<Object?>>(),
      isEmpty,
    );
  });
}

Uint8List _generateModulatedPcm16le({required int durationMs}) {
  const sampleRate = 16000;
  final sampleCount = sampleRate * durationMs ~/ 1000;
  final bytes = ByteData(sampleCount * 2);
  for (var index = 0; index < sampleCount; index++) {
    final time = index / sampleRate;
    final envelope = .65 + .25 * sin(2 * pi * 4 * time);
    final sample = (sin(2 * pi * 800 * time) * envelope * 12000).round();
    bytes.setInt16(index * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
