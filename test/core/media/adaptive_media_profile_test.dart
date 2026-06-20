import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';

void main() {
  test('cihaz tier profilleri en az 480p yayın profili seçer', () {
    final legacy =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.legacy);
    final balanced =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.balanced);
    final modern =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);

    expect(legacy.cameraPresetKey, 'medium');
    expect(legacy.height, 480);
    expect(balanced.height, 480);
    expect(modern.height, 720);
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
    expect(weak.height, 480);
    expect(weak.targetFps, lessThan(base.targetFps));
    expect(weak.jpegQuality, lessThan(base.jpegQuality));
    expect(critical.height, 480);
    expect(critical.targetFps, lessThan(weak.targetFps));
    expect(critical.cameraPresetKey, 'medium');
  });

  test('dört aktif izleyicide modern profil paylaşımlı 480p moda iner', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);
    final shared = base.adaptForClientLoad(4);
    final critical =
        base.adaptForNetwork(NetworkQualityTier.critical).adaptForClientLoad(4);

    expect(shared.height, 480);
    expect(shared.targetFps, 8);
    expect(shared.jpegQuality, 52);
    expect(shared.cameraPresetKey, 'medium');
    expect(critical.height, 480);
    expect(critical.targetFps, 4);
    expect(critical.jpegQuality, 42);
  });

  test('legacy cihaz tüm ağ koşullarında 480p altına düşmez', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.legacy);
    final excellent = base.adaptForNetwork(NetworkQualityTier.excellent);
    final weak = base.adaptForNetwork(NetworkQualityTier.weak);
    final critical = base.adaptForNetwork(NetworkQualityTier.critical);
    final offline = base.adaptForNetwork(NetworkQualityTier.offline);

    expect(base.height, 480);
    expect(excellent.height, 480);
    expect(excellent.targetFps, 10);
    expect(excellent.cameraPresetKey, 'medium');
    expect(excellent.audioFirst, isFalse);
    expect(weak.height, 480);
    expect(weak.audioFirst, isTrue);
    expect(critical.height, 480);
    expect(critical.audioFirst, isTrue);
    expect(offline.height, 480);
    expect(offline.audioFirst, isTrue);
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
