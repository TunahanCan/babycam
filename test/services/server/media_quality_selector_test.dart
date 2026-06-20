import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/services/server/media_quality_selector.dart';

void main() {
  const selector = MediaQualitySelector();

  test('tek client iyi ağda 480p profil seçer', () {
    final profile = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
    );

    expect(profile.height, 480);
    expect(profile.targetFps, 8);
    expect(profile.audioFirst, isFalse);
  });

  test('2-3 client veya weak ağ 360p audio-first seçer', () {
    final shared = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 3,
    );
    final weak = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.weak,
      activeClientCount: 1,
    );

    expect(shared.height, 360);
    expect(shared.targetFps, 5);
    expect(shared.audioFirst, isTrue);
    expect(weak.height, 360);
    expect(weak.targetFps, 5);
    expect(weak.audioFirst, isTrue);
  });

  test('4-5 client veya critical ağ 240p profil seçer', () {
    final crowded = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 5,
    );
    final critical = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.critical,
      activeClientCount: 1,
    );

    expect(crowded.height, 240);
    expect(crowded.targetFps, 4);
    expect(crowded.audioFirst, isTrue);
    expect(critical.height, 240);
    expect(critical.targetFps, 2);
    expect(critical.audioFirst, isTrue);
  });
}
