import 'dart:math';
import 'dart:typed_data';

import 'frame_rate_gate.dart';
import 'luma_downsampler.dart';
import 'luma_frame.dart';
import 'motion_analysis_config.dart';
import 'motion_analysis_result.dart';

/// Synchronous, pure-Dart luma motion analyzer with ROI, adaptive background,
/// smoothing, hysteresis, and minimum-duration decisions.
class MotionAnalyzerV2 {
  MotionAnalyzerV2({MotionAnalysisConfig config = const MotionAnalysisConfig()})
      : _config = config,
        _gate = FrameRateGate(fps: config.analysisFps) {
    _allocateBuffers();
  }

  final MotionAnalysisConfig _config;
  final FrameRateGate _gate;
  Uint8List _current = Uint8List(0);
  Float64List _background = Float64List(0);
  bool _hasBackground = false;
  double _smoothedScore = 0;
  double _noiseFloor = 0;
  bool _isMotion = false;
  int? _candidateStartMs;
  MotionAnalysisResult? _lastResult;
  int _analyzedFrames = 0;

  MotionAnalysisConfig get config => _config;

  /// Analyzes a luma frame and returns deterministic metrics/flags.
  MotionAnalysisResult analyze(LumaFrame frame) {
    final sw = Stopwatch()..start();
    if (!_gate.shouldRun(frame.timestampMs)) {
      final last = _lastResult;
      return MotionAnalysisResult(
        timestampMs: frame.timestampMs,
        score: last?.score ?? 0,
        rawScore: last?.rawScore ?? 0,
        activeAreaRatio: last?.activeAreaRatio ?? 0,
        meanDiff: last?.meanDiff ?? 0,
        currentMeanLuma: last?.currentMeanLuma ?? 0,
        backgroundMeanLuma: last?.backgroundMeanLuma ?? 0,
        globalLumaShift: last?.globalLumaShift ?? 0,
        isMotion: last?.isMotion ?? false,
        isGlobalLightChange: last?.isGlobalLightChange ?? false,
        skippedByFrameRateGate: true,
        invalidFrame: false,
        processingTimeMicros: sw.elapsedMicroseconds,
      );
    }

    final downsampler = LumaDownsampler(
      outputWidth: _config.downsampleWidth,
      outputHeight: _config.downsampleHeight,
    );
    if (!downsampler.downsample(frame, _current)) {
      return _finish(_invalid(frame.timestampMs, sw.elapsedMicroseconds));
    }

    final count = _current.length;
    if (!_hasBackground || _background.length != count) {
      for (var i = 0; i < count; i++) {
        _background[i] = _current[i].toDouble();
      }
      _hasBackground = true;
      _analyzedFrames = 1;
      return _finish(_result(frame.timestampMs, sw.elapsedMicroseconds));
    }

    var total = 0;
    var currentSum = 0.0;
    var backgroundSum = 0.0;
    for (var i = 0; i < count; i++) {
      if (_inRoi(i)) {
        total++;
        currentSum += _current[i];
        backgroundSum += _background[i];
      }
    }
    if (total == 0) return _finish(_invalid(frame.timestampMs, sw.elapsedMicroseconds));

    final currentMean = currentSum / total;
    final backgroundMean = backgroundSum / total;
    final globalShift = currentMean - backgroundMean;
    final threshold = max(_config.minPixelDiff, _noiseFloor * _config.noiseMultiplier);
    var active = 0;
    var rawActive = 0;
    var diffSum = 0.0;
    var allDiffSum = 0.0;

    for (var i = 0; i < count; i++) {
      if (!_inRoi(i)) continue;
      final rawDiff = (_current[i] - _background[i]).abs().toDouble();
      if (rawDiff > threshold) rawActive++;
      final diff = (_current[i] - globalShift - _background[i]).abs().toDouble();
      allDiffSum += diff;
      if (diff > threshold) {
        active++;
        diffSum += diff;
      }
    }

    final activeAreaRatio = active / total;
    final rawActiveRatio = rawActive / total;
    final meanDiff = diffSum / max(active, 1);
    var rawScore = activeAreaRatio < _config.minActiveAreaRatio
        ? 0.0
        : _clamp01(0.65 * (activeAreaRatio / 0.10) + 0.35 * (meanDiff / 64.0));
    final isGlobalLightChange = rawActiveRatio > _config.globalLightChangeRatio ||
        (rawActiveRatio > 0.40 && activeAreaRatio < rawActiveRatio * 0.25);
    if (isGlobalLightChange) rawScore = 0;

    _smoothedScore = _clamp01(
      _smoothedScore * (1 - _config.smoothingAlpha) +
          rawScore * _config.smoothingAlpha,
    );
    _updateMotionState(frame.timestampMs, isGlobalLightChange);

    if (!_isMotion && !isGlobalLightChange && rawScore < _config.motionOffThreshold) {
      final observedNoise = allDiffSum / total;
      _noiseFloor = _noiseFloor * 0.90 + observedNoise * 0.10;
    }

    final alpha = isGlobalLightChange
        ? _config.stableBackgroundAlpha * 0.5
        : (_isMotion ? _config.motionBackgroundAlpha : _config.stableBackgroundAlpha);
    final initAlpha = _analyzedFrames < 5 ? _config.initializationAlpha : alpha;
    for (var i = 0; i < count; i++) {
      _background[i] = _background[i] * (1 - initAlpha) + _current[i] * initAlpha;
    }
    _analyzedFrames++;

    return _finish(MotionAnalysisResult(
      timestampMs: frame.timestampMs,
      score: _clamp01(_smoothedScore),
      rawScore: _clamp01(rawScore),
      activeAreaRatio: activeAreaRatio,
      meanDiff: meanDiff,
      currentMeanLuma: currentMean,
      backgroundMeanLuma: backgroundMean,
      globalLumaShift: globalShift,
      isMotion: _isMotion && !isGlobalLightChange,
      isGlobalLightChange: isGlobalLightChange,
      skippedByFrameRateGate: false,
      invalidFrame: false,
      processingTimeMicros: sw.elapsedMicroseconds,
    ));
  }

