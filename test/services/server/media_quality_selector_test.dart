import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/adaptive_media_profile.dart';
import 'package:miucam/core/media/client_quality_tracker.dart';
import 'package:miucam/services/server/media_quality_selector.dart';

void main() {
  test('same resolution FPS recovery waits for sustained healthy reports', () {
    var nowMs = 1000;
    final selector = MediaQualitySelector(nowMs: () => nowMs);
    MediaQualityProfile select(NetworkQualityTier tier) => selector.select(
          deviceTier: DeviceCapabilityTier.modern,
          networkTier: tier,
          activeClientCount: 1,
        );

    expect(select(NetworkQualityTier.critical).targetFps, 5);
    nowMs += 60000;
    expect(select(NetworkQualityTier.critical).targetFps, 5);
    expect(select(NetworkQualityTier.weak).targetFps, 5);
    nowMs += 29999;
    expect(select(NetworkQualityTier.weak).targetFps, 5);
    nowMs++;
    expect(select(NetworkQualityTier.weak).targetFps, 8);
  });

  test('renewed degradation restarts the upgrade stability window', () {
    var nowMs = 1000;
    final selector = MediaQualitySelector(nowMs: () => nowMs);
    MediaQualityProfile select(NetworkQualityTier tier) => selector.select(
          deviceTier: DeviceCapabilityTier.modern,
          networkTier: tier,
          activeClientCount: 1,
        );

    select(NetworkQualityTier.critical);
    expect(select(NetworkQualityTier.good).targetFps, 5);
    nowMs += 29000;
    expect(select(NetworkQualityTier.critical).targetFps, 5);
    nowMs += 1000;
    expect(select(NetworkQualityTier.good).targetFps, 5);
    nowMs += 30000;
    final upgraded = select(NetworkQualityTier.good);
    expect(upgraded.height, 360);
    expect(upgraded.targetFps, 8);
  });

  test('shared 480p to 720p recovery respects the upgrade cooldown', () {
    var nowMs = 1000;
    final selector = MediaQualitySelector(nowMs: () => nowMs);
    MediaQualityProfile select(int clients) => selector.select(
          deviceTier: DeviceCapabilityTier.modern,
          networkTier: NetworkQualityTier.good,
          activeClientCount: clients,
        );

    expect(select(2).height, 480);
    expect(select(1).height, 480);
    nowMs += 30000;
    expect(select(1).height, 720);
  });

  test('reconnect restarts an in-progress upgrade stability window', () {
    var nowMs = 1000;
    final selector = MediaQualitySelector(nowMs: () => nowMs);
    MediaQualityProfile select({bool reconnect = false}) => selector.select(
          deviceTier: DeviceCapabilityTier.modern,
          networkTier: NetworkQualityTier.good,
          activeClientCount: 1,
          worstReport: ClientQualityReport(
            clientId: 'parent',
            networkTier: NetworkQualityTier.good,
            createdAtMs: nowMs,
            recentlyReconnected: reconnect,
            watchActive: true,
          ),
        );

    selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.critical,
      activeClientCount: 1,
    );
    select();
    nowMs += 29000;
    select(reconnect: true);
    nowMs += 1000;
    expect(select().targetFps, 5);
    nowMs += 30000;
    expect(select().targetFps, 8);
  });

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
    expect(oneStepUpgrade.height, 360);
    expect(oneStepUpgrade.targetFps, 8);

    nowMs += 30000;
    final fullRecovery = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: 1,
    );
    expect(fullRecovery.height, 720);
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
