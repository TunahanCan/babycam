import 'dart:typed_data';

/// Testable Y-plane luma frame input for motion analysis.
class LumaFrame {
  const LumaFrame({
    required this.yPlane,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.pixelStride,
    required this.timestampMs,
  });

  final Uint8List yPlane;
  final int width;
  final int height;
  final int rowStride;
  final int pixelStride;
  final int timestampMs;
}
