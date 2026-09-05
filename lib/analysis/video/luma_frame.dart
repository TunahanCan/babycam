import 'dart:typed_data';

enum LumaPixelFormat { luma8, bgra8888 }

/// Testable Y-plane luma frame input for motion analysis.
class LumaFrame {
  const LumaFrame({
    required this.yPlane,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.pixelStride,
    required this.timestampMs,
    this.monotonicTimestampMs,
    this.pixelFormat = LumaPixelFormat.luma8,
  });

  final Uint8List yPlane;
  final int width;
  final int height;
  final int rowStride;
  final int pixelStride;
  final int timestampMs;
  final int? monotonicTimestampMs;
  final LumaPixelFormat pixelFormat;

  /// Stable capture time for duration/gap decisions; wall time remains the
  /// user-facing event timestamp.
  int get analysisTimestampMs => monotonicTimestampMs ?? timestampMs;
}
