import 'dart:typed_data';

import 'package:miucam/analysis/video/luma_frame.dart';
import 'package:miucam/analysis/video/motion_analysis_config.dart';
import 'package:miucam/analysis/video/motion_analysis_result.dart';
import 'package:miucam/analysis/video/motion_analyzer_v2.dart';
import 'package:miucam/analysis/video/normalized_rect.dart';
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

LumaFrame makeFrame(
  Uint8List data,
  int width,
  int height,
  int timestampMs, {
  int? monotonicTimestampMs,
}) =>
    LumaFrame(
      yPlane: data,
      width: width,
      height: height,
      rowStride: width,
      pixelStride: 1,
      timestampMs: timestampMs,
      monotonicTimestampMs: monotonicTimestampMs,
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

  test('off threshold cannot exceed the sensitive on threshold', () {
    final analyzer = MotionAnalyzerV2(
      config: fastConfig().copyWith(
        motionOnThreshold: 0.15,
        motionOffThreshold: 0.20,
      ),
    );

    expect(analyzer.diagnostics()['effectiveMotionOffThreshold'], 0.12);
  });

  test('small local motion raises raw score and score', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    final data = makeLumaFrame(width: width, height: height, value: 80);
    drawRectOnLuma(data, width, height, 20, 15, 20, 15, 180);
    final result = analyzer.analyze(makeFrame(data, width, height, 600));
    expect(result.rawScore, greaterThan(0.2));
    expect(result.score, greaterThan(0.1));
    // A small moving patch must not be interpreted as whole-frame motion by
    // the content-aware FPS policy (whose activity threshold is 0.04).
    expect(result.normalizedMotionEnergy, lessThan(0.04));
    expect(result.normalizedMotionEnergy, inInclusiveRange(0, 1));
  });

  test('isolated sensor speckles do not become motion', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    MotionAnalysisResult? result;
    for (final t in [600, 900, 1200]) {
      final data = makeLumaFrame(width: width, height: height, value: 80);
      for (var y = 0; y < height; y += 6) {
        for (var x = 0; x < width; x += 6) {
          data[y * width + x] = 180;
        }
      }
      result = analyzer.analyze(makeFrame(data, width, height, t));
    }
    expect(result!.activeAreaRatio, lessThan(0.01));
    expect(result.isMotion, isFalse);
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
    expect(result.normalizedMotionEnergy, 0);
  });

  test('başlangıç exposure yerleşirken karar karantinası motion üretmez', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    final results = <MotionAnalysisResult>[];

    for (var index = 0; index < 5; index++) {
      final data =
          makeLumaFrame(width: width, height: height, value: 70 + index * 5);
      drawRectOnLuma(
        data,
        width,
        height,
        8 + index,
        8,
        30,
        20,
        120 + index * 10,
      );
      results.add(analyzer.analyze(
        makeFrame(data, width, height, index * 100),
      ));
    }

    expect(results.any((result) => result.isMotion), isFalse);
    expect(analyzer.diagnostics()['warmingUp'], isFalse);
  });

  test('uzun frame boşluğu minimum motion süresini tek sıçramada doldurmaz',
      () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    final moving = makeLumaFrame(width: width, height: height, value: 80);
    drawRectOnLuma(moving, width, height, 10, 10, 30, 20, 180);

    expect(
      analyzer.analyze(makeFrame(moving, width, height, 600)).isMotion,
      isFalse,
    );
    final afterGap = analyzer.analyze(makeFrame(moving, width, height, 5000));

    expect(afterGap.isMotion, isFalse);
    expect(afterGap.score, 0);
    expect(analyzer.diagnostics()['analyzedFrames'], 1);
  });

  test('invalid frame eski motion adayını sonraki kareye taşımaz', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    final moving = makeLumaFrame(width: width, height: height, value: 80);
    drawRectOnLuma(moving, width, height, 10, 10, 30, 20, 180);

    expect(
      analyzer.analyze(makeFrame(moving, width, height, 600)).isMotion,
      isFalse,
    );
    expect(
      analyzer.analyze(makeFrame(moving, width, height, 900)).isMotion,
      isFalse,
    );
    final invalid = analyzer.analyze(LumaFrame(
      yPlane: Uint8List(4),
      width: 2,
      height: 2,
      rowStride: 2,
      pixelStride: 1,
      timestampMs: 1000,
    ));
    final afterInvalid =
        analyzer.analyze(makeFrame(moving, width, height, 1200));

    expect(invalid.invalidFrame, isTrue);
    expect(afterInvalid.isMotion, isFalse);
    expect(afterInvalid.score, 0);
    expect(analyzer.diagnostics()['analyzedFrames'], 1);
  });

  test('wall clock sıçraması monotonic motion süresini değiştirmez', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    for (var index = 0; index < 5; index++) {
      analyzer.analyze(makeFrame(
        makeLumaFrame(width: width, height: height, value: 80),
        width,
        height,
        10000 + index * 100,
        monotonicTimestampMs: index * 100,
      ));
    }

    MotionAnalysisResult? result;
    final wallTimes = [20000, 50000, 100000];
    final monotonicTimes = [600, 900, 1200];
    for (var index = 0; index < wallTimes.length; index++) {
      final data = makeLumaFrame(width: width, height: height, value: 80);
      drawRectOnLuma(data, width, height, 10, 10, 30, 20, 180);
      result = analyzer.analyze(makeFrame(
        data,
        width,
        height,
        wallTimes[index],
        monotonicTimestampMs: monotonicTimes[index],
      ));
    }

    expect(result!.timestampMs, 100000);
    expect(result.isMotion, isTrue);
  });

  test('global ışık değişimi backgroundu hemen rebasing ile toparlar', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);

    final changed = analyzer.analyze(makeFrame(
      makeLumaFrame(width: width, height: height, value: 160),
      width,
      height,
      600,
    ));
    final settled = analyzer.analyze(makeFrame(
      makeLumaFrame(width: width, height: height, value: 160),
      width,
      height,
      900,
    ));

    expect(changed.isGlobalLightChange, isTrue);
    expect(settled.isGlobalLightChange, isFalse);
    expect(settled.score, lessThan(.05));

    MotionAnalysisResult? motion;
    for (final timestampMs in [1200, 1500, 1800]) {
      final data = makeLumaFrame(width: width, height: height, value: 160);
      drawRectOnLuma(data, width, height, 10, 10, 30, 20, 70);
      motion = analyzer.analyze(
        makeFrame(data, width, height, timestampMs),
      );
    }
    expect(motion!.isMotion, isTrue);
  });

  test('büyük heterojen sahne değişimi uniform ışık değişimi sayılmaz', () {
    final analyzer = MotionAnalyzerV2(config: fastConfig());
    prime(analyzer, width, height);
    final data = makeLumaFrame(width: width, height: height, value: 80);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        data[y * width + x] = ((x ~/ 4 + y ~/ 4).isEven) ? 0 : 200;
      }
    }

    final result = analyzer.analyze(makeFrame(data, width, height, 600));

    expect(result.isGlobalLightChange, isFalse);
    expect(result.rawScore, greaterThan(.25));
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
