import '../../core/media/adaptive_media_profile.dart';

/// Runs profile decisions one at a time and lets media lifecycle changes
/// invalidate work that was queued for an older camera generation.
class MediaProfileApplyQueue {
  Future<void> _tail = Future<void>.value();
  int _generation = 0;

  bool isCurrent(int generation) => generation == _generation;

  Future<void> enqueue(
    Future<void> Function(int generation) operation,
  ) {
    final generation = _generation;
    final result = _tail.then<void>((_) async {
      if (!isCurrent(generation)) return;
      await operation(generation);
    });
    // A failed operation is still returned to its caller, while the recovered
    // tail allows later reports to keep applying in order.
    _tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void invalidate() {
    _generation++;
  }
}

class MediaProfileCameraRestartPolicy {
  const MediaProfileCameraRestartPolicy();

  bool requiresRestart(
    MediaQualityProfile previous,
    MediaQualityProfile next,
  ) =>
      previous.cameraPresetKey != next.cameraPresetKey;

  /// Keep the camera source at the device's normal ceiling. Network profiles
  /// are paced down by MediaFrameBudget, so an FPS-only recovery can speed up
  /// again without rebuilding the controller.
  int captureFps({
    required MediaQualityProfile deviceProfile,
    required MediaQualityProfile activeProfile,
  }) =>
      deviceProfile.targetFps >= activeProfile.targetFps
          ? deviceProfile.targetFps
          : activeProfile.targetFps;
}
