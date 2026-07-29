import 'package:shared_preferences/shared_preferences.dart';

class ConfigurationService {
  ConfigurationService(this._prefs);

  static const _generalPrefix = 'config.';
  static const minMotionThreshold = 0.10;
  static const maxMotionThreshold = 0.60;
  static const minCryScoreThreshold = 0.45;
  static const maxCryScoreThreshold = 0.95;
  static const minDetectionDurationMs = 1000;
  static const minCryEvidenceDurationMs = 1500;
  static const maxDetectionDurationMs = 6000;
  static const minNotificationCooldownMs = 10000;
  static const maxNotificationCooldownMs = 180000;

  final SharedPreferences _prefs;
  SharedPreferences get preferences => _prefs;

  static Future<ConfigurationService> load() async =>
      ConfigurationService(await SharedPreferences.getInstance());

  double get motionThreshold => _boundedDouble(
        _prefs.getDouble('${_generalPrefix}motion_threshold'),
        fallback: 0.22,
        min: minMotionThreshold,
        max: maxMotionThreshold,
      );
  int get motionWindowMs =>
      _prefs.getInt('${_generalPrefix}motion_window_ms') ?? 3000;
  int get motionMinDurationMs =>
      (_prefs.getInt('${_generalPrefix}motion_min_duration_ms') ?? 2000)
          .clamp(minDetectionDurationMs, maxDetectionDurationMs)
          .toInt();
  double get cryScoreThreshold => _boundedDouble(
        _prefs.getDouble('${_generalPrefix}cry_score_threshold'),
        fallback: 0.65,
        min: minCryScoreThreshold,
        max: maxCryScoreThreshold,
      );
  int get cryMinDurationMs =>
      (_prefs.getInt('${_generalPrefix}cry_min_duration_ms') ?? 1500)
          .clamp(minCryEvidenceDurationMs, maxDetectionDurationMs)
          .toInt();
  int get cryWindowMs =>
      _prefs.getInt('${_generalPrefix}cry_window_ms') ?? 5000;
  int get notifyCooldownMs =>
      (_prefs.getInt('${_generalPrefix}notify_cooldown_ms') ?? 60000)
          .clamp(minNotificationCooldownMs, maxNotificationCooldownMs)
          .toInt();
  bool get webRtcPilotEnabled =>
      _prefs.getBool('${_generalPrefix}webrtc_pilot_enabled') ??
      const bool.fromEnvironment('MIUCAM_WEBRTC_PILOT');

  Future<void> setMotionThreshold(double threshold) => _prefs.setDouble(
        '${_generalPrefix}motion_threshold',
        _boundedDouble(
          threshold,
          fallback: 0.22,
          min: minMotionThreshold,
          max: maxMotionThreshold,
        ),
      );
  Future<void> setMotionWindowMs(int windowMs) =>
      _prefs.setInt('${_generalPrefix}motion_window_ms', windowMs);
  Future<void> setMotionMinDurationMs(int durationMs) => _prefs.setInt(
        '${_generalPrefix}motion_min_duration_ms',
        durationMs
            .clamp(minDetectionDurationMs, maxDetectionDurationMs)
            .toInt(),
      );
  Future<void> setCryScoreThreshold(double threshold) => _prefs.setDouble(
        '${_generalPrefix}cry_score_threshold',
        _boundedDouble(
          threshold,
          fallback: 0.65,
          min: minCryScoreThreshold,
          max: maxCryScoreThreshold,
        ),
      );
  Future<void> setCryMinDurationMs(int durationMs) => _prefs.setInt(
        '${_generalPrefix}cry_min_duration_ms',
        durationMs
            .clamp(minCryEvidenceDurationMs, maxDetectionDurationMs)
            .toInt(),
      );
  Future<void> setCryWindowMs(int windowMs) =>
      _prefs.setInt('${_generalPrefix}cry_window_ms', windowMs);
  Future<void> setNotifyCooldownMs(int cooldownMs) => _prefs.setInt(
        '${_generalPrefix}notify_cooldown_ms',
        cooldownMs
            .clamp(
              minNotificationCooldownMs,
              maxNotificationCooldownMs,
            )
            .toInt(),
      );
  Future<void> setWebRtcPilotEnabled(bool enabled) =>
      _prefs.setBool('${_generalPrefix}webrtc_pilot_enabled', enabled);

  Future<void> resetToDefaults() async {
    final keys = _prefs
        .getKeys()
        .where((key) => key.startsWith(_generalPrefix))
        .toList();
    for (final key in keys) {
      await _prefs.remove(key);
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
