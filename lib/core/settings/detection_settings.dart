/// User-facing detection policy shared by persistence and settings screens.
///
/// Durations use the same millisecond units as stored preferences. These
/// product presets are separate from the low-level analyzers' configurations.
class DetectionSettings {
  const DetectionSettings({
    required this.motionThreshold,
    required this.cryScoreThreshold,
    required this.notifyCooldownMs,
    required this.motionMinDurationMs,
    required this.cryMinDurationMs,
  });

  static const defaults = DetectionSettings(
    motionThreshold: .22,
    cryScoreThreshold: .65,
    notifyCooldownMs: 60000,
    motionMinDurationMs: 2000,
    cryMinDurationMs: 1500,
  );

  static const minMotionThreshold = .10;
  static const maxMotionThreshold = .60;
  static const minCryScoreThreshold = .45;
  static const maxCryScoreThreshold = .95;
  static const minDetectionDurationMs = 1000;
  static const minCryEvidenceDurationMs = 1500;
  static const maxDetectionDurationMs = 6000;
  static const minNotificationCooldownMs = 10000;
  static const maxNotificationCooldownMs = 180000;

  final double motionThreshold;
  final double cryScoreThreshold;
  final int notifyCooldownMs;
  final int motionMinDurationMs;
  final int cryMinDurationMs;
}

/// Product choices contain policy only; labels and icons belong to the UI.
enum DetectionPreset {
  sensitive(DetectionSettings(
    motionThreshold: .15,
    cryScoreThreshold: .50,
    notifyCooldownMs: 45000,
    motionMinDurationMs: 1000,
    cryMinDurationMs: 1500,
  )),
  balanced(DetectionSettings.defaults),
  fewerAlerts(DetectionSettings(
    motionThreshold: .35,
    cryScoreThreshold: .78,
    notifyCooldownMs: 90000,
    motionMinDurationMs: 3500,
    cryMinDurationMs: 2500,
  ));

  const DetectionPreset(this.settings);

  final DetectionSettings settings;
}
