import 'dart:math';

/// Pure-Dart Goertzel analyzer for a small set of center frequencies.
class GoertzelBandAnalyzer {
  GoertzelBandAnalyzer({
    required this.sampleRate,
    required List<double> centerFrequencies,
  }) : centerFrequencies = List.unmodifiable(centerFrequencies);

  final int sampleRate;
  final List<double> centerFrequencies;

  Map<double, double> analyzeNormalizedSamples(List<double> samples) {
    final result = <double, double>{};
    if (samples.isEmpty) {
      for (final f in centerFrequencies) {
        result[f] = 0;
      }
      return result;
    }
    final n = samples.length;
    for (final frequency in centerFrequencies) {
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
      final power = q1 * q1 + q2 * q2 - coeff * q1 * q2;
      result[frequency] = max(0, power / (n * n));
    }
    return result;
  }
}
