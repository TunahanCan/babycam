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
    required this.alert,
    required this.reason,
  });

  final double rms;
  final double dbfs;
  final double ambientRms;
  final double cryScore;
  final double moanScore;
  final double zeroCrossRate;
  final bool alert;
  final String reason;
}

class AudioAnalyzer {
  AudioAnalyzer({this.sampleRate = 16000});

  final int sampleRate;
  double _ambientRms = 0.015;
  double _sustainedCry = 0;
  double _sustainedMoan = 0;
  DateTime _lastAlert = DateTime.fromMillisecondsSinceEpoch(0);

  AudioAnalysisResult analyzePcm16(Uint8List pcmBytes) {
    final samples = _decodePcm16Le(pcmBytes);
    if (samples.isEmpty) return _empty();

    final rms = _rms(samples);
    final zeroCrossRate = _zeroCrossRate(samples);
    _ambientRms = _trackAmbient(rms);
    final dbfs = 20 * log(max(rms, 1e-6)) / ln10;

    final low = _bandEnergy(samples, 180, 420);
    final cry = _bandEnergy(samples, 420, 1600);
    final harsh = _bandEnergy(samples, 1600, 3600);
    final total = low + cry + harsh + 1e-9;

    final aboveAmbient = _smoothStep(rms / max(_ambientRms, 1e-5), 1.7, 5.5);
    final cryTimbre = ((cry * 1.25 + harsh * 0.65) / total).clamp(0.0, 1.0);
    final moanTimbre = (low / total).clamp(0.0, 1.0);

    final zeroCrossComponent = _smoothStep(zeroCrossRate, 0.08, 0.35);
    final cryScore = (0.50 * aboveAmbient + 0.38 * cryTimbre + 0.12 * zeroCrossComponent).clamp(0.0, 1.0);
    final moanScore = (0.50 * aboveAmbient + 0.50 * moanTimbre).clamp(0.0, 1.0);

    _sustainedCry = _leakyIntegrator(_sustainedCry, cryScore, attack: 0.35, release: 0.08);
    _sustainedMoan = _leakyIntegrator(_sustainedMoan, moanScore, attack: 0.25, release: 0.06);

    final now = DateTime.now();
    final cooldownPassed = now.difference(_lastAlert) > const Duration(seconds: 12);
    final cryAlert = _sustainedCry > 0.72 && rms > _ambientRms * 2.2;
    final moanAlert = _sustainedMoan > 0.78 && rms > _ambientRms * 1.8;
    final alert = cooldownPassed && (cryAlert || moanAlert);
    if (alert) _lastAlert = now;

    return AudioAnalysisResult(
      rms: rms,
      dbfs: dbfs,
      ambientRms: _ambientRms,
      cryScore: _sustainedCry,
      moanScore: _sustainedMoan,
      zeroCrossRate: zeroCrossRate,
      alert: alert,
      reason: cryAlert ? 'Ağlama benzeri yüksek frekanslı ses' : 'İnleme benzeri düşük frekanslı sürekli ses',
    );
  }

  AudioAnalysisResult _empty() => AudioAnalysisResult(
        rms: 0,
        dbfs: -120,
        ambientRms: _ambientRms,
        cryScore: _sustainedCry,
        moanScore: _sustainedMoan,
        zeroCrossRate: 0,
        alert: false,
        reason: 'Ses yok',
      );

  List<double> _decodePcm16Le(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final count = bytes.length ~/ 2;
    return List<double>.generate(count, (i) => data.getInt16(i * 2, Endian.little) / 32768.0, growable: false);
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

  double _bandEnergy(List<double> samples, double lowHz, double highHz) {
    const probesPerBand = 5;
    var energy = 0.0;
    for (var i = 0; i < probesPerBand; i++) {
      final t = probesPerBand == 1 ? 0.5 : i / (probesPerBand - 1);
      final frequency = lowHz + (highHz - lowHz) * t;
      energy += _goertzelPower(samples, frequency);
    }
    final bandwidthWeight = (highHz - lowHz) / sampleRate;
    return max(0, energy * bandwidthWeight / (samples.length * probesPerBand));
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

  double _leakyIntegrator(double previous, double current, {required double attack, required double release}) {
    final factor = current > previous ? attack : release;
    return previous * (1 - factor) + current * factor;
  }
}
