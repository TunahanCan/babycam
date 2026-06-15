import 'dart:async';

import '../audio/audio_analysis_result.dart';
import '../video/motion_analysis_result.dart';
import 'alert_config.dart';
import 'alert_event.dart';
import 'alert_severity.dart';
import 'alert_type.dart';
import 'cooldown_policy.dart';

/// Converts analyzer results into structured, transport-agnostic alerts.
class AlertEngine {
  AlertEngine({this.config = const AlertConfig()})
      : _cooldownPolicy = CooldownPolicy(
          cooldownMsByType: {
            AlertType.cryDetected: config.cryCooldownMs,
            AlertType.motionDetected: config.motionCooldownMs,
            AlertType.loudSound: config.loudSoundCooldownMs,
            AlertType.globalLightChange: config.globalLightChangeCooldownMs,
          },
        );

  final AlertConfig config;
  final CooldownPolicy _cooldownPolicy;
  final StreamController<AlertEvent> _controller =
      StreamController<AlertEvent>.broadcast();
  final List<AlertEvent> _pending = [];

  int _sequence = 0;
  int _alertsProduced = 0;
  AlertType? _lastAlertType;
  int? _lastAlertAt;
  bool _disposed = false;

  /// Broadcast stream of emitted alerts.
  Stream<AlertEvent> get alerts => _controller.stream;

  /// Handles one motion analysis result and returns the emitted alert, if any.
  AlertEvent? onMotionResult(MotionAnalysisResult result) {
    if (result.isGlobalLightChange) {
      if (!config.emitGlobalLightChangeInfo) {
        return null;
      }
      return _tryEmit(
        type: AlertType.globalLightChange,
        severity: AlertSeverity.info,
        message: 'Işık değişimi algılandı',
        score: result.score,
        timestampMs: result.timestampMs,
        metadata: _motionMetadata(result),
      );
    }

    if (!result.isMotion || result.score < config.motionAlertThreshold) {
      return null;
    }

    return _tryEmit(
      type: AlertType.motionDetected,
      severity: AlertSeverity.info,
      message: 'Hareket algılandı',
      score: result.score,
      timestampMs: result.timestampMs,
      metadata: _motionMetadata(result),
    );
  }

  /// Handles one audio analysis result and returns the emitted alert, if any.
  AlertEvent? onAudioResult(AudioAnalysisResult result) {
    if (result.isCryLikely && result.cryScore >= config.cryAlertThreshold) {
      return _tryEmit(
        type: AlertType.cryDetected,
        severity: AlertSeverity.warning,
        message: 'Ağlama algılandı',
        score: result.cryScore,
        timestampMs: result.timestampMs,
        metadata: _audioMetadata(result),
      );
    }

    final isLoudSound = result.isLoudSound || result.dbfs >= config.loudSoundDbfs;
    if (config.emitLoudSoundAlerts && isLoudSound) {
      return _tryEmit(
        type: AlertType.loudSound,
        severity: AlertSeverity.info,
        message: 'Yüksek ses algılandı',
        score: result.dbfs,
        timestampMs: result.timestampMs,
        metadata: _audioMetadata(result),
      );
    }

    return null;
  }

  /// Returns and clears alerts emitted since the previous drain.
  List<AlertEvent> drainPending() {
    final drained = List<AlertEvent>.unmodifiable(_pending);
    _pending.clear();
    return drained;
  }

  /// Resets cooldowns, counters, sequence, and pending events.
  void reset() {
    _cooldownPolicy.reset();
    _pending.clear();
    _sequence = 0;
    _alertsProduced = 0;
    _lastAlertType = null;
    _lastAlertAt = null;
  }

  /// Closes the alert stream. Future result handling becomes a safe no-op.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _controller.close();
  }

  /// Returns lightweight runtime diagnostics for tests and future integration.
  Map<String, Object?> diagnostics() {
    final nowMs = _lastAlertAt ?? DateTime.now().millisecondsSinceEpoch;
    return {
      'alertsProduced': _alertsProduced,
      'lastAlertType': _lastAlertType?.name,
      'lastAlertAt': _lastAlertAt,
      'cooldowns': {
        for (final type in AlertType.values)
          '${type.name}RemainingMs': _cooldownPolicy.remainingMs(type, nowMs),
      },
    };
  }

  AlertEvent? _tryEmit({
    required AlertType type,
    required AlertSeverity severity,
    required String message,
    required double score,
    required int timestampMs,
    required Map<String, Object?> metadata,
  }) {
    if (_disposed || !_cooldownPolicy.canEmit(type, timestampMs)) {
      return null;
    }

    final event = AlertEvent(
      id: '${type.name}-$timestampMs-${_sequence++}',
      type: type,
      severity: severity,
      message: message,
      score: score,
      timestampMs: timestampMs,
      metadata: metadata,
    );

    _cooldownPolicy.markEmitted(type, timestampMs);
    _alertsProduced++;
    _lastAlertType = type;
    _lastAlertAt = timestampMs;
    _pending.add(event);
    if (!_controller.isClosed) {
      _controller.add(event);
    }
    return event;
  }

  Map<String, Object?> _audioMetadata(AudioAnalysisResult result) => {
        'cryScore': result.cryScore,
        'rawCryScore': result.rawCryScore,
        'dbfs': result.dbfs,
        'ambientDbfs': result.ambientDbfs,
        'ambientDeltaDb': result.ambientDeltaDb,
        'cryBandRatio': result.cryBandRatio,
        'zeroCrossingRate': result.zeroCrossingRate,
        'spectralCentroid': result.spectralCentroid,
        'isCalibrated': result.isCalibrated,
        'isLoudSound': result.isLoudSound,
      };

  Map<String, Object?> _motionMetadata(MotionAnalysisResult result) => {
        'score': result.score,
        'rawScore': result.rawScore,
        'activeAreaRatio': result.activeAreaRatio,
        'meanDiff': result.meanDiff,
        'globalLumaShift': result.globalLumaShift,
        'currentMeanLuma': result.currentMeanLuma,
        'backgroundMeanLuma': result.backgroundMeanLuma,
      };
}
