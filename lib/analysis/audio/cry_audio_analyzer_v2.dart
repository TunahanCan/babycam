import 'dart:math';
import 'dart:typed_data';

import 'audio_analysis_config.dart';
import 'audio_analysis_result.dart';
import 'audio_calibration_state.dart';
import 'audio_chunk.dart';
import 'audio_ring_buffer.dart';
import 'goertzel_band_analyzer.dart';
import 'pcm16le_reader.dart';

const _centers = [250.0, 400.0, 600.0, 800.0, 1000.0, 1500.0, 2000.0, 3000.0, 4000.0];
const _minDbfs = -120.0;
const _fallbackAmbientDbfs = -55.0;

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
  double _ambientDbfs = _fallbackAmbientDbfs;
  double _previousCryScore = 0;
  List<double>? _previousBandVector;
  bool _candidateActive = false;
  int? _candidateStartMs;

  AudioCalibrationState get calibrationState => _state;

  void startCalibration({int? timestampMs}) {
    _state = AudioCalibrationState.calibrating;
    _calibrationStartMs = timestampMs;
    _calibrationDbfs.clear();
    _candidateActive = false;
    _candidateStartMs = null;
  }

  void resetCalibration() {
    _state = AudioCalibrationState.uncalibrated;
    _calibrationStartMs = null;
    _calibrationDbfs.clear();
    _ambientDbfs = _fallbackAmbientDbfs;
  }

  void reset() {
    _ring.reset();
    resetCalibration();
    _previousCryScore = 0;
    _previousBandVector = null;
    _candidateActive = false;
    _candidateStartMs = null;
  }

  List<AudioAnalysisResult> addChunk(AudioChunk chunk) {
    final samples = Pcm16LeReader.readMonoSamples(
      chunk.pcm16le,
      channels: chunk.channels,
    );
    final results = <AudioAnalysisResult>[];
    if (chunk.pcm16le.isNotEmpty && samples.isEmpty) {
      results.add(_invalidResult(chunk.timestampMs));
      return results;
    }

    final chunkDurationMs = samples.isEmpty
        ? 0
        : (samples.length * 1000 / max(1, chunk.sampleRate)).round();
    final chunkStartMs = chunk.timestampMs - chunkDurationMs;
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
      if (i > 0 && ((sample >= 0 && previous < 0) || (sample < 0 && previous >= 0))) crossings++;
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
    final cryRatio = bandRatio((f) => f >= 400 && f <= 1500);
    final highRatio = bandRatio((f) => f >= 1500 && f <= 4000);
    final centroid = total <= 0 ? 0.0 : _weightedCentroid(vector, total);
    final entropy = _entropy(vector, total);
    final flux = _spectralFlux(vector, _previousBandVector);
    _previousBandVector = vector;

    _updateCalibration(dbfs, timestampMs);
    final ambient = _state == AudioCalibrationState.uncalibrated ? _fallbackAmbientDbfs : _ambientDbfs;
    final delta = dbfs - ambient;
    final energyScore = _norm(delta, 6, 24);
    final bandScore = _norm(cryRatio, 0.25, 0.65);
    final zcrScore = _trapezoid(zcr, 0.02, 0.04, 0.22, 0.34);
    final centroidScore = _trapezoid(centroid, 350, 600, 2200, 3200);
    final fluxScore = _norm(flux, 0.0005, 0.03);
    final weightSum = max(1e-9, config.energyWeight + config.bandWeight + config.zcrWeight + config.centroidWeight + config.fluxWeight);
    var raw = (config.energyWeight * energyScore + config.bandWeight * bandScore + config.zcrWeight * zcrScore + config.centroidWeight * centroidScore + config.fluxWeight * fluxScore) / weightSum;
    if (dbfs < config.minDbfsForCryCandidate) raw *= 0.35;
    raw = raw.clamp(0.0, 1.0).toDouble();
    final alpha = config.smoothingAlpha.clamp(0.0, 1.0).toDouble();
    final score = (_previousCryScore * (1 - alpha) + raw * alpha).clamp(0.0, 1.0).toDouble();
    _previousCryScore = score;
    final isLoud = dbfs >= config.loudSoundDbfs;
    final likely = _updateDecision(score, timestampMs) && _state != AudioCalibrationState.calibrating;
    if (_state == AudioCalibrationState.calibrated && !likely && !isLoud && score < config.cryOffThreshold) {
      _ambientDbfs = _ambientDbfs * (1 - config.ambientUpdateAlpha) + dbfs * config.ambientUpdateAlpha;
    }
    sw.stop();
    return AudioAnalysisResult(
      timestampMs: timestampMs,
      cryScore: score,
      rawCryScore: raw,
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
      invalidChunk: false,
      isLoudSound: isLoud,
      processingTimeMicros: sw.elapsedMicroseconds,
    );
  }

  void _updateCalibration(double dbfs, int timestampMs) {
    if (_state != AudioCalibrationState.calibrating) return;
    _calibrationStartMs ??= timestampMs;
    _calibrationDbfs.add(dbfs);
    if (timestampMs - _calibrationStartMs! >= config.calibrationMs) {
      _ambientDbfs = _calibrationDbfs.isEmpty ? _fallbackAmbientDbfs : _calibrationDbfs.reduce((a, b) => a + b) / _calibrationDbfs.length;
      _state = AudioCalibrationState.calibrated;
      _calibrationDbfs.clear();
    }
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
    return _candidateActive && _candidateStartMs != null && timestampMs - _candidateStartMs! >= config.minCryDurationMs;
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
        invalidChunk: true,
        processingTimeMicros: 0,
      );
}

double _norm(double value, double minValue, double maxValue) =>
    ((value - minValue) / (maxValue - minValue))
        .clamp(0.0, 1.0)
        .toDouble();

double _trapezoid(double v, double start, double fullStart, double fullEnd, double end) {
  if (v <= start || v >= end) return 0;
  if (v >= fullStart && v <= fullEnd) return 1;
  if (v < fullStart) return _norm(v, start, fullStart);
  return 1 - _norm(v, fullEnd, end);
}
