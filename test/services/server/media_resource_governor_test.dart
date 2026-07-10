import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/services/platform/device_resource_snapshot_provider.dart';
import 'package:mimicam/services/server/media_resource_governor.dart';
import 'package:mimicam/services/server/stream_backpressure_gate.dart';

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
