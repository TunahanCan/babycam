import '../../core/media/adaptive_media_profile.dart';
import '../../core/media/client_quality_tracker.dart';
import 'stream_backpressure_gate.dart';
import 'utility_based_profile_selector.dart';

class MediaQualitySelector {
  MediaQualitySelector({
    Duration upgradeCooldown = const Duration(seconds: 30),
    int Function()? nowMs,
    UtilityBasedProfileSelector? utilitySelector,
  })  : _upgradeCooldown = upgradeCooldown,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _utilitySelector =
            utilitySelector ?? const UtilityBasedProfileSelector();

  final Duration _upgradeCooldown;
  final int Function() _nowMs;
  final UtilityBasedProfileSelector _utilitySelector;
  MediaQualityProfile? _currentProfile;
  int? _stableSinceMs;

  MediaQualityProfile select({
    required DeviceCapabilityTier deviceTier,
    required NetworkQualityTier networkTier,
    required int activeClientCount,
    ClientQualityReport? worstReport,
    Iterable<ClientQualityReport> qualityReports = const [],
    StreamBackpressureMetrics backpressureMetrics =
        const StreamBackpressureMetrics(),
  }) {
    final reports = [
      ...qualityReports,
      if (worstReport != null &&
          !qualityReports
              .any((report) => report.clientId == worstReport.clientId))
        worstReport,
    ];
    final desired = _utilitySelector.choose(
      deviceTier: deviceTier,
      networkTier: networkTier,
      activeClientCount: activeClientCount,
      currentProfile: _currentProfile,
      qualityReports: reports,
      backpressureMetrics: backpressureMetrics,
    );
    if (activeClientCount == 0) {
      _currentProfile = desired;
      _stableSinceMs = null;
      return desired;
    }
    final current = _currentProfile;
    if (current == null) {
      _currentProfile = desired;
      _stableSinceMs = null;
      return desired;
    }
    final budgetChange = _compareVideoBudget(desired, current);
    if (budgetChange < 0) {
      _currentProfile = desired;
      _stableSinceMs = null;
      return desired;
    }
    if (budgetChange > 0) {
      if (reports.any((report) => report.recentlyReconnected)) {
        _stableSinceMs = null;
        return current;
      }
      final nowMs = _nowMs();
      if (_stableSinceMs == null || nowMs < _stableSinceMs!) {
        _stableSinceMs = nowMs;
      }
      if (nowMs - _stableSinceMs! < _upgradeCooldown.inMilliseconds) {
        return current;
      }
      final upgraded = _oneStepUpgrade(
        current: current,
        desired: desired,
        deviceTier: deviceTier,
        activeClientCount: activeClientCount,
      );
      _currentProfile = upgraded;
      _stableSinceMs = nowMs;
      return upgraded;
    }
    _currentProfile = desired;
    // Time spent needing the current restricted profile is not evidence that
    // a higher bitrate is sustainable. A renewed bad report also interrupts
    // an upgrade window that had already started.
    _stableSinceMs = null;
    return desired;
  }

  /// Computes the profile that would be selected without advancing hysteresis
  /// state. This lets latency-sensitive HTTP responses report the pending
  /// decision while the serialized camera apply remains asynchronous.
  MediaQualityProfile preview({
    required DeviceCapabilityTier deviceTier,
    required NetworkQualityTier networkTier,
    required int activeClientCount,
    ClientQualityReport? worstReport,
    Iterable<ClientQualityReport> qualityReports = const [],
    StreamBackpressureMetrics backpressureMetrics =
        const StreamBackpressureMetrics(),
  }) {
    final savedProfile = _currentProfile;
    final savedStableSinceMs = _stableSinceMs;
    try {
      return select(
        deviceTier: deviceTier,
        networkTier: networkTier,
        activeClientCount: activeClientCount,
        worstReport: worstReport,
        qualityReports: qualityReports,
        backpressureMetrics: backpressureMetrics,
      );
    } finally {
      _currentProfile = savedProfile;
      _stableSinceMs = savedStableSinceMs;
    }
  }

  void reset() {
    _currentProfile = null;
    _stableSinceMs = null;
  }

  MediaQualityProfile _oneStepUpgrade({
    required MediaQualityProfile current,
    required MediaQualityProfile desired,
    required DeviceCapabilityTier deviceTier,
    required int activeClientCount,
  }) {
    final base = MediaQualityProfile.forDeviceTier(deviceTier);
    var next = desired;
    for (final tier in const [
      NetworkQualityTier.offline,
      NetworkQualityTier.critical,
      NetworkQualityTier.weak,
      NetworkQualityTier.good,
    ]) {
      final candidate =
          base.adaptForNetwork(tier).adaptForClientLoad(activeClientCount);
      if (_compareVideoBudget(candidate, current) > 0 &&
          _compareVideoBudget(candidate, next) < 0) {
        next = candidate;
      }
    }
    return desired.audioFirst && !next.audioFirst
        ? next.copyWith(audioFirst: true)
        : next;
  }

  // Resolution alone misses 360p/5fps -> 360p/8fps recovery and groups shared
  // 480p with full 720p. Include every video budget dimension in hysteresis.
  int _compareVideoBudget(MediaQualityProfile a, MediaQualityProfile b) {
    final pixels = (a.width * a.height).compareTo(b.width * b.height);
    if (pixels != 0) return pixels;
    final fps = a.targetFps.compareTo(b.targetFps);
    if (fps != 0) return fps;
    return a.jpegQuality.compareTo(b.jpegQuality);
  }
}
