import '../../core/media/adaptive_media_profile.dart';
import '../../core/media/client_quality_tracker.dart';
import 'stream_backpressure_gate.dart';

class UtilityBasedProfileSelector {
  const UtilityBasedProfileSelector();

  MediaQualityProfile choose({
    required DeviceCapabilityTier deviceTier,
    required NetworkQualityTier networkTier,
    required int activeClientCount,
    required MediaQualityProfile? currentProfile,
    Iterable<ClientQualityReport> qualityReports = const [],
    StreamBackpressureMetrics backpressureMetrics =
        const StreamBackpressureMetrics(),
  }) {
    final base = MediaQualityProfile.forDeviceTier(deviceTier);
    final signals = _QualitySignals.from(
      networkTier: networkTier,
      reports: qualityReports,
      backpressureMetrics: backpressureMetrics,
    );

    final planned = switch (_plannedTier(
      networkTier: signals.effectiveTier,
      activeClientCount: activeClientCount,
      videoTrouble: signals.videoTrouble,
      audioTrouble: signals.audioTrouble,
      backpressureMetrics: backpressureMetrics,
    )) {
      _PlannedMediaTier.full => base,
      _PlannedMediaTier.shared => base.adaptForClientLoad(activeClientCount),
      _PlannedMediaTier.weak => base
          .adaptForNetwork(NetworkQualityTier.weak)
          .adaptForClientLoad(activeClientCount),
      _PlannedMediaTier.critical => base
          .adaptForNetwork(NetworkQualityTier.critical)
          .adaptForClientLoad(activeClientCount),
      _PlannedMediaTier.survival => base
          .adaptForNetwork(NetworkQualityTier.offline)
          .adaptForClientLoad(activeClientCount),
    };

    if (!signals.audioTrouble) return planned;
    return planned.copyWith(
      id: '${planned.id}_audio_first',
      label: '${planned.label} / ses öncelikli',
      targetFps: planned.targetFps > 10 ? 10 : planned.targetFps,
      audioFirst: true,
    );
  }

  _PlannedMediaTier _plannedTier({
    required NetworkQualityTier networkTier,
    required int activeClientCount,
    required bool videoTrouble,
    required bool audioTrouble,
    required StreamBackpressureMetrics backpressureMetrics,
  }) {
    if (networkTier == NetworkQualityTier.offline) {
      return _PlannedMediaTier.survival;
    }
    if (activeClientCount >= 4) return _PlannedMediaTier.weak;
    if (networkTier == NetworkQualityTier.critical || videoTrouble) {
      return _PlannedMediaTier.critical;
    }
    if (networkTier == NetworkQualityTier.weak ||
        backpressureMetrics.averageWriteDurationMs != null &&
            backpressureMetrics.averageWriteDurationMs! >= 700) {
      return _PlannedMediaTier.weak;
    }
    if (activeClientCount >= 2) return _PlannedMediaTier.shared;
    if (audioTrouble) return _PlannedMediaTier.shared;
    return _PlannedMediaTier.full;
  }

  static NetworkQualityTier transportTier(ClientQualityReport report) {
    if (report.consecutiveFailures >= 3) return NetworkQualityTier.offline;
    if (report.rttMs != null) {
      if (report.rttMs! >= 1000) return NetworkQualityTier.critical;
      if (report.rttMs! >= 500) return NetworkQualityTier.weak;
      if (report.rttMs! >= 220) return NetworkQualityTier.good;
      return NetworkQualityTier.excellent;
    }
    final audioOnlyProblem =
        hasAudioProblem(report) && !hasVideoProblem(report);
    if (audioOnlyProblem &&
        report.networkTier.severity >= NetworkQualityTier.critical.severity) {
      return NetworkQualityTier.unknown;
    }
    return report.networkTier;
  }

  static bool hasVideoProblem(ClientQualityReport report) =>
      report.streamTimedOut ||
      _atLeast(report.videoFrameGapMs, 5000) ||
      report.skippedVideoFrames >= 8 ||
      report.consecutiveFailures >= 3;

  static bool hasAudioProblem(ClientQualityReport report) =>
      report.audioUnderrun ||
      report.skippedAudioChunks > 0 ||
      _atLeast(report.audioGapMs, 1800);

  static bool _atLeast(int? value, int threshold) =>
      value != null && value >= threshold;
}

enum _PlannedMediaTier {
  full,
  shared,
  weak,
  critical,
  survival,
}

class _QualitySignals {
  const _QualitySignals({
    required this.effectiveTier,
    required this.videoTrouble,
    required this.audioTrouble,
  });

  factory _QualitySignals.from({
    required NetworkQualityTier networkTier,
    required Iterable<ClientQualityReport> reports,
    required StreamBackpressureMetrics backpressureMetrics,
  }) {
    var effectiveTier = networkTier;
    var videoTrouble = backpressureMetrics.consecutiveWriteFailures >= 2 ||
        backpressureMetrics.skippedVideoFrames >= 12;
    var audioTrouble = backpressureMetrics.skippedAudioChunks > 0;
    for (final report in reports) {
      effectiveTier = effectiveTier
          .worse(UtilityBasedProfileSelector.transportTier(report));
      videoTrouble =
          videoTrouble || UtilityBasedProfileSelector.hasVideoProblem(report);
      audioTrouble =
          audioTrouble || UtilityBasedProfileSelector.hasAudioProblem(report);
    }
    return _QualitySignals(
      effectiveTier: effectiveTier,
      videoTrouble: videoTrouble,
      audioTrouble: audioTrouble,
    );
  }

  final NetworkQualityTier effectiveTier;
  final bool videoTrouble;
  final bool audioTrouble;
}
