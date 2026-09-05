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
    final isBgra = frame.pixelFormat == LumaPixelFormat.bgra8888;
    if (isBgra && frame.pixelStride < 4) return false;
    final sampleBytes = isBgra ? 3 : 1;
    if (frame.rowStride < (frame.width - 1) * frame.pixelStride + sampleBytes) {
      return false;
    }
    final lastOffset = (frame.height - 1) * frame.rowStride +
        (frame.width - 1) * frame.pixelStride +
        sampleBytes -
        1;
    return lastOffset >= 0 && lastOffset < frame.yPlane.length;
  }

  /// Writes downsampled luma into [output]. Returns false for invalid input.
  bool downsample(LumaFrame frame, Uint8List output) {
    if (!canDownsample(frame) || output.length < outputWidth * outputHeight) {
      return false;
    }
    final isBgra = frame.pixelFormat == LumaPixelFormat.bgra8888;
    final lumaScale = isBgra ? 1000 : 1;
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
            final offset = rowStart + sourceX * frame.pixelStride;
            if (isBgra) {
              // Convert while averaging, without allocating a full-resolution
              // intermediate Y plane. Blue alone misses red/green movement.
              sum += 114 * frame.yPlane[offset] +
                  587 * frame.yPlane[offset + 1] +
                  299 * frame.yPlane[offset + 2];
            } else {
              sum += frame.yPlane[offset];
            }
            count++;
          }
        }
        if (count == 0) return false;
        output[outIndex++] = (sum / (count * lumaScale)).round();
      }
    }
    return true;
  }
}
