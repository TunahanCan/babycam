import 'dart:math';
import 'dart:typed_data';

import 'audio_analysis_config.dart';
import 'audio_analysis_result.dart';
import 'audio_calibration_state.dart';
import 'audio_chunk.dart';
import 'audio_ring_buffer.dart';
import 'goertzel_band_analyzer.dart';
import 'pcm16le_reader.dart';

const _centers = [
  120.0,
  180.0,
  250.0,
  400.0,
  600.0,
  800.0,
  1000.0,
  1500.0,
  2000.0,
  3000.0,
  4000.0
];
const _minDbfs = -120.0;
const _fallbackAmbientDbfs = -55.0;
const _minimumUsableAmbientDbfs = -65.0;

/// Ambient-aware, deterministic cry-likelihood analyzer for PCM16LE chunks.
class CryAudioAnalyzerV2 {
  CryAudioAnalyzerV2({this.config = const AudioAnalysisConfig()})
      : _ring = AudioRingBuffer(
          sampleRate: config.sampleRate,
          windowMs: config.windowMs,
          hopMs: config.hopMs,
        ),
        _goertzel = GoertzelBandAnalyzer(
          sampleRate: config.sampleRate,
          centerFrequencies: _centers,
        );

  final AudioAnalysisConfig config;
  final AudioRingBuffer _ring;
  final GoertzelBandAnalyzer _goertzel;
  AudioCalibrationState _state = AudioCalibrationState.uncalibrated;
  int? _calibrationStartMs;
  final List<double> _calibrationDbfs = [];
  int _calibrationAcceptedMs = 0;
  int? _lastCalibrationAcceptedAtMs;
  bool _calibrationTimedOut = false;
  double _ambientDbfs = _fallbackAmbientDbfs;
  double _previousCryScore = 0;
  List<double>? _previousBandVector;
  bool _candidateActive = false;
  int? _candidateStartMs;
  int? _lastChunkEndMs;

  AudioCalibrationState get calibrationState => _state;
  double? get calibratedAmbientDbfs =>
      _state == AudioCalibrationState.calibrated ? _ambientDbfs : null;

  void startCalibration({int? timestampMs}) {
    // A requested baseline must contain only audio captured afterwards. The
    // previous sliding window otherwise counts up to a full second of old
    // room audio toward a newly requested calibration.
    markDiscontinuity();
    _state = AudioCalibrationState.calibrating;
    _calibrationStartMs = timestampMs;
    _calibrationDbfs.clear();
    _calibrationAcceptedMs = 0;
    _lastCalibrationAcceptedAtMs = null;
    _calibrationTimedOut = false;
    _candidateActive = false;
    _candidateStartMs = null;
  }

  void resetCalibration() {
    _state = AudioCalibrationState.uncalibrated;
    _calibrationStartMs = null;
    _calibrationDbfs.clear();
    _calibrationAcceptedMs = 0;
    _lastCalibrationAcceptedAtMs = null;
    _calibrationTimedOut = false;
    _ambientDbfs = _fallbackAmbientDbfs;
  }

  /// Reuses a trusted room baseline when only thresholds/cooldowns change.
  ///
  /// This avoids a new 30-second notification blackout after every settings
  /// adjustment. Capture restarts still use [startCalibration].
  void restoreCalibratedAmbient(double ambientDbfs) {
    _state = AudioCalibrationState.calibrated;
    _calibrationStartMs = null;
    _calibrationDbfs.clear();
    _calibrationAcceptedMs = config.calibrationMs;
    _lastCalibrationAcceptedAtMs = null;
    _calibrationTimedOut = false;
    _ambientDbfs = ambientDbfs.clamp(_minimumUsableAmbientDbfs, 0).toDouble();
    markDiscontinuity();
  }

  void reset() {
    markDiscontinuity();
    resetCalibration();
  }

