import '../../core/media/adaptive_media_profile.dart';

class MediaFrameBudget {
  MediaFrameBudget({Duration minInterval = const Duration(milliseconds: 120)})
      : _minInterval = minInterval;

  Duration _minInterval;
  int? _lastAcceptedMs;

  Duration get minInterval => _minInterval;

  bool shouldProcess(int timestampMs) {
    final lastAcceptedMs = _lastAcceptedMs;
    if (lastAcceptedMs != null &&
        timestampMs - lastAcceptedMs < _minInterval.inMilliseconds) {
      return false;
    }
    _lastAcceptedMs = timestampMs;
    return true;
  }

  void updateMinInterval(Duration minInterval) {
    if (_minInterval == minInterval) return;
    _minInterval = minInterval;
    reset();
  }

  void reset() {
    _lastAcceptedMs = null;
  }
}

class MediaEncodingPolicy {
  const MediaEncodingPolicy();

  bool shouldEncodeJpeg({
    required bool hasMjpegClients,
    required bool legacyWebSocketEnabled,
  }) =>
      hasMjpegClients || legacyWebSocketEnabled;
}

class FrameBudgetManager {
  const FrameBudgetManager();

  int targetFps({
    required double motionEnergy,
    required bool cryActive,
    required NetworkQualityTier networkTier,
    required int activeClients,
  }) {
    if (activeClients >= 4) return cryActive ? 2 : 1;
    if (networkTier == NetworkQualityTier.critical ||
        networkTier == NetworkQualityTier.offline) {
      return cryActive ? 2 : 1;
    }
    if (networkTier == NetworkQualityTier.weak) {
      return motionEnergy < 0.04 && !cryActive ? 2 : 5;
    }
    return motionEnergy < 0.04 && !cryActive ? 3 : 8;
  }
}
