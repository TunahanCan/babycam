class MediaFrameBudget {
  MediaFrameBudget({this.minInterval = const Duration(milliseconds: 120)});

  final Duration minInterval;
  int? _lastAcceptedMs;

  bool shouldProcess(int timestampMs) {
    final lastAcceptedMs = _lastAcceptedMs;
    if (lastAcceptedMs != null &&
        timestampMs - lastAcceptedMs < minInterval.inMilliseconds) {
      return false;
    }
    _lastAcceptedMs = timestampMs;
    return true;
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
