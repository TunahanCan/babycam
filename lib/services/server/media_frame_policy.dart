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
