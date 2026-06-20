import '../../core/media/adaptive_media_profile.dart';
import '../../core/media/client_quality_tracker.dart';

class MediaQualitySelector {
  MediaQualitySelector({
    Duration upgradeCooldown = const Duration(seconds: 30),
    int Function()? nowMs,
  })  : _upgradeCooldown = upgradeCooldown,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Duration _upgradeCooldown;
  final int Function() _nowMs;
  MediaQualityProfile? _currentProfile;
  int? _stableSinceMs;

  MediaQualityProfile select({
    required DeviceCapabilityTier deviceTier,
    required NetworkQualityTier networkTier,
    required int activeClientCount,
    ClientQualityReport? worstReport,
  }) {
    final effectiveTier = _worseTier(
      networkTier,
      worstReport?.effectiveTier ?? NetworkQualityTier.unknown,
    );
    final desired = MediaQualityProfile.forDeviceTier(deviceTier)
        .adaptForNetwork(effectiveTier)
        .adaptForClientLoad(activeClientCount);
    if (activeClientCount == 0) {
      _currentProfile = desired;
      _stableSinceMs = null;
      return desired;
    }
    final current = _currentProfile;
    if (current == null) {
      _currentProfile = desired;
      _stableSinceMs = _nowMs();
      return desired;
    }
    final currentSeverity = _profileSeverity(current);
    final desiredSeverity = _profileSeverity(desired);
    if (desiredSeverity > currentSeverity) {
      _currentProfile = desired;
      _stableSinceMs = null;
      return desired;
    }
    if (desiredSeverity < currentSeverity) {
      if (worstReport?.recentlyReconnected ?? false) return current;
      final nowMs = _nowMs();
      _stableSinceMs ??= nowMs;
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
    _stableSinceMs ??= _nowMs();
    return desired;
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
    final nextTier = switch (_profileSeverity(current)) {
      >= 4 => NetworkQualityTier.critical,
      3 => NetworkQualityTier.weak,
      _ => NetworkQualityTier.good,
    };
    final stepped = MediaQualityProfile.forDeviceTier(deviceTier)
        .adaptForNetwork(nextTier)
        .adaptForClientLoad(activeClientCount);
    return _profileSeverity(stepped) < _profileSeverity(current)
        ? stepped
        : desired;
  }

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

  int _profileSeverity(MediaQualityProfile profile) {
    if (profile.id.contains('survival') || profile.targetFps <= 1) return 4;
    if (profile.height <= 240) return 3;
    if (profile.height <= 360) return 2;
    return 1;
  }
}
