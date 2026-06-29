import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/core/media/client_quality_tracker.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/services/server/active_client_registry.dart';
import 'package:mimicam/services/server/media_quality_selector.dart';

void main() {
  test('1, 2-3 ve 4-5 active client kalite cap uygular', () {
    final selector = MediaQualitySelector();

    expect(
      selector
          .select(
            deviceTier: DeviceCapabilityTier.modern,
            networkTier: NetworkQualityTier.good,
            activeClientCount: 1,
          )
          .height,
      720,
    );
    selector.reset();
    expect(
      selector
          .select(
            deviceTier: DeviceCapabilityTier.modern,
            networkTier: NetworkQualityTier.good,
            activeClientCount: 3,
          )
          .height,
      480,
    );
    selector.reset();
    expect(
      selector
          .select(
            deviceTier: DeviceCapabilityTier.modern,
            networkTier: NetworkQualityTier.good,
            activeClientCount: 5,
          )
          .height,
      360,
    );
  });

  test('6. client reddedilir ve stop sonrası kalite hemen yükselmez', () {
    var nowMs = 1000;
    final registry = ActiveClientRegistry(
      tokenService: PairingTokenService(),
      maxActiveClients: 5,
    );
    final selector = MediaQualitySelector(nowMs: () => nowMs);

    for (var index = 0; index < 5; index++) {
      registry.startSession('client_$index');
    }
    expect(
      () => registry.startSession('client_5'),
      throwsA(isA<ActiveClientLimitException>()),
    );

    final crowded = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: registry.effectiveTier(),
      activeClientCount: registry.activeClientCount,
      worstReport: const ClientQualityReport(
        clientId: 'client_0',
        networkTier: NetworkQualityTier.good,
        createdAtMs: 1000,
        watchActive: true,
      ),
    );
    expect(crowded.height, 360);

    for (var index = 1; index < 5; index++) {
      registry.stopSession('client_$index');
    }
    final blockedUpgrade = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: registry.activeClientCount,
      worstReport: const ClientQualityReport(
        clientId: 'client_0',
        networkTier: NetworkQualityTier.good,
        createdAtMs: 2000,
        watchActive: true,
      ),
    );
    expect(blockedUpgrade.height, 360);

    nowMs += 30000;
    final oneStepUpgrade = selector.select(
      deviceTier: DeviceCapabilityTier.modern,
      networkTier: NetworkQualityTier.good,
      activeClientCount: registry.activeClientCount,
      worstReport: const ClientQualityReport(
        clientId: 'client_0',
        networkTier: NetworkQualityTier.good,
        createdAtMs: 31000,
        watchActive: true,
      ),
    );
    expect(oneStepUpgrade.height, 720);
  });
}
