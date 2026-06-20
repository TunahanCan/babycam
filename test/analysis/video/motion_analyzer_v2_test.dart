import 'dart:typed_data';

import 'package:mimicam/analysis/video/luma_frame.dart';
import 'package:mimicam/analysis/video/motion_analysis_config.dart';
import 'package:mimicam/analysis/video/motion_analysis_result.dart';
import 'package:mimicam/analysis/video/motion_analyzer_v2.dart';
import 'package:mimicam/analysis/video/normalized_rect.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List makeLumaFrame(
        {required int width, required int height, required int value}) =>
    Uint8List.fromList(List.filled(width * height, value));

void drawRectOnLuma(Uint8List frame, int width, int height, int left, int top,
    int rectWidth, int rectHeight, int value) {
  for (var y = top; y < top + rectHeight && y < height; y++) {
    for (var x = left; x < left + rectWidth && x < width; x++) {
      if (x >= 0 && y >= 0) frame[y * width + x] = value;
    }
  }
}

LumaFrame makeFrame(Uint8List data, int width, int height, int timestampMs) =>
    LumaFrame(
      yPlane: data,
      width: width,
      height: height,
      rowStride: width,
      pixelStride: 1,
      timestampMs: timestampMs,
    );

MotionAnalysisConfig fastConfig({NormalizedRect? roi}) => MotionAnalysisConfig(
      downsampleWidth: 40,
      downsampleHeight: 30,
      analysisFps: 30,
      motionOnThreshold: 0.25,
      motionOffThreshold: 0.12,
      minMotionDurationMs: 500,
      smoothingAlpha: 0.6,
      stableBackgroundAlpha: 0.01,
      initializationAlpha: 0.05,
      roi: roi,
    );

void prime(MotionAnalyzerV2 analyzer, int width, int height) {
  for (var i = 0; i < 5; i++) {
    analyzer.analyze(makeFrame(
        makeLumaFrame(width: width, height: height, value: 80),
        width,
        height,
        i * 100));
  }
}

void main() {
  const width = 80;
  const height = 60;

  test('static frame has low score and no motion', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    final result = analyzer.analyze(makeFrame(
        makeLumaFrame(width: width, height: height, value: 90),
        width,
        height,
        0));
    expect(result.score, lessThan(0.01));
    expect(result.isMotion, isFalse);
  });

  test('static frames stabilize background', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    final diag = analyzer.diagnostics();
    expect(diag['hasBackground'], isTrue);
    expect(diag['analyzedFrames'], greaterThanOrEqualTo(5));
  });

  test('small local motion raises raw score and score', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    final data = makeLumaFrame(width: width, height: height, value: 80);
    drawRectOnLuma(data, width, height, 20, 15, 20, 15, 180);
    final result = analyzer.analyze(makeFrame(data, width, height, 600));
    expect(result.rawScore, greaterThan(0.2));
    expect(result.score, greaterThan(0.1));
  });

  test('motion shorter than min duration stays false', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    final data = makeLumaFrame(width: width, height: height, value: 80);
    drawRectOnLuma(data, width, height, 10, 10, 30, 20, 180);
    final result = analyzer.analyze(makeFrame(data, width, height, 600));
    expect(result.score, greaterThan(0.25));
    expect(result.isMotion, isFalse);
  });

  test('sustained motion longer than min duration becomes true', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    MotionAnalysisResult? result;
    for (final t in [600, 900, 1200]) {
      final data = makeLumaFrame(width: width, height: height, value: 80);
      drawRectOnLuma(data, width, height, 10, 10, 30, 20, 180);
      result = analyzer.analyze(makeFrame(data, width, height, t));
    }
    expect(result!.isMotion, isTrue);
  });

  test('motion inside ROI raises score', () {
    final analyzer = MotionAnalyzerV2(
      config: fastConfig(
          roi: const NormalizedRect(left: 0, top: 0, width: 0.5, height: 0.5)),
    );
    prime(analyzer, width, height);
    final data = makeLumaFrame(width: width, height: height, value: 80);
    drawRectOnLuma(data, width, height, 5, 5, 20, 15, 180);
    final result = analyzer.analyze(makeFrame(data, width, height, 600));
    expect(result.rawScore, greaterThan(0.3));
  });

  test('motion outside ROI keeps score low', () {
    final analyzer = MotionAnalyzerV2(
      config: fastConfig(
          roi: const NormalizedRect(left: 0, top: 0, width: 0.5, height: 0.5)),
    );
    prime(analyzer, width, height);
    final data = makeLumaFrame(width: width, height: height, value: 80);
    drawRectOnLuma(data, width, height, 55, 40, 20, 15, 180);
    final result = analyzer.analyze(makeFrame(data, width, height, 600));
    expect(result.rawScore, lessThan(0.05));
  });

  test('whole frame brightness change is global light change and no motion',
      () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    final result = analyzer.analyze(makeFrame(
        makeLumaFrame(width: width, height: height, value: 160),
        width,
        height,
        600));
    expect(result.isGlobalLightChange, isTrue);
    expect(result.isMotion, isFalse);
  });

  test('hysteresis keeps motion until score falls below off threshold', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    for (final t in [600, 900, 1200]) {
      final data = makeLumaFrame(width: width, height: height, value: 80);
      drawRectOnLuma(data, width, height, 10, 10, 30, 20, 180);
      analyzer.analyze(makeFrame(data, width, height, t));
    }
    final smaller = makeLumaFrame(width: width, height: height, value: 80);
    drawRectOnLuma(smaller, width, height, 10, 10, 12, 10, 180);
    final result = analyzer.analyze(makeFrame(smaller, width, height, 1500));
    expect(result.score, greaterThan(0.12));
    expect(result.isMotion, isTrue);
  });

  test('empty invalid frame is safe', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    final result = analyzer.analyze(makeFrame(Uint8List(0), 0, 0, 0));
    expect(result.invalidFrame, isTrue);
  });

  test('toJson returns core fields', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    final json = analyzer
        .analyze(makeFrame(
            makeLumaFrame(width: width, height: height, value: 90),
            width,
            height,
            0))
        .toJson();
    expect(
        json.keys,
        containsAll(
            ['timestampMs', 'score', 'rawScore', 'isMotion', 'invalidFrame']));
  });
}
