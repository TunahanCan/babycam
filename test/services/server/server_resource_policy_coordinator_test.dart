import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/services/platform/device_resource_snapshot_provider.dart';
import 'package:mimicam/services/server/media_resource_governor.dart';
import 'package:mimicam/services/server/server_resource_policy_coordinator.dart';
import 'package:mimicam/services/server/stream_backpressure_gate.dart';

void main() {
  test('watchdog starts immediately and never overlaps refreshes', () async {
    var active = true;
    var calls = 0;
    var idleCalls = 0;
    final release = Completer<void>();
    final coordinator = ServerResourcePolicyCoordinator(
      governor: const MediaResourceGovernor(),
      monitoringRequired: () => active,
      refreshProfile: () async {
        calls++;
        await release.future;
      },
      onMonitoringIdle: () => idleCalls++,
      onWatchdogError: (_) {},
      watchdogInterval: const Duration(milliseconds: 1),
    );

    coordinator.reconcileWatchdog();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(calls, 1);

    active = false;
    coordinator.reconcileWatchdog();
    expect(idleCalls, 1);
    release.complete();
    await coordinator.refreshNow();
    expect(calls, 1);
    coordinator.dispose();
  });

  test('watchdog contains refresh errors and can retry', () async {
    var calls = 0;
    final errors = <Object>[];
    final coordinator = ServerResourcePolicyCoordinator(
      governor: const MediaResourceGovernor(),
      monitoringRequired: () => true,
      refreshProfile: () async {
        calls++;
        if (calls == 1) throw StateError('snapshot failed');
      },
      onMonitoringIdle: () {},
      onWatchdogError: errors.add,
      watchdogInterval: const Duration(days: 1),
    );

    await coordinator.refreshNow();
    await coordinator.refreshNow();

    expect(calls, 2);
    expect(errors.single, isA<StateError>());
    coordinator.dispose();
  });

  test('coordinator stabilizes decisions and builds bounded WebRTC policy', () {
    final coordinator = ServerResourcePolicyCoordinator(
      governor: const MediaResourceGovernor(),
      monitoringRequired: () => false,
      refreshProfile: () async {},
      onMonitoringIdle: () {},
      onWatchdogError: (_) {},
    );
    final decision = coordinator.evaluate(const MediaResourceGovernorInput(
      device: DeviceResourceSnapshot(
        thermalState: DeviceThermalState.critical,
        lowPowerMode: false,
        charging: false,
        batteryLevelPercent: 4,
        measuredAtMs: 1,
      ),
      networkTier: NetworkQualityTier.excellent,
      backpressure: StreamBackpressureMetrics(),
      activeClientCount: 1,
      audioDemandAvailable: true,
    ));
    final profile = MediaQualityProfile.forDeviceTier(
      DeviceCapabilityTier.modern,
    );
    final policy = coordinator.webRtcPolicyFor(profile, decision);

    expect(decision.state, MediaDegradationState.audioOnly);
    expect(policy.videoEnabled, isFalse);
    expect(policy.maxVideoBitrateBps, inInclusiveRange(120000, 2500000));
    expect(policy.scaleResolutionDownBy, inInclusiveRange(1.0, 4.0));
    coordinator.dispose();
  });
}
