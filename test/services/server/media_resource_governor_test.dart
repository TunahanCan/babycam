import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/adaptive_media_profile.dart';
import 'package:miucam/services/platform/device_resource_snapshot_provider.dart';
import 'package:miucam/services/server/media_resource_governor.dart';
import 'package:miucam/services/server/stream_backpressure_gate.dart';

void main() {
  const governor = MediaResourceGovernor();
  final base = MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.modern);

  test('nominal charged device keeps full profile', () {
    final decision = governor.evaluate(_input(
      thermal: DeviceThermalState.nominal,
      charging: true,
    ));

    expect(decision.state, MediaDegradationState.normal);
    expect(decision.applyTo(base), same(base));
  });

  test('serious thermal pressure enters survival profile', () {
    final decision = governor.evaluate(_input(
      thermal: DeviceThermalState.serious,
    ));
    final profile = decision.applyTo(base);

    expect(decision.state, MediaDegradationState.survival);
    expect(profile.height, 240);
    expect(profile.targetFps, 2);
    expect(profile.audioFirst, isTrue);
  });

  test('critical thermal pressure with audio demand enters audio-only state',
      () {
    final decision = governor.evaluate(_input(
      thermal: DeviceThermalState.critical,
      audioDemandAvailable: true,
    ));

    expect(decision.state, MediaDegradationState.audioOnly);
    expect(decision.applyTo(base).targetFps, 1);
    expect(decision.reasons, contains('thermalCritical'));
  });

  test('decoder coalescence and audio underrun preserve audio budget', () {
    final decision = governor.evaluate(_input(
      decoderCoalescedFrames: 12,
      audioUnderruns: 1,
    ));

    expect(decision.state, MediaDegradationState.survival);
    expect(
        decision.reasons,
        containsAll([
          'clientDecoderOverloaded',
          'audioUnderrun',
        ]));
  });

  test('recovery hysteresis prevents thermal profile flapping', () {
    final stabilizer = MediaResourceDecisionStabilizer(recoverySamples: 3);
    final constrained = governor.evaluate(_input(
      thermal: DeviceThermalState.serious,
    ));
    final healthy = governor.evaluate(_input(
      thermal: DeviceThermalState.nominal,
      charging: true,
    ));

    expect(
      stabilizer.stabilize(constrained).state,
      MediaDegradationState.survival,
    );
    expect(stabilizer.stabilize(healthy).state, MediaDegradationState.survival);
    expect(
        stabilizer.stabilize(healthy).reasons, contains('recoveryHysteresis'));
    expect(stabilizer.stabilize(healthy).state, MediaDegradationState.normal);
  });

  test('audio-only recovery also requires stable healthy samples', () {
    final stabilizer = MediaResourceDecisionStabilizer(recoverySamples: 3);
    final audioOnly = governor.evaluate(_input(
      thermal: DeviceThermalState.critical,
      audioDemandAvailable: true,
    ));
    final healthy = governor.evaluate(_input(
      thermal: DeviceThermalState.nominal,
      charging: true,
    ));

    expect(stabilizer.stabilize(audioOnly).audioOnly, isTrue);
    expect(stabilizer.stabilize(healthy).audioOnly, isTrue);
    expect(stabilizer.stabilize(healthy).audioOnly, isTrue);
    expect(stabilizer.stabilize(healthy).state, MediaDegradationState.normal);
  });
}

MediaResourceGovernorInput _input({
  DeviceThermalState thermal = DeviceThermalState.nominal,
  bool? charging = false,
  bool lowPower = false,
  bool audioDemandAvailable = false,
  int decoderCoalescedFrames = 0,
  int audioUnderruns = 0,
}) =>
    MediaResourceGovernorInput(
      device: DeviceResourceSnapshot(
        thermalState: thermal,
        lowPowerMode: lowPower,
        charging: charging,
        batteryLevelPercent: 80,
        measuredAtMs: 1,
      ),
      networkTier: NetworkQualityTier.excellent,
      backpressure: const StreamBackpressureMetrics(),
      activeClientCount: 1,
      audioDemandAvailable: audioDemandAvailable,
      decoderCoalescedFrames: decoderCoalescedFrames,
      audioUnderruns: audioUnderruns,
    );
