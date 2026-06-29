import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/core/media/client_quality_tracker.dart';
import 'package:mimicam/services/server/stream_backpressure_gate.dart';
import 'package:mimicam/services/server/utility_based_profile_selector.dart';

void main() {
  test('video timeout gelince critical profili hemen seçer', () {
    const selector = UtilityBasedProfileSelector();

    final profile = selector.choose(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
      currentProfile:
          MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern),
      qualityReports: const [
        ClientQualityReport(
          clientId: 'anne',
          networkTier: NetworkQualityTier.good,
          createdAtMs: 1000,
          videoFrameGapMs: 5000,
          watchActive: true,
        ),
      ],
    );

    expect(profile.height, 360);
    expect(profile.audioFirst, isTrue);
  });

  test('2-3 client 480p, 4-5 client 360p üst sınırı uygular', () {
    const selector = UtilityBasedProfileSelector();

    final shared = selector.choose(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 3,
      currentProfile: null,
    );
    final crowded = selector.choose(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 5,
      currentProfile: null,
    );

    expect(shared.height, 480);
    expect(crowded.height, 360);
  });

  test('audio underrun tek başına videoyu critical yapmaz', () {
    const selector = UtilityBasedProfileSelector();

    final profile = selector.choose(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
      currentProfile:
          MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern),
      qualityReports: const [
        ClientQualityReport(
          clientId: 'anne',
          networkTier: NetworkQualityTier.critical,
          createdAtMs: 1000,
          audioUnderrun: true,
          audioGapMs: 2000,
          watchActive: true,
        ),
      ],
    );

    expect(profile.height, 720);
    expect(profile.audioFirst, isTrue);
    expect(profile.targetFps, 10);
  });

  test('backpressure video skip artınca düşük profil faydası kazanır', () {
    const selector = UtilityBasedProfileSelector();

    final profile = selector.choose(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
      currentProfile:
          MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern),
      backpressureMetrics: const StreamBackpressureMetrics(
        skippedVideoFrames: 40,
        averageWriteDurationMs: 600,
      ),
    );

    expect(profile.height, lessThanOrEqualTo(360));
  });
}
