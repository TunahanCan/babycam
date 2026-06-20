import 'dart:math';

import '../../core/media/adaptive_media_profile.dart';

class JpegByteBudgetController {
  JpegByteBudgetController({
    this.kp = 8.0,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final double kp;
  final int Function() _nowMs;
  final _states = <String, _JpegBudgetState>{};

  int qualityFor(MediaQualityProfile profile) =>
      _stateFor(profile).currentQuality;

  void recordEncodedFrame(
    MediaQualityProfile profile, {
    required int byteLength,
    int? atMs,
  }) {
    final state = _stateFor(profile);
    final nowMs = atMs ?? _nowMs();
    state.windowStartedAtMs ??= nowMs;
    state.bytesInWindow += byteLength;
    final elapsedMs = max(1, nowMs - state.windowStartedAtMs!);
    if (elapsedMs < 1000) return;

    final actualBytesPerSecond = state.bytesInWindow * 1000 / elapsedMs;
    final target = targetBytesPerSecond(profile);
    final errorRatio = (actualBytesPerSecond - target) / target;
    final delta = kp * errorRatio;
    final next = (state.currentQuality - delta).round();
    final ceiling = min(58, profile.jpegQuality);
    state.currentQuality = next.clamp(32, ceiling).toInt();
    state.lastActualBytesPerSecond = actualBytesPerSecond.round();
    state.windowStartedAtMs = nowMs;
    state.bytesInWindow = 0;
  }

  int targetBytesPerSecond(MediaQualityProfile profile) {
    if (profile.id.contains('survival') ||
        profile.targetFps <= 1 ||
        profile.height <= 240 && profile.jpegQuality <= 36) {
      return 18 * 1024;
    }
    if (profile.id.contains('critical') || profile.height <= 240) {
      return 45 * 1024;
    }
    if (profile.id.contains('weak') || profile.height <= 360) {
      return 120 * 1024;
    }
    return 275 * 1024;
  }

  int? lastActualBytesPerSecond(MediaQualityProfile profile) =>
      _states[profile.id]?.lastActualBytesPerSecond;

  void reset() {
    _states.clear();
  }

  _JpegBudgetState _stateFor(MediaQualityProfile profile) =>
      _states.putIfAbsent(
        profile.id,
        () => _JpegBudgetState(profile.jpegQuality.clamp(32, 58).toInt()),
      );
}

class _JpegBudgetState {
  _JpegBudgetState(this.currentQuality);

  int currentQuality;
  int? windowStartedAtMs;
  int bytesInWindow = 0;
  int? lastActualBytesPerSecond;
}
