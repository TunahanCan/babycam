import 'dart:typed_data';

import 'luma_frame.dart';

/// Area-average Y-plane downsampler with stride-aware safe reads.
class LumaDownsampler {
  const LumaDownsampler(
      {required this.outputWidth, required this.outputHeight});

  final int outputWidth;
  final int outputHeight;

  bool canDownsample(LumaFrame frame) {
    if (outputWidth <= 0 || outputHeight <= 0) return false;
    if (frame.width <= 0 || frame.height <= 0) return false;
    // Upscaling repeats one sensor sample into connected output pixels and can
    // turn a single low-light speckle into apparent motion.
    if (frame.width < outputWidth || frame.height < outputHeight) return false;
    if (frame.rowStride <= 0 || frame.pixelStride <= 0) return false;
    if (frame.yPlane.isEmpty) return false;
    final lastOffset = (frame.height - 1) * frame.rowStride +
        (frame.width - 1) * frame.pixelStride;
    return lastOffset >= 0 && lastOffset < frame.yPlane.length;
  }

  /// Writes downsampled luma into [output]. Returns false for invalid input.
  bool downsample(LumaFrame frame, Uint8List output) {
    if (!canDownsample(frame) || output.length < outputWidth * outputHeight) {
      return false;
    }
    var outIndex = 0;
    for (var y = 0; y < outputHeight; y++) {
      final startY = (y * frame.height) ~/ outputHeight;
      final endY = ((y + 1) * frame.height) ~/ outputHeight;
      for (var x = 0; x < outputWidth; x++) {
        final startX = (x * frame.width) ~/ outputWidth;
        final endX = ((x + 1) * frame.width) ~/ outputWidth;
        var sum = 0;
        var count = 0;
        for (var sourceY = startY; sourceY < endY; sourceY++) {
          final rowStart = sourceY * frame.rowStride;
          for (var sourceX = startX; sourceX < endX; sourceX++) {
            sum += frame.yPlane[rowStart + sourceX * frame.pixelStride];
            count++;
          }
        }
        if (count == 0) return false;
        output[outIndex++] = (sum / count).round();
      }
    }
    return true;
  }
}
