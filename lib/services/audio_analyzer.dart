import 'dart:math';
import 'dart:typed_data';

class AudioAnalysisResult {
  const AudioAnalysisResult({
    required this.rms,
    required this.dbfs,
    required this.ambientRms,
    required this.cryScore,
    required this.moanScore,
    required this.zeroCrossRate,
    required this.spectralCentroidHz,
    required this.spectralBandwidthHz,
    required this.spectralEntropy,
    required this.fundamentalHz,
    required this.voiceActivityScore,
    required this.alert,
    required this.reason,
  });

  final double rms;
  final double dbfs;
  final double ambientRms;
  final double cryScore;
  final double moanScore;
  final double zeroCrossRate;
  final double spectralCentroidHz;
  final double spectralBandwidthHz;
  final double spectralEntropy;
  final double fundamentalHz;
  final double voiceActivityScore;
  final bool alert;
  final String reason;

  String get dominantSound => cryScore >= moanScore ? 'ağlama' : 'inleme';

  String get summary {
    final f0 = fundamentalHz > 0 ? '${fundamentalHz.round()} Hz' : 'belirsiz';
    return 'seviye ${dbfs.toStringAsFixed(1)} dBFS, ortam ${(20 * log(max(ambientRms, 1e-6)) / ln10).toStringAsFixed(1)} dBFS, '
        'F0 $f0, merkez ${spectralCentroidHz.round()} Hz, bant ${spectralBandwidthHz.round()} Hz, '
        'ZCR ${zeroCrossRate.toStringAsFixed(2)}, entropi ${spectralEntropy.toStringAsFixed(2)}, '
        'ağlama ${(cryScore * 100).round()}%, inleme ${(moanScore * 100).round()}%';
  }
}

class _BandProfile {
  const _BandProfile(
    this.lowEnergy,
    this.cryEnergy,
    this.harshEnergy,
    this.totalEnergy,
  );

  final double lowEnergy;
  final double cryEnergy;
  final double harshEnergy;
  final double totalEnergy;
}

class _SpectralShape {
  const _SpectralShape({
    required this.centroidHz,
    required this.bandwidthHz,
    required this.entropy,
  });

  final double centroidHz;
  final double bandwidthHz;
  final double entropy;
}

class AudioAnalyzer {
  AudioAnalyzer({this.sampleRate = 16000});

  final int sampleRate;
  double _ambientRms = 0.015;
  double _sustainedCry = 0;
  double _sustainedMoan = 0;
  double _sustainedVoiceActivity = 0;
  DateTime _lastAlert = DateTime.fromMillisecondsSinceEpoch(0);

