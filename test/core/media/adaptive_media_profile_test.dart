import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';

void main() {
  test('cihaz tier profilleri canlı izleme bütçesine uyar', () {
    final legacy =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.legacy);
    final balanced =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.balanced);
    final modern =
        MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);

    expect(legacy.height, 480);
    expect(legacy.targetFps, 8);
    expect(legacy.jpegQuality, 56);
    expect(balanced.height, 540);
    expect(balanced.targetFps, 10);
    expect(balanced.jpegQuality, 60);
    expect(modern.height, 720);
    expect(modern.targetFps, 12);
    expect(modern.cameraPresetKey, 'high');
    expect(modern.preferredVideoCodec, 'h264-webrtc');
    expect(modern.preferredAudioCodec, 'opus');
  });

  test('zayıf ve kritik ağda 360p ses önceliği seçilir', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);
    final weak = base.adaptForNetwork(NetworkQualityTier.weak);
    final critical = base.adaptForNetwork(NetworkQualityTier.critical);
    final survival = base.adaptForNetwork(NetworkQualityTier.offline);

    expect(weak.audioFirst, isTrue);
    expect(weak.height, 360);
    expect(weak.targetFps, 8);
    expect(weak.jpegQuality, 54);
    expect(critical.audioFirst, isTrue);
    expect(critical.height, 360);
    expect(critical.targetFps, 5);
    expect(critical.cameraPresetKey, 'medium');
    expect(survival.targetFps, 2);
  });

  test('aktif izleyici arttıkça kalite 480p ve 360p bütçesine iner', () {
    final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);
    final shared = base.adaptForClientLoad(3);
    final crowded = base.adaptForClientLoad(5);

    expect(shared.height, 480);
    expect(shared.targetFps, 8);
    expect(shared.jpegQuality, 56);
    expect(shared.audioFirst, isTrue);
    expect(crowded.height, 360);
    expect(crowded.targetFps, 5);
    expect(crowded.jpegQuality, 50);
    expect(crowded.cameraPresetKey, 'medium');
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
