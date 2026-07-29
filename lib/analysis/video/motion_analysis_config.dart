import 'normalized_rect.dart';

/// Immutable configuration for [MotionAnalyzerV2].
class MotionAnalysisConfig {
  const MotionAnalysisConfig({
    this.downsampleWidth = 64,
    this.downsampleHeight = 48,
    this.analysisFps = 3,
    this.stableBackgroundAlpha = 0.02,
    this.motionBackgroundAlpha = 0.002,
    this.initializationAlpha = 0.20,
    this.minPixelDiff = 12.0,
    this.noiseMultiplier = 2.5,
    this.minActiveNeighborCount = 2,
    this.motionOnThreshold = 0.35,
    this.motionOffThreshold = 0.20,
    this.minMotionDurationMs = 1200,
    this.minActiveAreaRatio = 0.015,
    this.globalLightChangeRatio = 0.70,
    this.smoothingAlpha = 0.25,
    this.initializationFrames = 5,
    this.maxFrameGapMs = 1000,
    this.minMotionFrames = 3,
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

  /// Rejects isolated pixels that are typical of sensor/compression noise.
  /// A real moving object normally produces a small connected region.
  final int minActiveNeighborCount;
  final double motionOnThreshold;
  final double motionOffThreshold;
  final int minMotionDurationMs;
  final double minActiveAreaRatio;
  final double globalLightChangeRatio;
  final double smoothingAlpha;

  /// Valid frames used only to settle exposure/focus and the background model
  /// after startup or a capture discontinuity.
  final int initializationFrames;

  /// A larger timestamp gap is missing evidence, not sustained movement.
  final int maxFrameGapMs;

  /// Prevents two widely spaced frames from satisfying a duration threshold.
  final int minMotionFrames;
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
    int? minActiveNeighborCount,
    double? motionOnThreshold,
    double? motionOffThreshold,
    int? minMotionDurationMs,
    double? minActiveAreaRatio,
    double? globalLightChangeRatio,
    double? smoothingAlpha,
    int? initializationFrames,
    int? maxFrameGapMs,
    int? minMotionFrames,
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
        minActiveNeighborCount:
            minActiveNeighborCount ?? this.minActiveNeighborCount,
        motionOnThreshold: motionOnThreshold ?? this.motionOnThreshold,
        motionOffThreshold: motionOffThreshold ?? this.motionOffThreshold,
        minMotionDurationMs: minMotionDurationMs ?? this.minMotionDurationMs,
        minActiveAreaRatio: minActiveAreaRatio ?? this.minActiveAreaRatio,
        globalLightChangeRatio:
            globalLightChangeRatio ?? this.globalLightChangeRatio,
        smoothingAlpha: smoothingAlpha ?? this.smoothingAlpha,
        initializationFrames: initializationFrames ?? this.initializationFrames,
        maxFrameGapMs: maxFrameGapMs ?? this.maxFrameGapMs,
        minMotionFrames: minMotionFrames ?? this.minMotionFrames,
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
        'minActiveNeighborCount': minActiveNeighborCount,
        'motionOnThreshold': motionOnThreshold,
        'motionOffThreshold': motionOffThreshold,
        'minMotionDurationMs': minMotionDurationMs,
        'minActiveAreaRatio': minActiveAreaRatio,
        'globalLightChangeRatio': globalLightChangeRatio,
        'smoothingAlpha': smoothingAlpha,
        'initializationFrames': initializationFrames,
        'maxFrameGapMs': maxFrameGapMs,
        'minMotionFrames': minMotionFrames,
        'roi': roi?.toJson(),
      };
}
