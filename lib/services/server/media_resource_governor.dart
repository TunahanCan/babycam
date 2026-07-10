import 'dart:math';

import '../../core/media/adaptive_media_profile.dart';
import '../platform/device_resource_snapshot_provider.dart';
import 'stream_backpressure_gate.dart';

enum MediaDegradationState {
  normal,
  constrained,
  survival,
  audioOnly,
}

class MediaResourceGovernorInput {
  const MediaResourceGovernorInput({
    required this.device,
    required this.networkTier,
    required this.backpressure,
    required this.activeClientCount,
    this.videoEncodeP95Ms,
    this.framesCaptured = 0,
    this.framesDroppedBeforeEncode = 0,
    this.decoderCoalescedFrames = 0,
    this.audioUnderruns = 0,
    this.audioDemandAvailable = false,
  });

  final DeviceResourceSnapshot device;
  final NetworkQualityTier networkTier;
  final StreamBackpressureMetrics backpressure;
  final int activeClientCount;
  final double? videoEncodeP95Ms;
  final int framesCaptured;
  final int framesDroppedBeforeEncode;
  final int decoderCoalescedFrames;
  final int audioUnderruns;
  final bool audioDemandAvailable;

  double get preEncodeDropRatio {
    final total = framesCaptured + framesDroppedBeforeEncode;
    return total <= 0 ? 0 : framesDroppedBeforeEncode / total;
  }
}

class MediaResourceGovernorDecision {
  const MediaResourceGovernorDecision({
    required this.state,
    required this.reasons,
  });

  static const normal = MediaResourceGovernorDecision(
    state: MediaDegradationState.normal,
    reasons: <String>[],
  );

  final MediaDegradationState state;
  final List<String> reasons;

  bool get audioOnly => state == MediaDegradationState.audioOnly;

  MediaQualityProfile applyTo(MediaQualityProfile profile) => switch (state) {
        MediaDegradationState.normal => profile,
        MediaDegradationState.constrained => _cap(
            profile,
            id: 'resource_constrained_360p',
            label: 'Cihaz koruma',
            width: 640,
            height: 360,
            fps: 6,
            quality: 50,
            preset: 'medium',
          ),
        MediaDegradationState.survival => _cap(
            profile,
            id: 'resource_survival_240p',
            label: 'Kaynak koruma',
            width: 426,
            height: 240,
            fps: 2,
            quality: 42,
            preset: 'low',
          ),
        MediaDegradationState.audioOnly => _cap(
            profile,
            id: 'resource_audio_only',
            label: 'Ses öncelikli koruma',
            width: 426,
            height: 240,
            // A 1 fps liveness frame keeps legacy MJPEG clients connected
            // while audio receives almost the entire CPU/network budget.
            fps: 1,
            quality: 38,
            preset: 'low',
          ),
      };

  static MediaQualityProfile _cap(
    MediaQualityProfile profile, {
    required String id,
    required String label,
    required int width,
    required int height,
    required int fps,
    required int quality,
    required String preset,
  }) =>
      profile.copyWith(
        id: id,
        label: label,
        width: min(profile.width, width),
        height: min(profile.height, height),
        targetFps: min(profile.targetFps, fps),
        jpegQuality: min(profile.jpegQuality, quality),
        cameraPresetKey: preset,
        audioFirst: true,
      );

  Map<String, Object?> toJson() => {
        'state': state.name,
        'audioOnly': audioOnly,
        'reasons': reasons,
      };
}

/// Combines thermal, power, codec and transport pressure into one deterministic
/// degradation decision. Degradation is immediate; profile upgrade hysteresis
/// remains the responsibility of [MediaQualitySelector].
class MediaResourceGovernor {
  const MediaResourceGovernor();

  MediaResourceGovernorDecision evaluate(MediaResourceGovernorInput input) {
    final reasons = <String>[];
    var severity = 0;

    void raise(int next, String reason) {
      severity = max(severity, next);
      reasons.add(reason);
    }

    switch (input.device.thermalState) {
      case DeviceThermalState.critical:
        raise(3, 'thermalCritical');
      case DeviceThermalState.serious:
        raise(2, 'thermalSerious');
      case DeviceThermalState.fair:
        raise(1, 'thermalFair');
      case DeviceThermalState.nominal || DeviceThermalState.unknown:
        break;
    }

    if (input.device.lowPowerMode && input.device.charging != true) {
      raise(1, 'lowPowerMode');
    }
    final battery = input.device.batteryLevelPercent;
    if (battery != null && input.device.charging != true) {
      if (battery <= 5) {
        raise(3, 'batteryCritical');
      } else if (battery <= 12) {
        raise(2, 'batteryLow');
      } else if (battery <= 20) {
        raise(1, 'batteryConstrained');
      }
    }

    if (input.networkTier == NetworkQualityTier.offline) {
      raise(3, 'networkOffline');
    } else if (input.networkTier == NetworkQualityTier.critical) {
      raise(2, 'networkCritical');
    } else if (input.networkTier == NetworkQualityTier.weak) {
      raise(1, 'networkWeak');
    }
    if (input.backpressure.consecutiveWriteFailures >= 2 ||
        input.backpressure.consecutiveSkippedAudioChunks > 0) {
      raise(2, 'transportBackpressure');
    } else if (input.backpressure.consecutiveSkippedVideoFrames >= 3 ||
        (input.backpressure.averageWriteDurationMs ?? 0) >= 120) {
      raise(1, 'videoBackpressure');
    }

    if ((input.videoEncodeP95Ms ?? 0) >= 350 ||
        input.preEncodeDropRatio >= .25) {
      raise(2, 'encoderOverloaded');
    } else if ((input.videoEncodeP95Ms ?? 0) >= 180 ||
        input.preEncodeDropRatio >= .10) {
      raise(1, 'encoderConstrained');
    }
    if (input.decoderCoalescedFrames >= 12) {
      raise(2, 'clientDecoderOverloaded');
    } else if (input.decoderCoalescedFrames >= 4) {
      raise(1, 'clientDecoderConstrained');
    }
    if (input.audioUnderruns > 0) raise(2, 'audioUnderrun');
    if (input.activeClientCount >= 4) raise(1, 'highClientTraffic');

    // Audio-only is useful only when an audio path actually exists. A
    // video-only watcher otherwise keeps a survival liveness stream.
    final state = switch (severity) {
      >= 3 when input.audioDemandAvailable => MediaDegradationState.audioOnly,
      >= 3 => MediaDegradationState.survival,
      2 => MediaDegradationState.survival,
      1 => MediaDegradationState.constrained,
      _ => MediaDegradationState.normal,
    };
    return MediaResourceGovernorDecision(
      state: state,
      reasons: List.unmodifiable(reasons),
    );
  }
}
