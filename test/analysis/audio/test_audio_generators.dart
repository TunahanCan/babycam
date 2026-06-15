import 'dart:math';
import 'dart:typed_data';

Uint8List generateSinePcm16le({required int sampleRate, required double frequencyHz, required int durationMs, required double amplitude, int channels = 1}) {
  return _generate(sampleRate, durationMs, channels, (i) => sin(2 * pi * frequencyHz * i / sampleRate) * amplitude);
}

Uint8List generateNoisePcm16le({required int sampleRate, required int durationMs, required double amplitude, int channels = 1, int seed = 1}) {
  final random = Random(seed);
  return _generate(sampleRate, durationMs, channels, (_) => (random.nextDouble() * 2 - 1) * amplitude);
}

Uint8List generateCryLikePcm16le({required int sampleRate, required int durationMs, double amplitude = 0.55, int channels = 1}) {
  return _generate(sampleRate, durationMs, channels, (i) {
    final t = i / sampleRate;
    final mod = 0.55 + 0.45 * ((sin(2 * pi * 4 * t) + 1) / 2);
    final mixed = 0.45 * sin(2 * pi * 600 * t) + 0.35 * sin(2 * pi * 900 * t) + 0.20 * sin(2 * pi * 1300 * t);
    return mixed * mod * amplitude;
  });
}

Uint8List _generate(int sampleRate, int durationMs, int channels, double Function(int) valueAt) {
  final frames = sampleRate * durationMs ~/ 1000;
  final data = ByteData(frames * channels * 2);
  for (var i = 0; i < frames; i++) {
    final sample = (valueAt(i).clamp(-1.0, 1.0) * 32767).round();
    for (var ch = 0; ch < channels; ch++) {
      data.setInt16((i * channels + ch) * 2, sample, Endian.little);
    }
  }
  return data.buffer.asUint8List();
}
