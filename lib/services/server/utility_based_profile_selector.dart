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
    final reports = qualityReports.toList(growable: false);
    final base = MediaQualityProfile.forDeviceTier(deviceTier);
    final effectiveTier = _effectiveNetworkTier(networkTier, reports);
    final videoTrouble =
        _videoTrouble(reports, backpressureMetrics: backpressureMetrics);
    final audioTrouble =
        _audioTrouble(reports, backpressureMetrics: backpressureMetrics);

    final planned = switch (_plannedTier(
      networkTier: effectiveTier,
      activeClientCount: activeClientCount,
      videoTrouble: videoTrouble,
      audioTrouble: audioTrouble,
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

    if (!audioTrouble) return planned;
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

  NetworkQualityTier _effectiveNetworkTier(
    NetworkQualityTier networkTier,
    List<ClientQualityReport> reports,
  ) {
    var effective = networkTier;
    for (final report in reports) {
      effective = _worseTier(effective, _transportTier(report));
    }
    return effective;
  }

  NetworkQualityTier _transportTier(ClientQualityReport report) {
    if (report.consecutiveFailures >= 3) return NetworkQualityTier.offline;
    if (report.rttMs != null) {
      if (report.rttMs! >= 1000) return NetworkQualityTier.critical;
      if (report.rttMs! >= 500) return NetworkQualityTier.weak;
      if (report.rttMs! >= 220) return NetworkQualityTier.good;
      return NetworkQualityTier.excellent;
    }
    final audioOnlyProblem =
        _hasAudioProblem(report) && !_hasVideoProblem(report);
    if (audioOnlyProblem &&
        _severity(report.networkTier) >=
            _severity(NetworkQualityTier.critical)) {
      return NetworkQualityTier.unknown;
    }
    return report.networkTier;
  }

  bool _videoTrouble(
    List<ClientQualityReport> reports, {
    required StreamBackpressureMetrics backpressureMetrics,
  }) {
    if (backpressureMetrics.consecutiveWriteFailures >= 2 ||
        backpressureMetrics.skippedVideoFrames >= 12) {
      return true;
    }
    return reports.any((report) => _hasVideoProblem(report));
  }

  bool _audioTrouble(
    List<ClientQualityReport> reports, {
    required StreamBackpressureMetrics backpressureMetrics,
  }) {
    if (backpressureMetrics.skippedAudioChunks > 0) return true;
    return reports.any((report) => _hasAudioProblem(report));
  }

  bool _hasVideoProblem(ClientQualityReport report) =>
      report.streamTimedOut ||
      _atLeast(report.videoFrameGapMs, 5000) ||
      report.skippedVideoFrames >= 8 ||
      report.consecutiveFailures >= 3;

  bool _hasAudioProblem(ClientQualityReport report) =>
      report.audioUnderrun ||
      report.skippedAudioChunks > 0 ||
      _atLeast(report.audioGapMs, 1800);

  NetworkQualityTier _worseTier(
    NetworkQualityTier current,
    NetworkQualityTier next,
  ) =>
      _severity(next) > _severity(current) ? next : current;

  int _severity(NetworkQualityTier tier) => switch (tier) {
        NetworkQualityTier.offline => 5,
        NetworkQualityTier.critical => 4,
        NetworkQualityTier.weak => 3,
        NetworkQualityTier.good => 2,
        NetworkQualityTier.excellent => 1,
        NetworkQualityTier.unknown => 0,
      };

  bool _atLeast(int? value, int threshold) =>
      value != null && value >= threshold;
}

enum _PlannedMediaTier {
  full,
  shared,
  weak,
  critical,
  survival,
}