  /// Clears temporal classification state without losing the calibrated room
  /// baseline. Use this when capture contains an intentional gap such as
  /// comfort audio or parent talkback suppression.
  void markDiscontinuity() {
    _ring.reset();
    _previousCryScore = 0;
    _previousBandVector = null;
    _candidateActive = false;
    _candidateStartMs = null;
    _lastChunkEndMs = null;
    if (_state == AudioCalibrationState.calibrating) {
      // A calibration interval must contain continuous room audio. Do not let
      // talkback/comfort-audio suppression or a capture drop make a handful
      // of old samples look like a complete 30-second baseline.
      _calibrationStartMs = null;
      _calibrationDbfs.clear();
      _calibrationAcceptedMs = 0;
      _lastCalibrationAcceptedAtMs = null;
      _calibrationTimedOut = false;
    }
  }

  List<AudioAnalysisResult> addChunk(AudioChunk chunk) {
    if (chunk.sampleRate != config.sampleRate || chunk.channels <= 0) {
      markDiscontinuity();
      return [_invalidResult(chunk.timestampMs)];
    }
    if (chunk.pcm16le.isEmpty) {
      markDiscontinuity();
      return [_invalidResult(chunk.timestampMs)];
    }
    final frameBytes = chunk.channels * 2;
    if (chunk.pcm16le.length % frameBytes != 0) {
      markDiscontinuity();
      return [_invalidResult(chunk.timestampMs)];
    }
    final samples = Pcm16LeReader.readMonoSamples(
      chunk.pcm16le,
      channels: chunk.channels,
    );
    final results = <AudioAnalysisResult>[];
    if (samples.isEmpty) {
      // A truncated frame is a capture discontinuity. Keeping the previous
      // ring/candidate would allow evidence on either side of corrupt PCM to
      // be joined into one apparently continuous cry.
      markDiscontinuity();
      results.add(_invalidResult(chunk.timestampMs));
      return results;
    }

    final chunkDurationMs = samples.isEmpty
        ? 0
        : (samples.length * 1000 / max(1, chunk.sampleRate)).round();
    final chunkStartMs = chunk.timestampMs - chunkDurationMs;
    final lastChunkEndMs = _lastChunkEndMs;
    final discontinuityToleranceMs = max(500, config.hopMs * 2);
    if (lastChunkEndMs != null) {
      final gapMs = chunkStartMs - lastChunkEndMs;
      if (gapMs > discontinuityToleranceMs ||
          gapMs < -discontinuityToleranceMs) {
        markDiscontinuity();
      }
    }
    _lastChunkEndMs = chunk.timestampMs;
    var offset = 0;
    while (offset < samples.length) {
      final end = min(samples.length, offset + _ring.hopSamples);
      final part = Int16List.sublistView(samples, offset, end);
      final partTimestampMs =
          chunkStartMs + (end * 1000 / max(1, chunk.sampleRate)).round();
      _ring.addSamples(part, timestampMs: partTimestampMs);
      if (_ring.shouldAnalyze(partTimestampMs)) {
        results.add(_analyzeWindow(_ring.readLatestWindow(), partTimestampMs));
      }
      offset = end;
    }
    return results;
  }

  Map<String, Object?> diagnostics() => {
        'calibrationState': _state.name,
        'ambientDbfs': _ambientDbfs,
        'calibrationAcceptedMs': _calibrationAcceptedMs,
        'calibrationTimedOut': _calibrationTimedOut,
        'previousCryScore': _previousCryScore,
        'candidateActive': _candidateActive,
        'config': config.toJson(),
      };

