import 'dart:typed_data';

import 'luma_frame.dart';

/// Nearest-neighbor Y-plane downsampler with stride-aware safe reads.
class LumaDownsampler {
  const LumaDownsampler(
      {required this.outputWidth, required this.outputHeight});

  final int outputWidth;
  final int outputHeight;

  bool canDownsample(LumaFrame frame) {
    if (outputWidth <= 0 || outputHeight <= 0) return false;
    if (frame.width <= 0 || frame.height <= 0) return false;
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
      final srcY = (y * frame.height) ~/ outputHeight;
      final rowStart = srcY * frame.rowStride;
      for (var x = 0; x < outputWidth; x++) {
        final srcX = (x * frame.width) ~/ outputWidth;
        final offset = rowStart + srcX * frame.pixelStride;
        output[outIndex++] = frame.yPlane[offset];
      }
    }
    return true;
  }
}
