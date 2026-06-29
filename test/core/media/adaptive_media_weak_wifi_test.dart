import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';

void main() {
  test('normal weak critical survival profilleri beklenen bütçeyi taşır', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);

    final normal = base.adaptForNetwork(NetworkQualityTier.good);
    final weak = base.adaptForNetwork(NetworkQualityTier.weak);
    final critical = base.adaptForNetwork(NetworkQualityTier.critical);
    final survival = base.adaptForNetwork(NetworkQualityTier.offline);

    expect(normal.toJson(), containsPair('height', 720));
    expect(normal.toJson(), containsPair('targetFps', 12));
    expect(normal.toJson(), containsPair('jpegQuality', 66));
    expect(weak.toJson(), containsPair('height', 360));
    expect(weak.toJson(), containsPair('targetFps', 8));
    expect(weak.toJson(), containsPair('jpegQuality', 54));
    expect(critical.toJson(), containsPair('height', 360));
    expect(critical.toJson(), containsPair('targetFps', 5));
    expect(critical.toJson(), containsPair('jpegQuality', 48));
    expect(survival.toJson(), containsPair('targetFps', 2));
    expect(survival.audioFirst, isTrue);
  });

  test('4-5 aktif izleyici video kalitesini 360p seviyesine indirir', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);
    final crowded = base.adaptForClientLoad(5);

    expect(crowded.height, 360);
    expect(crowded.targetFps, lessThanOrEqualTo(5));
    expect(crowded.jpegQuality, lessThanOrEqualTo(50));
    expect(crowded.audioFirst, isTrue);
  });
}