  AudioAnalysisResult _analyzeWindow(Int16List samples, int timestampMs) {
    final sw = Stopwatch()..start();
    if (samples.isEmpty) return _invalidResult(timestampMs);
    final normalized = List<double>.filled(samples.length, 0);
    var sumSq = 0.0;
    var peak = 0.0;
    var crossings = 0;
    var previous = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final sample = Pcm16LeReader.sampleToDouble(samples[i]);
      normalized[i] = sample;
      sumSq += sample * sample;
      peak = max(peak, sample.abs());
      if (i > 0 &&
          ((sample >= 0 && previous < 0) || (sample < 0 && previous >= 0))) {
        crossings++;
      }
      previous = sample;
    }
    final rms = sqrt(sumSq / samples.length);
    final dbfs = max(_minDbfs, 20 * log(max(rms, 1e-9)) / ln10);
    final zcr = crossings / samples.length;
    final bands = _goertzel.analyzeNormalizedSamples(normalized);
    final vector = _centers.map((f) => bands[f] ?? 0).toList(growable: false);
    final total = vector.fold<double>(0, (a, b) => a + b);
    double bandRatio(bool Function(double) include) {
      if (total <= 0) return 0;
      var energy = 0.0;
      for (var i = 0; i < _centers.length; i++) {
        if (include(_centers[i])) energy += vector[i];
      }
      return (energy / total).clamp(0.0, 1.0).toDouble();
    }

    final lowRatio = bandRatio((f) => f >= 250 && f <= 600);
    final subCryVoiceRatio = bandRatio((f) => f < 300);
    final cryRatio = bandRatio((f) => f >= 400 && f <= 1500);
    final highRatio = bandRatio((f) => f >= 1500 && f <= 4000);
    final centroid = total <= 0 ? 0.0 : _weightedCentroid(vector, total);
    final entropy = _entropy(vector, total);
    final flux = _spectralFlux(vector, _previousBandVector);
    final amplitudeModulation = _amplitudeModulation(normalized);
    final isClipped = peak >= .98;

