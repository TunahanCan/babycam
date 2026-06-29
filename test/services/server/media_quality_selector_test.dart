import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/core/media/client_quality_tracker.dart';
import 'package:mimicam/services/server/media_quality_selector.dart';

void main() {
  test('tek modern client iyi ağda 720p profil seçer', () {
    final selector = MediaQualitySelector();
    final profile = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
    );

    expect(profile.height, 720);
    expect(profile.targetFps, 12);
    expect(profile.audioFirst, isFalse);
  });

  test('2-3 client 480p, weak ağ 360p audio-first seçer', () {
    final selector = MediaQualitySelector();
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

    expect(shared.height, 480);
    expect(shared.targetFps, 8);
    expect(shared.audioFirst, isTrue);
    expect(weak.height, 360);
    expect(weak.targetFps, 8);
    expect(weak.audioFirst, isTrue);
  });

  test('4-5 client veya critical ağ 360p profil seçer', () {
    final selector = MediaQualitySelector();
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

    expect(crowded.height, 360);
    expect(crowded.targetFps, lessThanOrEqualTo(5));
    expect(crowded.audioFirst, isTrue);
    expect(critical.height, 360);
    expect(critical.targetFps, 5);
    expect(critical.audioFirst, isTrue);
  });

  test(
      'critical rapor hızlı degrade, stabil metrik 30 sn sonra tek kademe upgrade eder',
      () {
    var nowMs = 1000;
    final selector = MediaQualitySelector(nowMs: () => nowMs);

    final normal = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
    );
    expect(normal.height, 720);

    final critical = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
      worstReport: const ClientQualityReport(
        clientId: 'anne',
        networkTier: NetworkQualityTier.good,
        createdAtMs: 1000,
        videoFrameGapMs: 5000,
        watchActive: true,
      ),
    );
    expect(critical.height, 360);
    expect(critical.audioFirst, isTrue);

    nowMs += 29000;
    final blockedUpgrade = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
      worstReport: const ClientQualityReport(
        clientId: 'anne',
        networkTier: NetworkQualityTier.good,
        createdAtMs: 30000,
        watchActive: true,
      ),
    );
    expect(blockedUpgrade.height, 360);

    nowMs += 30000;
    final oneStepUpgrade = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
      worstReport: const ClientQualityReport(
        clientId: 'anne',
        networkTier: NetworkQualityTier.good,
        createdAtMs: 31000,
        watchActive: true,
      ),
    );
    expect(oneStepUpgrade.height, 720);
  });

  test('video timeout critical yapar, audio underrun sadece audio-first yapar',
      () {
    var nowMs = 1000;
    final selector = MediaQualitySelector(nowMs: () => nowMs);

    selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
    );
    final audioFirst = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
      worstReport: const ClientQualityReport(
        clientId: 'anne',
        networkTier: NetworkQualityTier.good,
        createdAtMs: 1000,
        audioUnderrun: true,
        watchActive: true,
      ),
    );
    expect(audioFirst.height, 720);
    expect(audioFirst.audioFirst, isTrue);

    nowMs += 60000;
    final critical = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
      worstReport: const ClientQualityReport(
        clientId: 'anne',
        networkTier: NetworkQualityTier.good,
        createdAtMs: 61000,
        streamTimedOut: true,
        watchActive: true,
        recentlyReconnected: true,
      ),
    );
    expect(critical.height, 360);
  });
}
