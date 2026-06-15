import 'normalized_rect.dart';

/// Immutable configuration for [MotionAnalyzerV2].
class MotionAnalysisConfig {
  const MotionAnalysisConfig({
    this.downsampleWidth = 80,
    this.downsampleHeight = 60,
    this.analysisFps = 3,
    this.stableBackgroundAlpha = 0.02,
    this.motionBackgroundAlpha = 0.002,
    this.initializationAlpha = 0.20,
    this.minPixelDiff = 12.0,
    this.noiseMultiplier = 2.5,
    this.motionOnThreshold = 0.35,
    this.motionOffThreshold = 0.20,
    this.minMotionDurationMs = 1200,
    this.minActiveAreaRatio = 0.015,
    this.globalLightChangeRatio = 0.70,
    this.smoothingAlpha = 0.25,
    this.roi,
  });

  final int downsampleWidth;
  final int downsampleHeight;
  final int analysisFps;
  final double stableBackgroundAlpha;
  final double motionBackgroundAlpha;
  final double initializationAlpha;
  final double minPixelDiff;
  final double noiseMultiplier;
  final double motionOnThreshold;
  final double motionOffThreshold;
  final int minMotionDurationMs;
  final double minActiveAreaRatio;
  final double globalLightChangeRatio;
  final double smoothingAlpha;
  final NormalizedRect? roi;

  MotionAnalysisConfig copyWith({
    int? downsampleWidth,
    int? downsampleHeight,
    int? analysisFps,
    double? stableBackgroundAlpha,
    double? motionBackgroundAlpha,
    double? initializationAlpha,
    double? minPixelDiff,
    double? noiseMultiplier,
    double? motionOnThreshold,
    double? motionOffThreshold,
    int? minMotionDurationMs,
    double? minActiveAreaRatio,
    double? globalLightChangeRatio,
    double? smoothingAlpha,
    NormalizedRect? roi,
    bool clearRoi = false,
  }) =>
      MotionAnalysisConfig(
        downsampleWidth: downsampleWidth ?? this.downsampleWidth,
        downsampleHeight: downsampleHeight ?? this.downsampleHeight,
        analysisFps: analysisFps ?? this.analysisFps,
        stableBackgroundAlpha:
            stableBackgroundAlpha ?? this.stableBackgroundAlpha,
        motionBackgroundAlpha:
            motionBackgroundAlpha ?? this.motionBackgroundAlpha,
        initializationAlpha: initializationAlpha ?? this.initializationAlpha,
        minPixelDiff: minPixelDiff ?? this.minPixelDiff,
        noiseMultiplier: noiseMultiplier ?? this.noiseMultiplier,
        motionOnThreshold: motionOnThreshold ?? this.motionOnThreshold,
        motionOffThreshold: motionOffThreshold ?? this.motionOffThreshold,
        minMotionDurationMs: minMotionDurationMs ?? this.minMotionDurationMs,
        minActiveAreaRatio: minActiveAreaRatio ?? this.minActiveAreaRatio,
        globalLightChangeRatio:
            globalLightChangeRatio ?? this.globalLightChangeRatio,
        smoothingAlpha: smoothingAlpha ?? this.smoothingAlpha,
        roi: clearRoi ? null : roi ?? this.roi,
      );

  Map<String, Object?> toJson() => {
        'downsampleWidth': downsampleWidth,
        'downsampleHeight': downsampleHeight,
        'analysisFps': analysisFps,
        'stableBackgroundAlpha': stableBackgroundAlpha,
        'motionBackgroundAlpha': motionBackgroundAlpha,
        'initializationAlpha': initializationAlpha,
        'minPixelDiff': minPixelDiff,
        'noiseMultiplier': noiseMultiplier,
        'motionOnThreshold': motionOnThreshold,
        'motionOffThreshold': motionOffThreshold,
        'minMotionDurationMs': minMotionDurationMs,
        'minActiveAreaRatio': minActiveAreaRatio,
        'globalLightChangeRatio': globalLightChangeRatio,
        'smoothingAlpha': smoothingAlpha,
        'roi': roi?.toJson(),
      };
}