    final isBroadbandNoise =
        entropy >= 0.80 && highRatio >= 0.25 && cryRatio < 0.85;
    final hasCrySpectralShape = !isBroadbandNoise &&
        cryRatio >= 0.40 &&
        subCryVoiceRatio <= 0.35 &&
        zcr >= 0.015 &&
        zcr <= 0.38 &&
        centroid >= 300 &&
        centroid <= 3000 &&
        (entropy >= 0.10 || amplitudeModulation >= 0.06) &&
        entropy <= 0.95;
    final wasCalibrating = _state == AudioCalibrationState.calibrating;
    final calibrationContaminated = isClipped ||
        (dbfs >= config.minDbfsForCryCandidate && hasCrySpectralShape);
    _updateCalibration(
      dbfs,
      timestampMs,
      acceptSample: !calibrationContaminated,
    );
    final ambient = _state == AudioCalibrationState.uncalibrated
        ? _fallbackAmbientDbfs
        : _ambientDbfs;
    final delta = dbfs - ambient;
    final energyScore = _norm(delta, 6, 24);
    final bandScore = _norm(cryRatio, 0.25, 0.65);
    final zcrScore = _trapezoid(zcr, 0.02, 0.04, 0.22, 0.34);
    final centroidScore = _trapezoid(centroid, 350, 600, 2200, 3200);
    final fluxScore = _norm(flux, 0.0005, 0.03);
    final weightSum = max(
        1e-9,
        config.energyWeight +
            config.bandWeight +
            config.zcrWeight +
            config.centroidWeight +
            config.fluxWeight);
    var raw = (config.energyWeight * energyScore +
            config.bandWeight * bandScore +
            config.zcrWeight * zcrScore +
            config.centroidWeight * centroidScore +
            config.fluxWeight * fluxScore) /
        weightSum;
    if (dbfs < config.minDbfsForCryCandidate) raw *= 0.35;
    // Energy alone is not cry evidence. This gate rejects common steady tones,
    // broad-band fan/white-noise steps, and sensor hiss before the temporal
    // episode logic sees them. Adult speech can still overlap this envelope,
    // which is why duration and duty-cycle confirmation remain mandatory.
    if (!hasCrySpectralShape) raw *= 0.25;
    // Saturated PCM no longer represents the room waveform reliably. It must
    // not become cry evidence (or keep an earlier candidate alive) merely
    // because clipping spreads energy across the watched bands.
    if (isClipped) raw = 0;
    raw = raw.clamp(0.0, 1.0).toDouble();
    final alpha = config.smoothingAlpha.clamp(0.0, 1.0).toDouble();
    final score = isClipped
        ? 0.0
        : (_previousCryScore * (1 - alpha) + raw * alpha)
            .clamp(0.0, 1.0)
            .toDouble();
    _previousCryScore = wasCalibrating || isClipped ? 0 : score;
    _previousBandVector = wasCalibrating || isClipped ? null : vector;
    final isLoud = dbfs >= config.loudSoundDbfs;
    final likely = wasCalibrating || isClipped
        ? false
        : _updateDecision(score, timestampMs);
    if (wasCalibrating || isClipped) {
      _candidateActive = false;
      _candidateStartMs = null;
    }
    if (_state == AudioCalibrationState.calibrated &&
        !wasCalibrating &&
        !likely &&
        !isLoud &&
        raw < config.cryOffThreshold) {
      _ambientDbfs = (_ambientDbfs * (1 - config.ambientUpdateAlpha) +
              dbfs * config.ambientUpdateAlpha)
          .clamp(_minimumUsableAmbientDbfs, 0)
          .toDouble();
    }
    sw.stop();
    return AudioAnalysisResult(
      timestampMs: timestampMs,
      cryScore: wasCalibrating ? 0 : score,
      rawCryScore: wasCalibrating ? 0 : raw,
      isCryLikely: likely,
      isCalibrated: _state == AudioCalibrationState.calibrated,
      calibrationState: _state,
      rms: rms,
      dbfs: dbfs,
      peak: peak,
      zeroCrossingRate: zcr,
      ambientDbfs: ambient,
      ambientDeltaDb: delta,
      cryBandRatio: cryRatio,
      lowBandRatio: lowRatio,
      highBandRatio: highRatio,
      spectralCentroid: centroid,
      spectralEntropy: entropy,
      spectralFlux: flux,
      amplitudeModulation: amplitudeModulation,
      invalidChunk: false,
      isClipped: isClipped,
      isLoudSound: isLoud,
      processingTimeMicros: sw.elapsedMicroseconds,
    );
  }

  void _updateCalibration(
    double dbfs,
    int timestampMs, {
    required bool acceptSample,
  }) {
    if (_state != AudioCalibrationState.calibrating) return;
    _calibrationStartMs ??= timestampMs;
    if (!acceptSample) {
      _finishCalibrationIfExpired(timestampMs);
      return;
    }
    _calibrationAcceptedMs +=
        _lastCalibrationAcceptedAtMs == null ? config.windowMs : config.hopMs;
    _lastCalibrationAcceptedAtMs = timestampMs;
    _calibrationDbfs.add(dbfs);
    if (_calibrationAcceptedMs >= config.calibrationMs) {
      _finishCalibration(timedOut: false);
      return;
    }
    _finishCalibrationIfExpired(timestampMs);
  }

  void _finishCalibrationIfExpired(int timestampMs) {
    final startedAtMs = _calibrationStartMs;
    if (startedAtMs == null) return;
    final maxElapsedMs = max(
      config.calibrationMs * 2,
      config.calibrationMs + 5000,
    );
    if (timestampMs - startedAtMs < maxElapsedMs) return;
    _finishCalibration(timedOut: true);
  }

  void _finishCalibration({required bool timedOut}) {
    _ambientDbfs = _robustAmbientDbfs(_calibrationDbfs);
    _state = AudioCalibrationState.calibrated;
    _calibrationTimedOut = timedOut;
    _calibrationStartMs = null;
    _calibrationDbfs.clear();
    _lastCalibrationAcceptedAtMs = null;
  }

  double _robustAmbientDbfs(List<double> samples) {
    final sorted = samples.where((value) => value.isFinite).toList()..sort();
    if (sorted.isEmpty) return _fallbackAmbientDbfs;

    // Cry-shaped/clipped windows are rejected before this point, so the
    // ordinary median is robust to isolated room transients without the
    // downward bias caused by trimming the loudest fifth first. A
    // digital-silence baseline is still floored so the first fan sample cannot
    // gain an artificial 80 dB energy advantage.
    final middle = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
    return median.clamp(_minimumUsableAmbientDbfs, 0).toDouble();
  }

  bool _updateDecision(double score, int timestampMs) {
    if (!_candidateActive) {
      if (score >= config.cryOnThreshold) {
        _candidateActive = true;
        _candidateStartMs = timestampMs;
      }
    } else if (score <= config.cryOffThreshold) {
      _candidateActive = false;
      _candidateStartMs = null;
    }
    return _candidateActive &&
        _candidateStartMs != null &&
        timestampMs - _candidateStartMs! >= config.minCryDurationMs;
  }

  double _weightedCentroid(List<double> vector, double total) {
    var sum = 0.0;
    for (var i = 0; i < vector.length; i++) {
      sum += _centers[i] * vector[i];
    }
    return sum / total;
  }

  double _entropy(List<double> vector, double total) {
    if (total <= 0) return 0;
    var e = 0.0;
    for (final v in vector) {
      if (v > 0) {
        final p = v / total;
        e -= p * log(p);
      }
    }
    return (e / log(vector.length)).clamp(0.0, 1.0).toDouble();
  }

  double _spectralFlux(List<double> current, List<double>? previous) {
    if (previous == null) return 0;
    var sum = 0.0;
    for (var i = 0; i < current.length; i++) {
      sum += max(0, current[i] - previous[i]);
    }
    return sum;
  }

  double _amplitudeModulation(List<double> samples) {
    if (samples.isEmpty) return 0;
    final blockSize = max(1, config.sampleRate ~/ 20);
    final envelope = <double>[];
    for (var start = 0; start < samples.length; start += blockSize) {
      final end = min(samples.length, start + blockSize);
      if (end - start < blockSize ~/ 2) break;
      var sumSq = 0.0;
      for (var index = start; index < end; index++) {
        sumSq += samples[index] * samples[index];
      }
      envelope.add(sqrt(sumSq / (end - start)));
    }
    if (envelope.length < 3) return 0;
    final mean =
        envelope.reduce((first, second) => first + second) / envelope.length;
    if (mean <= 1e-9) return 0;
    var variance = 0.0;
    for (final value in envelope) {
      final delta = value - mean;
      variance += delta * delta;
    }
    return (sqrt(variance / envelope.length) / mean).clamp(0.0, 1.0).toDouble();
  }

  AudioAnalysisResult _invalidResult(int timestampMs) => AudioAnalysisResult(
        timestampMs: timestampMs,
        cryScore: _previousCryScore,
        rawCryScore: 0,
        isCryLikely: false,
        isCalibrated: _state == AudioCalibrationState.calibrated,
        calibrationState: _state,
        rms: 0,
        dbfs: _minDbfs,
        peak: 0,
        zeroCrossingRate: 0,
        ambientDbfs: _ambientDbfs,
        ambientDeltaDb: 0,
        cryBandRatio: 0,
        lowBandRatio: 0,
        highBandRatio: 0,
        spectralCentroid: 0,
        spectralEntropy: 0,
        spectralFlux: 0,
        amplitudeModulation: 0,
        invalidChunk: true,
        processingTimeMicros: 0,
      );
}

double _norm(double value, double minValue, double maxValue) =>
    ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0).toDouble();

double _trapezoid(
    double v, double start, double fullStart, double fullEnd, double end) {
  if (v <= start || v >= end) return 0;
  if (v >= fullStart && v <= fullEnd) return 1;
  if (v < fullStart) return _norm(v, start, fullStart);
  return 1 - _norm(v, fullEnd, end);
}
