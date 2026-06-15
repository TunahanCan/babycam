/// Immutable configuration for alert decisions and per-type cooldowns.
class AlertConfig {
  const AlertConfig({
    this.cryCooldownMs = 60000,
    this.motionCooldownMs = 30000,
    this.loudSoundCooldownMs = 30000,
    this.globalLightChangeCooldownMs = 15000,
    this.cryAlertThreshold = 0.65,
    this.motionAlertThreshold = 0.35,
    this.loudSoundDbfs = -18.0,
    this.emitGlobalLightChangeInfo = false,
    this.emitLoudSoundAlerts = false,
  });

  final int cryCooldownMs;
  final int motionCooldownMs;
  final int loudSoundCooldownMs;
  final int globalLightChangeCooldownMs;
  final double cryAlertThreshold;
  final double motionAlertThreshold;
  final double loudSoundDbfs;
  final bool emitGlobalLightChangeInfo;
  final bool emitLoudSoundAlerts;

  /// Returns a copy with selected fields replaced.
  AlertConfig copyWith({
    int? cryCooldownMs,
    int? motionCooldownMs,
    int? loudSoundCooldownMs,
    int? globalLightChangeCooldownMs,
    double? cryAlertThreshold,
    double? motionAlertThreshold,
    double? loudSoundDbfs,
    bool? emitGlobalLightChangeInfo,
    bool? emitLoudSoundAlerts,
  }) =>
      AlertConfig(
        cryCooldownMs: cryCooldownMs ?? this.cryCooldownMs,
        motionCooldownMs: motionCooldownMs ?? this.motionCooldownMs,
        loudSoundCooldownMs: loudSoundCooldownMs ?? this.loudSoundCooldownMs,
        globalLightChangeCooldownMs:
            globalLightChangeCooldownMs ?? this.globalLightChangeCooldownMs,
        cryAlertThreshold: cryAlertThreshold ?? this.cryAlertThreshold,
        motionAlertThreshold: motionAlertThreshold ?? this.motionAlertThreshold,
        loudSoundDbfs: loudSoundDbfs ?? this.loudSoundDbfs,
        emitGlobalLightChangeInfo:
            emitGlobalLightChangeInfo ?? this.emitGlobalLightChangeInfo,
        emitLoudSoundAlerts: emitLoudSoundAlerts ?? this.emitLoudSoundAlerts,
      );

  /// Converts this config into a JSON-friendly map.
  Map<String, Object?> toJson() => {
        'cryCooldownMs': cryCooldownMs,
        'motionCooldownMs': motionCooldownMs,
        'loudSoundCooldownMs': loudSoundCooldownMs,
        'globalLightChangeCooldownMs': globalLightChangeCooldownMs,
        'cryAlertThreshold': cryAlertThreshold,
        'motionAlertThreshold': motionAlertThreshold,
        'loudSoundDbfs': loudSoundDbfs,
        'emitGlobalLightChangeInfo': emitGlobalLightChangeInfo,
        'emitLoudSoundAlerts': emitLoudSoundAlerts,
      };
}
