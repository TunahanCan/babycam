import 'dart:async';

import '../../analysis/alert/alert_engine.dart';
import '../../analysis/alert/alert_event.dart';
import '../../analysis/audio/audio_analysis_result.dart';
import '../../analysis/audio/audio_chunk.dart';
import '../../analysis/audio/cry_audio_analyzer_v2.dart';
import '../../analysis/video/frame_rate_gate.dart';
import '../../analysis/video/luma_frame.dart';
import '../../analysis/video/motion_analysis_result.dart';
import '../../analysis/video/motion_analyzer_v2.dart';
import 'media_analysis_metrics.dart';

class MediaAnalysisCoordinator {
  MediaAnalysisCoordinator({
    required MotionAnalyzerV2 motionAnalyzer,
    required CryAudioAnalyzerV2 audioAnalyzer,
    required AlertEngine alertEngine,
    required MediaAnalysisMetrics metrics,
    void Function(String message)? onLog,
    void Function(AudioAnalysisResult result)? onAudioResult,
    void Function(MotionAnalysisResult result)? onMotionResult,
  })  : _motionAnalyzer = motionAnalyzer,
        _audioAnalyzer = audioAnalyzer,
        _alertEngine = alertEngine,
        _metrics = metrics,
        _motionFrameGate =
            FrameRateGate(fps: motionAnalyzer.config.analysisFps),
        _onLog = onLog,
        _onAudioResult = onAudioResult,
        _onMotionResult = onMotionResult;

  final MotionAnalyzerV2 _motionAnalyzer;
  final CryAudioAnalyzerV2 _audioAnalyzer;
  final AlertEngine _alertEngine;
  final MediaAnalysisMetrics _metrics;
  final FrameRateGate _motionFrameGate;
  final void Function(String message)? _onLog;
  final void Function(AudioAnalysisResult result)? _onAudioResult;
  final void Function(MotionAnalysisResult result)? _onMotionResult;

  bool _isMotionAnalysisBusy = false;
  bool _disposed = false;
  int _lastMotionErrorLog = 0;
  int _lastAudioErrorLog = 0;

  Stream<AlertEvent> get alerts => _alertEngine.alerts;

  void onCameraFrame(LumaFrame frame) {
    if (_disposed) return;
    _metrics.recordVideoFrameReceived();
    if (!_motionFrameGate.shouldRun(frame.timestampMs)) {
      _metrics.recordMotionSkippedByFpsGate();
      return;
    }
    if (_isMotionAnalysisBusy) {
      _metrics.recordMotionDroppedBecauseBusy();
      return;
    }
    _isMotionAnalysisBusy = true;
    try {
      final result = _motionAnalyzer.analyze(frame);
      _metrics.recordMotion(result);
      _onMotionResult?.call(result);
      _alertEngine.onMotionResult(result);
    } catch (error) {
      _metrics.recordMotionError();
      _throttledLog('Motion analysis failed: $error', isAudio: false);
    } finally {
      _isMotionAnalysisBusy = false;
    }
  }

  void onAudioChunk(AudioChunk chunk) {
    if (_disposed) return;
    _metrics.recordAudioChunkReceived();
    try {
      final results = _audioAnalyzer.addChunk(chunk);
      for (final result in results) {
        _metrics.recordAudio(result);
        _onAudioResult?.call(result);
        _alertEngine.onAudioResult(result);
      }
    } catch (error) {
      _metrics.recordAudioError();
      _throttledLog('Audio analysis failed: $error', isAudio: true);
    }
  }

  Map<String, Object?> diagnostics() => {
        'analysis': _metrics.toJson(),
        'motionAnalyzer': _motionAnalyzer.diagnostics(),
        'audioAnalyzer': _audioAnalyzer.diagnostics(),
        'alertEngine': _alertEngine.diagnostics(),
      };

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _motionAnalyzer.reset();
    _audioAnalyzer.reset();
    await _alertEngine.dispose();
  }

  void _throttledLog(String message, {required bool isAudio}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = isAudio ? _lastAudioErrorLog : _lastMotionErrorLog;
    if (now - last < 5000) return;
    if (isAudio) {
      _lastAudioErrorLog = now;
    } else {
      _lastMotionErrorLog = now;
    }
    _onLog?.call(message);
  }
}
