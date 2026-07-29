import 'dart:typed_data';

import 'package:miucam/analysis/video/luma_downsampler.dart';
import 'package:miucam/analysis/video/luma_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uniform frame remains uniform after downsample', () {
    final input = Uint8List.fromList(List.filled(16, 77));
    final output = Uint8List(4);
    final ok =
        const LumaDownsampler(outputWidth: 2, outputHeight: 2).downsample(
      LumaFrame(
        yPlane: input,
        width: 4,
        height: 4,
        rowStride: 4,
        pixelStride: 1,
        timestampMs: 0,
      ),
      output,
    );
    expect(ok, isTrue);
    expect(output, everyElement(77));
  });

  test('handles rowStride greater than width', () {
    final input = Uint8List.fromList([
      1,
      2,
      3,
      99,
      99,
      4,
      5,
      6,
      99,
      99,
      7,
      8,
      9,
      99,
      99,
    ]);
    final output = Uint8List(4);
    final ok =
        const LumaDownsampler(outputWidth: 2, outputHeight: 2).downsample(
      LumaFrame(
        yPlane: input,
        width: 3,
        height: 3,
        rowStride: 5,
        pixelStride: 1,
        timestampMs: 0,
      ),
      output,
    );
    expect(ok, isTrue);
    expect(output, [1, 3, 6, 7]);
  });

  test('area averaging does not replicate one sensor speckle', () {
    final input = Uint8List(16)..[0] = 255;
    final output = Uint8List(4);

    final ok =
        const LumaDownsampler(outputWidth: 2, outputHeight: 2).downsample(
      LumaFrame(
        yPlane: input,
        width: 4,
        height: 4,
        rowStride: 4,
        pixelStride: 1,
        timestampMs: 0,
      ),
      output,
    );

    expect(ok, isTrue);
    expect(output, [64, 0, 0, 0]);
  });

  test('smaller source is rejected instead of being upscaled', () {
    final ok =
        const LumaDownsampler(outputWidth: 4, outputHeight: 4).downsample(
      LumaFrame(
        yPlane: Uint8List(4),
        width: 2,
        height: 2,
        rowStride: 2,
        pixelStride: 1,
        timestampMs: 0,
      ),
      Uint8List(16),
    );

    expect(ok, isFalse);
  });

  test('invalid dimensions are safe', () {
    final output = Uint8List(4);
    final ok =
        const LumaDownsampler(outputWidth: 2, outputHeight: 2).downsample(
      LumaFrame(
        yPlane: Uint8List(0),
        width: 0,
        height: 3,
        rowStride: 3,
        pixelStride: 1,
        timestampMs: 0,
      ),
      output,
    );
    expect(ok, isFalse);
  });
}
