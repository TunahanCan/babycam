import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:babycam/services/audio_analyzer.dart';

void main() {
  test('high mid-band sustained tone increases cry score', () {
    final analyzer = AudioAnalyzer(sampleRate: 16000);
    final chunk = _sinePcm16(frequency: 900, amplitude: 0.45, sampleRate: 16000);

    var score = 0.0;
    for (var i = 0; i < 12; i++) {
      score = analyzer.analyzePcm16(chunk).cryScore;
    }

    expect(score, greaterThan(0.55));
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
