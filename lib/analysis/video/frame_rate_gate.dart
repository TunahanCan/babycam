/// Gates analysis so expensive work runs at a target FPS independent of camera FPS.
class FrameRateGate {
  FrameRateGate({required int fps})
      : fps = fps <= 0 ? 1 : fps,
        _intervalMs = fps <= 0 ? 1000 : (1000 / fps).ceil();

  final int fps;
  final int _intervalMs;
  int? _lastRunMs;

  /// Returns true when the frame at [timestampMs] should be analyzed.
  bool shouldRun(int timestampMs) {
    final last = _lastRunMs;
    if (last == null || timestampMs < last) {
      _lastRunMs = timestampMs;
      return true;
    }
    if (timestampMs - last >= _intervalMs) {
      _lastRunMs = timestampMs;
      return true;
    }
    return false;
  }

  /// Clears previous timing state.
  void reset() => _lastRunMs = null;
}
