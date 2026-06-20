import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/analysis/audio/goertzel_band_analyzer.dart';
import 'package:mimicam/analysis/audio/pcm16le_reader.dart';
import 'test_audio_generators.dart';

void main() {
  test('1000 Hz sine peaks at 1000 Hz band', () {
    final bytes = generateSinePcm16le(
        sampleRate: 16000, frequencyHz: 1000, durationMs: 1000, amplitude: 0.8);
    final samples = Pcm16LeReader.readMonoSamples(bytes)
        .map(Pcm16LeReader.sampleToDouble)
        .toList();
    final result = GoertzelBandAnalyzer(
        sampleRate: 16000,
        centerFrequencies: [400, 1000, 3000]).analyzeNormalizedSamples(samples);
    expect(result[1000], greaterThan(result[400]! * 20));
    expect(result[1000], greaterThan(result[3000]! * 20));
  });
  test('silence and empty are safe', () {
    final analyzer =
        GoertzelBandAnalyzer(sampleRate: 16000, centerFrequencies: [400, 1000]);
    expect(
        analyzer
            .analyzeNormalizedSamples(List.filled(100, 0))
            .values
            .every((e) => e < 1e-12),
        isTrue);
    expect(analyzer.analyzeNormalizedSamples([]).values, everyElement(0));
  });
}
