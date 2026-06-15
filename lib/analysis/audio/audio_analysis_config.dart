/// Immutable configuration for [CryAudioAnalyzerV2].
class AudioAnalysisConfig {
  final int sampleRate;
  final int windowMs;
  final int hopMs;
  final int calibrationMs;
  final double cryOnThreshold;
  final double cryOffThreshold;
  final int minCryDurationMs;
  final double ambientUpdateAlpha;
  final double smoothingAlpha;
  final double energyWeight;
  final double bandWeight;
  final double zcrWeight;
  final double centroidWeight;
  final double fluxWeight;
  final double minDbfsForCryCandidate;
  final double loudSoundDbfs;

  const AudioAnalysisConfig({
    this.sampleRate = 16000,
    this.windowMs = 1000,
    this.hopMs = 250,
    this.calibrationMs = 30000,
    this.cryOnThreshold = 0.65,
    this.cryOffThreshold = 0.45,
    this.minCryDurationMs = 1500,
    this.ambientUpdateAlpha = 0.005,
    this.smoothingAlpha = 0.25,
    this.energyWeight = 0.45,
    this.bandWeight = 0.25,
    this.zcrWeight = 0.10,
    this.centroidWeight = 0.10,
    this.fluxWeight = 0.10,
    this.minDbfsForCryCandidate = -55.0,
    this.loudSoundDbfs = -18.0,
  });

  AudioAnalysisConfig copyWith({
    int? sampleRate,
    int? windowMs,
    int? hopMs,
    int? calibrationMs,
    double? cryOnThreshold,
    double? cryOffThreshold,
    int? minCryDurationMs,
    double? ambientUpdateAlpha,
    double? smoothingAlpha,
    double? energyWeight,
    double? bandWeight,
    double? zcrWeight,
    double? centroidWeight,
    double? fluxWeight,
    double? minDbfsForCryCandidate,
    double? loudSoundDbfs,
  }) => AudioAnalysisConfig(
        sampleRate: sampleRate ?? this.sampleRate,
        windowMs: windowMs ?? this.windowMs,
        hopMs: hopMs ?? this.hopMs,
        calibrationMs: calibrationMs ?? this.calibrationMs,
        cryOnThreshold: cryOnThreshold ?? this.cryOnThreshold,
        cryOffThreshold: cryOffThreshold ?? this.cryOffThreshold,
        minCryDurationMs: minCryDurationMs ?? this.minCryDurationMs,
        ambientUpdateAlpha: ambientUpdateAlpha ?? this.ambientUpdateAlpha,
        smoothingAlpha: smoothingAlpha ?? this.smoothingAlpha,
        energyWeight: energyWeight ?? this.energyWeight,
        bandWeight: bandWeight ?? this.bandWeight,
        zcrWeight: zcrWeight ?? this.zcrWeight,
        centroidWeight: centroidWeight ?? this.centroidWeight,
        fluxWeight: fluxWeight ?? this.fluxWeight,
        minDbfsForCryCandidate:
            minDbfsForCryCandidate ?? this.minDbfsForCryCandidate,
        loudSoundDbfs: loudSoundDbfs ?? this.loudSoundDbfs,
      );

  Map<String, Object?> toJson() => {
        'sampleRate': sampleRate,
        'windowMs': windowMs,
        'hopMs': hopMs,
        'calibrationMs': calibrationMs,
        'cryOnThreshold': cryOnThreshold,
        'cryOffThreshold': cryOffThreshold,
        'minCryDurationMs': minCryDurationMs,
        'ambientUpdateAlpha': ambientUpdateAlpha,
        'smoothingAlpha': smoothingAlpha,
        'energyWeight': energyWeight,
        'bandWeight': bandWeight,
        'zcrWeight': zcrWeight,
        'centroidWeight': centroidWeight,
        'fluxWeight': fluxWeight,
        'minDbfsForCryCandidate': minDbfsForCryCandidate,
        'loudSoundDbfs': loudSoundDbfs,
      };
}