  AudioAnalysisResult analyzePcm16(Uint8List pcmBytes) {
    final samples = _decodePcm16Le(pcmBytes);
    if (samples.isEmpty) return _empty();

    final rms = _rms(samples);
    final zeroCrossRate = _zeroCrossRate(samples);
    _ambientRms = _trackAmbient(rms);
    final dbfs = 20 * log(max(rms, 1e-6)) / ln10;
    final aboveAmbient = _smoothStep(rms / max(_ambientRms, 1e-5), 1.55, 5.25);

    final bands = _bandProfile(samples);
    final spectral = _spectralShape(samples);
    final fundamentalHz = _estimateFundamentalHz(samples);

    final lowRatio = (bands.lowEnergy / bands.totalEnergy).clamp(0.0, 1.0);
    final cryRatio = (bands.cryEnergy / bands.totalEnergy).clamp(0.0, 1.0);
    final harshRatio = (bands.harshEnergy / bands.totalEnergy).clamp(0.0, 1.0);

    final infantPitchComponent = _triangularScore(fundamentalHz, 250, 470, 680);
    final cryCentroidComponent = _smoothStep(spectral.centroidHz, 450, 1800) *
        (1 - _smoothStep(spectral.centroidHz, 4300, 6200));
    final narrowVoicedComponent =
        (1 - _smoothStep(spectral.entropy, 0.55, 0.92)).clamp(0.0, 1.0);
    final zeroCrossComponent = _smoothStep(zeroCrossRate, 0.08, 0.35);
    final cryTimbre =
        (cryRatio * 1.12 + harshRatio * 0.58 + cryCentroidComponent * 0.40).clamp(0.0, 1.0);
    final moanTimbre =
        (lowRatio * 1.15 + (1 - _smoothStep(spectral.centroidHz, 360, 1100)) * 0.35).clamp(0.0, 1.0);

    final voiceActivity = (0.52 * aboveAmbient +
            0.28 * narrowVoicedComponent +
            0.20 * _smoothStep(bands.totalEnergy, 0.00002, 0.003))
        .clamp(0.0, 1.0);
    final cryScore = (0.34 * aboveAmbient +
            0.27 * cryTimbre +
            0.21 * infantPitchComponent +
            0.10 * zeroCrossComponent +
            0.08 * voiceActivity)
        .clamp(0.0, 1.0);
    final moanScore = (0.42 * aboveAmbient +
            0.37 * moanTimbre +
            0.13 * (1 - zeroCrossComponent) +
            0.08 * voiceActivity)
        .clamp(0.0, 1.0);

    _sustainedCry = _leakyIntegrator(_sustainedCry, cryScore, attack: 0.35, release: 0.08);
    _sustainedMoan = _leakyIntegrator(_sustainedMoan, moanScore, attack: 0.25, release: 0.06);
    _sustainedVoiceActivity = _leakyIntegrator(_sustainedVoiceActivity, voiceActivity, attack: 0.30, release: 0.10);

    final now = DateTime.now();
    final cooldownPassed = now.difference(_lastAlert) > const Duration(seconds: 12);
    final cryAlert = _sustainedCry > 0.72 &&
        rms > _ambientRms * 2.05 &&
        _sustainedVoiceActivity > 0.45;
    final moanAlert = _sustainedMoan > 0.78 &&
        rms > _ambientRms * 1.75 &&
        _sustainedVoiceActivity > 0.38;
    final alert = cooldownPassed && (cryAlert || moanAlert);
    if (alert) _lastAlert = now;

    return AudioAnalysisResult(
      rms: rms,
      dbfs: dbfs,
      ambientRms: _ambientRms,
      cryScore: _sustainedCry,
      moanScore: _sustainedMoan,
      zeroCrossRate: zeroCrossRate,
      spectralCentroidHz: spectral.centroidHz,
      spectralBandwidthHz: spectral.bandwidthHz,
      spectralEntropy: spectral.entropy,
      fundamentalHz: fundamentalHz,
      voiceActivityScore: _sustainedVoiceActivity,
      alert: alert,
      reason: _buildReason(
        cryLike: _sustainedCry >= _sustainedMoan,
        fundamentalHz: fundamentalHz,
        spectral: spectral,
      ),
    );
  }

  AudioAnalysisResult _empty() => AudioAnalysisResult(
        rms: 0,
        dbfs: -120,
        ambientRms: _ambientRms,
        cryScore: _sustainedCry,
        moanScore: _sustainedMoan,
        zeroCrossRate: 0,
        spectralCentroidHz: 0,
        spectralBandwidthHz: 0,
        spectralEntropy: 0,
        fundamentalHz: 0,
        voiceActivityScore: _sustainedVoiceActivity,
        alert: false,
        reason: 'Ses yok',
      );

  List<double> _decodePcm16Le(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final count = bytes.length ~/ 2;
    return List<double>.generate(
      count,
      (i) => data.getInt16(i * 2, Endian.little) / 32768.0,
      growable: false,
    );
  }

  double _rms(List<double> samples) {
    var sum = 0.0;
    for (final sample in samples) {
      sum += sample * sample;
    }
    return sqrt(sum / samples.length);
  }

  double _zeroCrossRate(List<double> samples) {
    if (samples.length < 2) return 0;
    var crossings = 0;
    var previous = samples.first;
    for (var i = 1; i < samples.length; i++) {
      final sample = samples[i];
      if ((sample >= 0 && previous < 0) || (sample < 0 && previous >= 0)) crossings++;
      previous = sample;
    }
    return crossings / (samples.length - 1);
  }

  double _trackAmbient(double rms) {
    final alpha = rms < _ambientRms ? 0.08 : 0.006;
    return (_ambientRms * (1 - alpha) + rms * alpha).clamp(0.003, 0.35);
  }

  _BandProfile _bandProfile(List<double> samples) {
    final low = _bandEnergy(samples, 180, 420);
    final cry = _bandEnergy(samples, 420, 1600);
    final harsh = _bandEnergy(samples, 1600, 3600);
    return _BandProfile(low, cry, harsh, low + cry + harsh + 1e-9);
  }

