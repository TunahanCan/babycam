import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';

void main() {
  test('cihaz tier profilleri MVP HTTP/WS medya bütçesine uyar', () {
    final legacy =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.legacy);
    final balanced =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.balanced);
    final modern =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);

    expect(legacy.height, 360);
    expect(legacy.targetFps, 5);
    expect(legacy.jpegQuality, 42);
    expect(balanced.height, 480);
    expect(balanced.targetFps, 8);
    expect(balanced.jpegQuality, 52);
    expect(modern.height, 480);
    expect(modern.cameraPresetKey, 'medium');
    expect(modern.preferredVideoCodec, 'h264-webrtc');
    expect(modern.preferredAudioCodec, 'opus');
  });

  test('zayıf ağda 360p, kritik ağda 240p ses önceliği seçilir', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);
    final weak = base.adaptForNetwork(NetworkQualityTier.weak);
    final critical = base.adaptForNetwork(NetworkQualityTier.critical);
    final survival = base.adaptForNetwork(NetworkQualityTier.offline);

    expect(weak.audioFirst, isTrue);
    expect(weak.height, 360);
    expect(weak.targetFps, 5);
    expect(weak.jpegQuality, 42);
    expect(critical.audioFirst, isTrue);
    expect(critical.height, 240);
    expect(critical.targetFps, 2);
    expect(critical.cameraPresetKey, 'low');
    expect(survival.targetFps, 1);
  });

  test('aktif izleyici arttıkça kalite 360p ve 240p bütçesine iner', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);
    final shared = base.adaptForClientLoad(3);
    final crowded = base.adaptForClientLoad(5);

    expect(shared.height, 360);
    expect(shared.targetFps, 5);
    expect(shared.jpegQuality, 42);
    expect(shared.audioFirst, isTrue);
    expect(crowded.height, 240);
    expect(crowded.targetFps, 4);
    expect(crowded.jpegQuality, 40);
    expect(crowded.cameraPresetKey, 'low');
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
