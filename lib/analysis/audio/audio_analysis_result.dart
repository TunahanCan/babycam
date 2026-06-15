import 'audio_calibration_state.dart';

/// Feature and decision output for one analyzed audio window.
class AudioAnalysisResult {
  final int timestampMs;
  final double cryScore;
  final double rawCryScore;
  final bool isCryLikely;
  final bool isCalibrated;
  final AudioCalibrationState calibrationState;
  final double rms;
  final double dbfs;
  final double peak;
  final double zeroCrossingRate;
  final double ambientDbfs;
  final double ambientDeltaDb;
  final double cryBandRatio;
  final double lowBandRatio;
  final double highBandRatio;
  final double spectralCentroid;
  final double spectralEntropy;
  final double spectralFlux;
  final bool invalidChunk;
  final bool isLoudSound;
  final int processingTimeMicros;

  const AudioAnalysisResult({
    required this.timestampMs,
    required this.cryScore,
    required this.rawCryScore,
    required this.isCryLikely,
    required this.isCalibrated,
    required this.calibrationState,
    required this.rms,
    required this.dbfs,
    required this.peak,
    required this.zeroCrossingRate,
    required this.ambientDbfs,
    required this.ambientDeltaDb,
    required this.cryBandRatio,
    required this.lowBandRatio,
    required this.highBandRatio,
    required this.spectralCentroid,
    required this.spectralEntropy,
    required this.spectralFlux,
    required this.invalidChunk,
    required this.processingTimeMicros,
    this.isLoudSound = false,
  });

  Map<String, Object?> toJson() => {
        'timestampMs': timestampMs,
        'cryScore': cryScore,
        'rawCryScore': rawCryScore,
        'isCryLikely': isCryLikely,
        'isCalibrated': isCalibrated,
        'calibrationState': calibrationState.name,
        'rms': rms,
        'dbfs': dbfs,
        'peak': peak,
        'zeroCrossingRate': zeroCrossingRate,
        'ambientDbfs': ambientDbfs,
        'ambientDeltaDb': ambientDeltaDb,
        'cryBandRatio': cryBandRatio,
        'lowBandRatio': lowBandRatio,
        'highBandRatio': highBandRatio,
        'spectralCentroid': spectralCentroid,
        'spectralEntropy': spectralEntropy,
        'spectralFlux': spectralFlux,
        'invalidChunk': invalidChunk,
        'isLoudSound': isLoudSound,
        'processingTimeMicros': processingTimeMicros,
      };
}