  double _bandEnergy(List<double> samples, double lowHz, double highHz) {
    const probesPerBand = 7;
    var energy = 0.0;
    for (var i = 0; i < probesPerBand; i++) {
      final t = probesPerBand == 1 ? 0.5 : i / (probesPerBand - 1);
      final frequency = lowHz + (highHz - lowHz) * t;
      energy += _goertzelPower(samples, frequency);
    }
    final bandwidthWeight = (highHz - lowHz) / sampleRate;
    return max(0, energy * bandwidthWeight / (samples.length * probesPerBand));
  }

  _SpectralShape _spectralShape(List<double> samples) {
    const probes = 28;
    const minHz = 120.0;
    final maxHz = min(5000.0, sampleRate / 2 - 1);
    final powers = <double>[];
    var total = 0.0;
    var weighted = 0.0;
    for (var i = 0; i < probes; i++) {
      final frequency = minHz + (maxHz - minHz) * i / (probes - 1);
      final power = max(0.0, _goertzelPower(samples, frequency));
      powers.add(power);
      total += power;
      weighted += power * frequency;
    }
    if (total <= 1e-12) {
      return const _SpectralShape(centroidHz: 0, bandwidthHz: 0, entropy: 0);
    }
    final centroid = weighted / total;
    var variance = 0.0;
    var entropy = 0.0;
    for (var i = 0; i < probes; i++) {
      final frequency = minHz + (maxHz - minHz) * i / (probes - 1);
      final probability = powers[i] / total;
      final distanceFromCentroid = frequency - centroid;
      variance += probability * distanceFromCentroid * distanceFromCentroid;
      entropy -= probability * log(probability + 1e-12) / ln2;
    }
    return _SpectralShape(
      centroidHz: centroid,
      bandwidthHz: sqrt(variance),
      entropy: (entropy / (log(probes) / ln2)).clamp(0.0, 1.0),
    );
  }

  double _estimateFundamentalHz(List<double> samples) {
    final minLag = max(1, sampleRate ~/ 700);
    final maxLag = min(samples.length - 2, sampleRate ~/ 160);
    var bestLag = 0;
    var bestCorrelation = 0.0;
    var zeroLag = 0.0;
    for (final sample in samples) {
      zeroLag += sample * sample;
    }
    if (zeroLag <= 1e-9) return 0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      var correlation = 0.0;
      for (var i = 0; i < samples.length - lag; i++) {
        correlation += samples[i] * samples[i + lag];
      }
      final normalized = correlation / zeroLag;
      if (normalized > bestCorrelation) {
        bestCorrelation = normalized;
        bestLag = lag;
      }
    }
    return bestCorrelation > 0.28 && bestLag > 0 ? sampleRate / bestLag : 0;
  }

  double _goertzelPower(List<double> samples, double frequency) {
    final omega = 2 * pi * frequency / sampleRate;
    final coeff = 2 * cos(omega);
    var q0 = 0.0;
    var q1 = 0.0;
    var q2 = 0.0;
    for (final sample in samples) {
      q0 = coeff * q1 - q2 + sample;
      q2 = q1;
      q1 = q0;
    }
    return q1 * q1 + q2 * q2 - coeff * q1 * q2;
  }

  double _smoothStep(double value, double edge0, double edge1) {
    final x = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  double _triangularScore(double value, double low, double peak, double high) {
    if (value <= 0 || value <= low || value >= high) return 0;
    if (value <= peak) return ((value - low) / (peak - low)).clamp(0.0, 1.0);
    return ((high - value) / (high - peak)).clamp(0.0, 1.0);
  }

  double _leakyIntegrator(
    double previous,
    double current, {
    required double attack,
    required double release,
  }) {
    final factor = current > previous ? attack : release;
    return previous * (1 - factor) + current * factor;
  }

  String _buildReason({
    required bool cryLike,
    required double fundamentalHz,
    required _SpectralShape spectral,
  }) {
    final pitch = fundamentalHz > 0 ? ', temel frekans ${fundamentalHz.round()} Hz' : '';
    if (cryLike) {
      return 'Ağlama benzeri vokal ses$pitch, parlaklık ${spectral.centroidHz.round()} Hz';
    }
    return 'İnleme benzeri düşük frekanslı sürekli ses$pitch, merkez ${spectral.centroidHz.round()} Hz';
  }
}
