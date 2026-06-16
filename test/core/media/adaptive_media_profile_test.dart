import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';

void main() {
  test('cihaz tier profilleri eski cihazlarda uyumluluk modunu seçer', () {
    final legacy =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.legacy);
    final modern =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);

    expect(legacy.cameraPresetKey, 'low');
    expect(legacy.audioFirst, isTrue);
    expect(legacy.targetFps, lessThan(modern.targetFps));
    expect(modern.preferredVideoCodec, 'h264-webrtc');
    expect(modern.preferredAudioCodec, 'opus');
  });

  test('zayıf ağda video düşer ve ses öncelikli moda geçer', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);
    final weak = base.adaptForNetwork(NetworkQualityTier.weak);
    final critical = base.adaptForNetwork(NetworkQualityTier.critical);

    expect(weak.audioFirst, isTrue);
    expect(weak.targetFps, lessThan(base.targetFps));
    expect(weak.jpegQuality, lessThan(base.jpegQuality));
    expect(critical.targetFps, lessThan(weak.targetFps));
    expect(critical.cameraPresetKey, 'low');
  });

  test('network classifier rtt ve hata sayısına göre tier üretir', () {
    const classifier = NetworkQualityClassifier();

    expect(classifier.classify(rttMs: 80), NetworkQualityTier.excellent);
    expect(classifier.classify(rttMs: 260), NetworkQualityTier.good);
    expect(classifier.classify(rttMs: 600), NetworkQualityTier.weak);
    expect(classifier.classify(rttMs: 1200), NetworkQualityTier.critical);
    expect(
      classifier.classify(consecutiveFailures: 3),
      NetworkQualityTier.offline,
    );
  });
}
