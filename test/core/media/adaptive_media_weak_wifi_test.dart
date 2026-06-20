import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';

void main() {
  test('normal weak critical survival profilleri beklenen bütçeyi taşır', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);

    final normal = base.adaptForNetwork(NetworkQualityTier.good);
    final weak = base.adaptForNetwork(NetworkQualityTier.weak);
    final critical = base.adaptForNetwork(NetworkQualityTier.critical);
    final survival = base.adaptForNetwork(NetworkQualityTier.offline);

    expect(normal.toJson(), containsPair('height', 480));
    expect(normal.toJson(), containsPair('targetFps', 8));
    expect(normal.toJson(), containsPair('jpegQuality', 52));
    expect(weak.toJson(), containsPair('height', 360));
    expect(weak.toJson(), containsPair('targetFps', 5));
    expect(weak.toJson(), containsPair('jpegQuality', 42));
    expect(critical.toJson(), containsPair('height', 240));
    expect(critical.toJson(), containsPair('targetFps', 2));
    expect(critical.toJson(), containsPair('jpegQuality', 36));
    expect(survival.toJson(), containsPair('targetFps', 1));
    expect(survival.audioFirst, isTrue);
  });

  test('4-5 aktif izleyici video kalitesini 240p seviyesine indirir', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);
    final crowded = base.adaptForClientLoad(5);

    expect(crowded.height, 240);
    expect(crowded.targetFps, lessThanOrEqualTo(4));
    expect(crowded.jpegQuality, lessThanOrEqualTo(40));
    expect(crowded.audioFirst, isTrue);
  });
}
