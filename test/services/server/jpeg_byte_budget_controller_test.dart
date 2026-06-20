import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/services/server/jpeg_byte_budget_controller.dart';

void main() {
  test('actual bytes target üstündeyse JPEG quality düşer', () {
    var nowMs = 1000;
    final controller = JpegByteBudgetController(nowMs: () => nowMs);
    final profile =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);

    expect(controller.qualityFor(profile), profile.jpegQuality);

    controller.recordEncodedFrame(profile, byteLength: 400 * 1024, atMs: nowMs);
    nowMs += 1000;
    controller.recordEncodedFrame(profile, byteLength: 400 * 1024, atMs: nowMs);

    expect(controller.qualityFor(profile), lessThan(profile.jpegQuality));
    expect(controller.qualityFor(profile), greaterThanOrEqualTo(32));
    expect(
        controller.lastActualBytesPerSecond(profile), greaterThan(275 * 1024));
  });
}
