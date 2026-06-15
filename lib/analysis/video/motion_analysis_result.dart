/// Result metrics and decision flags produced by MotionAnalyzerV2.
class MotionAnalysisResult {
  const MotionAnalysisResult({
    required this.timestampMs,
    required this.score,
    required this.rawScore,
    required this.activeAreaRatio,
    required this.meanDiff,
    required this.currentMeanLuma,
    required this.backgroundMeanLuma,
    required this.globalLumaShift,
    required this.isMotion,
    required this.isGlobalLightChange,
    required this.skippedByFrameRateGate,
    required this.invalidFrame,
    required this.processingTimeMicros,
  });

  final int timestampMs;
  final double score;
  final double rawScore;
  final double activeAreaRatio;
  final double meanDiff;
  final double currentMeanLuma;
  final double backgroundMeanLuma;
  final double globalLumaShift;
  final bool isMotion;
  final bool isGlobalLightChange;
  final bool skippedByFrameRateGate;
  final bool invalidFrame;
  final int processingTimeMicros;

  Map<String, Object?> toJson() => {
        'timestampMs': timestampMs,
        'score': score,
        'rawScore': rawScore,
        'activeAreaRatio': activeAreaRatio,
        'meanDiff': meanDiff,
        'currentMeanLuma': currentMeanLuma,
        'backgroundMeanLuma': backgroundMeanLuma,
        'globalLumaShift': globalLumaShift,
        'isMotion': isMotion,
        'isGlobalLightChange': isGlobalLightChange,
        'skippedByFrameRateGate': skippedByFrameRateGate,
        'invalidFrame': invalidFrame,
        'processingTimeMicros': processingTimeMicros,
      };
}