  /// Resets background, smoothing, gate, and hysteresis state.
  void reset() {
    _gate.reset();
    _hasBackground = false;
    _smoothedScore = 0;
    _noiseFloor = _config.minPixelDiff / _config.noiseMultiplier;
    _isMotion = false;
    _candidateStartMs = null;
    _lastResult = null;
    _analyzedFrames = 0;
  }

  /// Returns lightweight analyzer diagnostics.
  Map<String, Object?> diagnostics() => {
        'hasBackground': _hasBackground,
        'smoothedScore': _smoothedScore,
        'noiseFloor': _noiseFloor,
        'isMotion': _isMotion,
        'candidateStartMs': _candidateStartMs,
        'analyzedFrames': _analyzedFrames,
        'config': _config.toJson(),
      };

  void _allocateBuffers() {
    final length = max(0, _config.downsampleWidth * _config.downsampleHeight).toInt();
    _current = Uint8List(length);
    _background = Float64List(length);
    _noiseFloor = _config.minPixelDiff / _config.noiseMultiplier;
  }

  bool _inRoi(int index) {
    final roi = _config.roi;
    if (roi == null) return true;
    final x = index % _config.downsampleWidth;
    final y = index ~/ _config.downsampleWidth;
    return roi.containsNormalized(
      (x + 0.5) / _config.downsampleWidth,
      (y + 0.5) / _config.downsampleHeight,
    );
  }

  void _updateMotionState(int timestampMs, bool isGlobalLightChange) {
    if (isGlobalLightChange) {
      _isMotion = false;
      _candidateStartMs = null;
      return;
    }
    if (_isMotion) {
      if (_smoothedScore <= _config.motionOffThreshold) {
        _isMotion = false;
        _candidateStartMs = null;
      }
      return;
    }
    if (_smoothedScore >= _config.motionOnThreshold) {
      _candidateStartMs ??= timestampMs;
      if (timestampMs - _candidateStartMs! >= _config.minMotionDurationMs) {
        _isMotion = true;
      }
    } else if (_smoothedScore <= _config.motionOffThreshold) {
      _candidateStartMs = null;
    }
  }

  MotionAnalysisResult _result(int timestampMs, int micros) => MotionAnalysisResult(
        timestampMs: timestampMs,
        score: 0,
        rawScore: 0,
        activeAreaRatio: 0,
        meanDiff: 0,
        currentMeanLuma: 0,
        backgroundMeanLuma: 0,
        globalLumaShift: 0,
        isMotion: false,
        isGlobalLightChange: false,
        skippedByFrameRateGate: false,
        invalidFrame: false,
        processingTimeMicros: micros,
      );

  MotionAnalysisResult _invalid(int timestampMs, int micros) => MotionAnalysisResult(
        timestampMs: timestampMs,
        score: 0,
        rawScore: 0,
        activeAreaRatio: 0,
        meanDiff: 0,
        currentMeanLuma: 0,
        backgroundMeanLuma: 0,
        globalLumaShift: 0,
        isMotion: false,
        isGlobalLightChange: false,
        skippedByFrameRateGate: false,
        invalidFrame: true,
        processingTimeMicros: micros,
      );

  MotionAnalysisResult _finish(MotionAnalysisResult result) {
    _lastResult = result;
    return result;
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0);
}
