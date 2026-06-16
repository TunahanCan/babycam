import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/audio_analyzer.dart';

void main() {
  test('high mid-band sustained tone increases cry score', () {
    final analyzer = AudioAnalyzer(sampleRate: 16000);
    final chunk = _sinePcm16(frequency: 470, amplitude: 0.45, sampleRate: 16000);

    late AudioAnalysisResult result;
    for (var i = 0; i < 12; i++) {
      result = analyzer.analyzePcm16(chunk);
    }

    expect(result.cryScore, greaterThan(0.55));
    expect(result.fundamentalHz, closeTo(470, 18));
    expect(result.summary, contains('F0'));
  });

  test('low sustained tone increases moan score', () {
    final analyzer = AudioAnalyzer(sampleRate: 16000);
    final chunk = _sinePcm16(frequency: 260, amplitude: 0.40, sampleRate: 16000);

    var score = 0.0;
    for (var i = 0; i < 12; i++) {
      score = analyzer.analyzePcm16(chunk).moanScore;
    }

    expect(score, greaterThan(0.55));
  });

  test('broadband noisy audio has no confident infant pitch', () {
    final analyzer = AudioAnalyzer(sampleRate: 16000);
    final chunk = _noisePcm16(amplitude: 0.20, sampleRate: 16000);

    final result = analyzer.analyzePcm16(chunk);

    expect(result.spectralEntropy, greaterThan(0.40));
    expect(result.fundamentalHz, equals(0));
    expect(result.voiceActivityScore, lessThan(0.55));
  });
}

Uint8List _sinePcm16({required double frequency, required double amplitude, required int sampleRate}) {
  final sampleCount = sampleRate ~/ 4;
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final sample = (sin(2 * pi * frequency * i / sampleRate) * amplitude * 32767).round();
    bytes.setInt16(i * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Uint8List _noisePcm16({required double amplitude, required int sampleRate}) {
  final random = Random(7);
  final sampleCount = sampleRate ~/ 4;
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final sample = ((random.nextDouble() * 2 - 1) * amplitude * 32767).round();
    bytes.setInt16(i * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
