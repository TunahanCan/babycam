import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/services/platform/device_capability_probe.dart';

void main() {
  test('işlemci sayısına göre cihaz tier tahmini yapılır', () {
    expect(
      DeviceCapabilityProbe.detectTier(processorCount: 4),
      DeviceCapabilityTier.legacy,
    );
    expect(
      DeviceCapabilityProbe.detectTier(processorCount: 6),
      DeviceCapabilityTier.balanced,
    );
    expect(
      DeviceCapabilityProbe.detectTier(processorCount: 8),
      DeviceCapabilityTier.modern,
    );
  });
}
