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
    final emergencyTier = _emergencyTier(
      networkTier: networkTier,
      reports: reports,
      activeClientCount: activeClientCount,
    );
    if (emergencyTier != null) {
      return MediaQualityProfile.forDeviceTier(deviceTier)
          .adaptForNetwork(emergencyTier)
          .adaptForClientLoad(activeClientCount);
    }
    final effectiveTier = _effectiveNetworkTier(networkTier, reports);
    if (_severity(effectiveTier) >= _severity(NetworkQualityTier.weak)) {
      return MediaQualityProfile.forDeviceTier(deviceTier)
          .adaptForNetwork(effectiveTier)
          .adaptForClientLoad(activeClientCount);
    }

    final candidates = _candidatesFor(
      deviceTier: deviceTier,
      activeClientCount: activeClientCount,
    );
    var best = candidates.first;
    var bestUtility = double.negativeInfinity;
    for (final profile in candidates) {
      final utility = _utility(
        profile: profile,
        reports: reports,
        backpressureMetrics: backpressureMetrics,
        activeClientCount: activeClientCount,
        currentProfile: currentProfile,
      );
      if (utility > bestUtility) {
        best = profile;
        bestUtility = utility;
      }
    }
    return best;
  }

  List<MediaQualityProfile> _candidatesFor({
    required DeviceCapabilityTier deviceTier,
    required int activeClientCount,
  }) {
    final base = MediaQualityProfile.forDeviceTier(deviceTier);
    final normal = base
        .adaptForNetwork(NetworkQualityTier.good)
        .adaptForClientLoad(activeClientCount);
    final weak = base
        .adaptForNetwork(NetworkQualityTier.weak)
        .adaptForClientLoad(activeClientCount);
    final critical = base
        .adaptForNetwork(NetworkQualityTier.critical)
        .adaptForClientLoad(activeClientCount);
    final survival = base
        .adaptForNetwork(NetworkQualityTier.offline)
        .adaptForClientLoad(activeClientCount);
    if (activeClientCount >= 4) return [critical, survival];
    if (activeClientCount >= 2) return [weak, critical, survival];
    return [normal, weak, critical, survival];
  }

  NetworkQualityTier? _emergencyTier({
    required NetworkQualityTier networkTier,
    required List<ClientQualityReport> reports,
    required int activeClientCount,
  }) {
    if (networkTier == NetworkQualityTier.offline) {
      return NetworkQualityTier.offline;
    }
    for (final report in reports) {
      if (report.streamTimedOut ||
          report.audioUnderrun ||
          report.skippedAudioChunks > 0 ||
          _atLeast(report.videoFrameGapMs, 5000) ||
          _atLeast(report.audioGapMs, 1500)) {
        return activeClientCount >= 4
            ? NetworkQualityTier.offline
            : NetworkQualityTier.critical;
      }
    }
    return null;
  }

  NetworkQualityTier _effectiveNetworkTier(
    NetworkQualityTier networkTier,
    List<ClientQualityReport> reports,
  ) {
    var effective = networkTier;
    for (final report in reports) {
      effective = _worseTier(effective, report.effectiveTier);
    }
    return effective;
  }

  double _utility({
    required MediaQualityProfile profile,
    required List<ClientQualityReport> reports,
    required StreamBackpressureMetrics backpressureMetrics,
    required int activeClientCount,
    required MediaQualityProfile? currentProfile,
  }) {
    return _visualQuality(profile) -
        _stallPenalty(reports) -
        _audioPenalty(reports, backpressureMetrics) -
        _backpressurePenalty(backpressureMetrics, profile) -
        _clientLoadPenalty(activeClientCount) -
        _switchPenalty(profile, currentProfile);
  }

  double _visualQuality(MediaQualityProfile profile) {
    final resolutionScore = (profile.height / 480).clamp(0.0, 1.0);
    final fpsScore = (profile.targetFps / 8).clamp(0.0, 1.0);
    final jpegScore = (profile.jpegQuality / 58).clamp(0.0, 1.0);
    return (resolutionScore * 1.2) + (fpsScore * 0.8) + (jpegScore * 0.5);
  }

  double _stallPenalty(List<ClientQualityReport> reports) {
    final maxGap = reports
        .map((report) => report.videoFrameGapMs ?? 0)
        .fold<int>(0, (max, value) => value > max ? value : max);
    return (maxGap / 5000).clamp(0.0, 2.0) * 1.4;
  }

  double _audioPenalty(
    List<ClientQualityReport> reports,
    StreamBackpressureMetrics metrics,
  ) {
    final maxGap = reports
        .map((report) => report.audioGapMs ?? 0)
        .fold<int>(0, (max, value) => value > max ? value : max);
    final underrun = reports.any((report) => report.audioUnderrun);
    final skipped = reports.fold<int>(
      metrics.skippedAudioChunks,
      (sum, report) => sum + report.skippedAudioChunks,
    );
    return (maxGap / 1500).clamp(0.0, 2.0) * 1.8 +
        (underrun ? 3.0 : 0.0) +
        skipped * 0.25;
  }

  double _backpressurePenalty(
    StreamBackpressureMetrics metrics,
    MediaQualityProfile profile,
  ) {
    final profileCost =
        ((profile.height / 240) * (profile.targetFps / 2)).clamp(1.0, 8.0);
    final base = (metrics.skippedVideoFrames / 12).clamp(0.0, 2.0) +
        (metrics.averageWriteDurationMs == null
            ? 0.0
            : (metrics.averageWriteDurationMs! / 500).clamp(0.0, 1.0));
    return base * profileCost * 0.35;
  }

  double _clientLoadPenalty(int activeClientCount) =>
      activeClientCount <= 1 ? 0.0 : activeClientCount * 0.18;

  double _switchPenalty(
    MediaQualityProfile profile,
    MediaQualityProfile? currentProfile,
  ) =>
      currentProfile == null || currentProfile.id == profile.id ? 0.0 : 0.35;

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
