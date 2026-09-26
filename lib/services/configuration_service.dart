import 'package:shared_preferences/shared_preferences.dart';

import '../core/async/serialized_async_executor.dart';
import '../core/settings/detection_settings.dart';

class ConfigurationService {
  ConfigurationService(this._prefs);

  static const _generalPrefix = 'config.';
  // Retain the existing API while the policy is owned by the shared model.
  static const minMotionThreshold = DetectionSettings.minMotionThreshold;
  static const maxMotionThreshold = DetectionSettings.maxMotionThreshold;
  static const minCryScoreThreshold = DetectionSettings.minCryScoreThreshold;
  static const maxCryScoreThreshold = DetectionSettings.maxCryScoreThreshold;
  static const minDetectionDurationMs =
      DetectionSettings.minDetectionDurationMs;
  static const minCryEvidenceDurationMs =
      DetectionSettings.minCryEvidenceDurationMs;
  static const maxDetectionDurationMs =
      DetectionSettings.maxDetectionDurationMs;
  static const minNotificationCooldownMs =
      DetectionSettings.minNotificationCooldownMs;
  static const maxNotificationCooldownMs =
      DetectionSettings.maxNotificationCooldownMs;

  final SharedPreferences _prefs;
  final _writes = SerializedAsyncExecutor();
  SharedPreferences get preferences => _prefs;

  static Future<ConfigurationService> load() async =>
      ConfigurationService(await SharedPreferences.getInstance());

  DetectionSettings get detectionSettings => DetectionSettings(
        motionThreshold: motionThreshold,
        cryScoreThreshold: cryScoreThreshold,
        notifyCooldownMs: notifyCooldownMs,
        motionMinDurationMs: motionMinDurationMs,
        cryMinDurationMs: cryMinDurationMs,
      );

  Future<void> setDetectionSettings(DetectionSettings settings) async {
    // Preserve ordered writes and complete all accepted writes even if one
    // fails. Callers reload durable settings after a partial storage failure.
    await Future.wait<void>([
      setMotionThreshold(settings.motionThreshold),
      setCryScoreThreshold(settings.cryScoreThreshold),
      setNotifyCooldownMs(settings.notifyCooldownMs),
      setMotionMinDurationMs(settings.motionMinDurationMs),
      setCryMinDurationMs(settings.cryMinDurationMs),
    ]);
  }

  double get motionThreshold => _boundedDouble(
        _prefs.getDouble('${_generalPrefix}motion_threshold'),
        fallback: DetectionSettings.defaults.motionThreshold,
        min: minMotionThreshold,
        max: maxMotionThreshold,
      );
  int get motionWindowMs =>
      _prefs.getInt('${_generalPrefix}motion_window_ms') ?? 3000;
  int get motionMinDurationMs =>
      (_prefs.getInt('${_generalPrefix}motion_min_duration_ms') ??
              DetectionSettings.defaults.motionMinDurationMs)
          .clamp(minDetectionDurationMs, maxDetectionDurationMs)
          .toInt();
  double get cryScoreThreshold => _boundedDouble(
        _prefs.getDouble('${_generalPrefix}cry_score_threshold'),
        fallback: DetectionSettings.defaults.cryScoreThreshold,
        min: minCryScoreThreshold,
        max: maxCryScoreThreshold,
      );
  int get cryMinDurationMs =>
      (_prefs.getInt('${_generalPrefix}cry_min_duration_ms') ??
              DetectionSettings.defaults.cryMinDurationMs)
          .clamp(minCryEvidenceDurationMs, maxDetectionDurationMs)
          .toInt();
  int get cryWindowMs =>
      _prefs.getInt('${_generalPrefix}cry_window_ms') ?? 5000;
  int get notifyCooldownMs =>
      (_prefs.getInt('${_generalPrefix}notify_cooldown_ms') ??
              DetectionSettings.defaults.notifyCooldownMs)
          .clamp(minNotificationCooldownMs, maxNotificationCooldownMs)
          .toInt();
  bool get webRtcPilotEnabled =>
      _prefs.getBool('${_generalPrefix}webrtc_pilot_enabled') ??
      const bool.fromEnvironment('MIUCAM_WEBRTC_PILOT');

  Future<void> setMotionThreshold(double threshold) =>
      _persist(() => _prefs.setDouble(
            '${_generalPrefix}motion_threshold',
            _boundedDouble(
              threshold,
              fallback: DetectionSettings.defaults.motionThreshold,
              min: minMotionThreshold,
              max: maxMotionThreshold,
            ),
          ));
  Future<void> setMotionWindowMs(int windowMs) => _persist(
      () => _prefs.setInt('${_generalPrefix}motion_window_ms', windowMs));
  Future<void> setMotionMinDurationMs(int durationMs) =>
      _persist(() => _prefs.setInt(
            '${_generalPrefix}motion_min_duration_ms',
            durationMs
                .clamp(minDetectionDurationMs, maxDetectionDurationMs)
                .toInt(),
          ));
  Future<void> setCryScoreThreshold(double threshold) =>
      _persist(() => _prefs.setDouble(
            '${_generalPrefix}cry_score_threshold',
            _boundedDouble(
              threshold,
              fallback: DetectionSettings.defaults.cryScoreThreshold,
              min: minCryScoreThreshold,
              max: maxCryScoreThreshold,
            ),
          ));
  Future<void> setCryMinDurationMs(int durationMs) =>
      _persist(() => _prefs.setInt(
            '${_generalPrefix}cry_min_duration_ms',
            durationMs
                .clamp(minCryEvidenceDurationMs, maxDetectionDurationMs)
                .toInt(),
          ));
  Future<void> setCryWindowMs(int windowMs) =>
      _persist(() => _prefs.setInt('${_generalPrefix}cry_window_ms', windowMs));
  Future<void> setNotifyCooldownMs(int cooldownMs) =>
      _persist(() => _prefs.setInt(
            '${_generalPrefix}notify_cooldown_ms',
            cooldownMs
                .clamp(
                  minNotificationCooldownMs,
                  maxNotificationCooldownMs,
                )
                .toInt(),
          ));
  Future<void> setWebRtcPilotEnabled(bool enabled) => _persist(
      () => _prefs.setBool('${_generalPrefix}webrtc_pilot_enabled', enabled));

  Future<void> resetToDefaults() => _writes.run(() async {
        // Snapshot after preceding writes and keep the whole reset in order.
        final keys = _prefs
            .getKeys()
            .where((key) => key.startsWith(_generalPrefix))
            .toList();
        for (final key in keys) {
          await _requireSaved(() => _prefs.remove(key));
        }
      });

  Future<void> _persist(Future<bool> Function() write) =>
      _writes.run(() => _requireSaved(write));

  Future<void> _requireSaved(Future<bool> Function() write) async {
    try {
      if (!await write()) {
        throw StateError('Could not persist server settings.');
      }
    } catch (_) {
      // SharedPreferences changes its cache before the platform confirms
      // the write. Restore durable values before the UI reads them again.
      try {
        await _prefs.reload();
      } catch (_) {
        // Preserve the original storage failure for the caller.
      }
      rethrow;
    }
  }

  double _boundedDouble(
    double? value, {
    required double fallback,
    required double min,
    required double max,
  }) {
    final safeValue = value != null && value.isFinite ? value : fallback;
    return safeValue.clamp(min, max).toDouble();
  }
}
