import '../../analysis/alert/alert_event.dart';
import '../../analysis/audio/audio_analysis_result.dart';
import '../../analysis/video/motion_analysis_result.dart';

class MediaAnalysisMetrics {
  MediaAnalysisMetrics({required this.motionTargetFps});

  final int motionTargetFps;

  int videoFramesReceived = 0;
  int videoFramesAnalyzed = 0;
  int videoFramesSkippedByFpsGate = 0;
  int videoFramesDroppedBecauseBusy = 0;
  int motionErrors = 0;
  double motionProcessingAvgMicros = 0;
  double? lastMotionScore;
  int? lastMotionAt;
  bool? lastMotionIsMotion;
  bool? lastGlobalLightChange;

  int audioChunksReceived = 0;
  int audioWindowsAnalyzed = 0;
  int audioChunksDropped = 0;
  int audioErrors = 0;
  double audioProcessingAvgMicros = 0;
  double? lastCryScore;
  double? lastAudioDbfs;
  double? lastAmbientDbfs;
  int? lastAudioAt;
  bool? lastCryLikely;
  String? audioCalibrationState;

  int alertsProduced = 0;
  String? lastAlertType;
  int? lastAlertAt;

  void recordVideoFrameReceived() => videoFramesReceived++;
  void recordMotionSkippedByFpsGate() => videoFramesSkippedByFpsGate++;
  void recordMotionDroppedBecauseBusy() => videoFramesDroppedBecauseBusy++;
  void recordMotionError() => motionErrors++;

  void recordMotion(MotionAnalysisResult result) {
    if (!result.skippedByFrameRateGate && !result.invalidFrame) {
      videoFramesAnalyzed++;
    }
    motionProcessingAvgMicros =
        _ema(motionProcessingAvgMicros, result.processingTimeMicros.toDouble());
    lastMotionScore = result.score;
    lastMotionAt = result.timestampMs;
    lastMotionIsMotion = result.isMotion;
    lastGlobalLightChange = result.isGlobalLightChange;
  }

  void recordAudioChunkReceived() => audioChunksReceived++;
  void recordAudioChunkDropped() => audioChunksDropped++;
  void recordAudioError() => audioErrors++;

  void recordAudio(AudioAnalysisResult result) {
    if (!result.invalidChunk) {
      audioWindowsAnalyzed++;
    }
    audioProcessingAvgMicros =
        _ema(audioProcessingAvgMicros, result.processingTimeMicros.toDouble());
    lastCryScore = result.cryScore;
    lastAudioDbfs = result.dbfs;
    lastAmbientDbfs = result.ambientDbfs;
    lastAudioAt = result.timestampMs;
    lastCryLikely = result.isCryLikely;
    audioCalibrationState = result.calibrationState.name;
  }

  void recordAlert(AlertEvent event) {
    alertsProduced++;
    lastAlertType = event.type.name;
    lastAlertAt = event.timestampMs;
  }

  Map<String, Object?> toJson() => {
        'motion': {
          'targetFps': motionTargetFps,
          'lastScore': lastMotionScore,
          'framesReceived': videoFramesReceived,
          'framesAnalyzed': videoFramesAnalyzed,
          'framesSkippedByFpsGate': videoFramesSkippedByFpsGate,
          'framesDroppedBecauseBusy': videoFramesDroppedBecauseBusy,
          'errors': motionErrors,
          'processingAvgMs': motionProcessingAvgMicros / 1000.0,
          'isMotion': lastMotionIsMotion,
          'isGlobalLightChange': lastGlobalLightChange,
          'lastMotionAt': lastMotionAt,
        },
        'audio': {
          'chunksReceived': audioChunksReceived,
          'windowsAnalyzed': audioWindowsAnalyzed,
          'chunksDropped': audioChunksDropped,
          'errors': audioErrors,
          'lastCryScore': lastCryScore,
          'lastDbfs': lastAudioDbfs,
          'ambientDbfs': lastAmbientDbfs,
          'processingAvgMs': audioProcessingAvgMicros / 1000.0,
          'isCryLikely': lastCryLikely,
          'calibrationState': audioCalibrationState,
          'lastAudioAt': lastAudioAt,
        },
        'alerts': {
          'alertsProduced': alertsProduced,
          'lastAlertType': lastAlertType,
          'lastAlertAt': lastAlertAt,
        },
      };

  void reset() {
    videoFramesReceived = 0;
    videoFramesAnalyzed = 0;
    videoFramesSkippedByFpsGate = 0;
    videoFramesDroppedBecauseBusy = 0;
    motionErrors = 0;
    motionProcessingAvgMicros = 0;
    lastMotionScore = null;
    lastMotionAt = null;
    lastMotionIsMotion = null;
    lastGlobalLightChange = null;
    audioChunksReceived = 0;
    audioWindowsAnalyzed = 0;
    audioChunksDropped = 0;
    audioErrors = 0;
    audioProcessingAvgMicros = 0;
    lastCryScore = null;
    lastAudioDbfs = null;
    lastAmbientDbfs = null;
    lastAudioAt = null;
    lastCryLikely = null;
    audioCalibrationState = null;
    alertsProduced = 0;
    lastAlertType = null;
    lastAlertAt = null;
  }

  double _ema(double avg, double value) =>
      avg == 0 ? value : avg * 0.9 + value * 0.1;
}
