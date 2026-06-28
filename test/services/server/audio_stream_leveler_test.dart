import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/server/audio_stream_leveler.dart';

void main() {
  test('dusuk RMS PCM sesini peak limitini asmadan yukseltir', () {
    final leveler = AudioStreamLeveler(
      targetRms: 3000,
      maxGain: 10,
      maxPeak: 30000,
      attack: 1,
      release: 1,
    );
    final input = _pcm16le(List<int>.filled(1600, 200));

    final output = leveler.processPcm16le(input);
    final inputRms = _rms(input);
    final outputRms = _rms(output);

    expect(outputRms, greaterThan(inputRms * 5));
    expect(_peak(output), lessThanOrEqualTo(30000));
    expect(leveler.lastSnapshot.gain, greaterThan(5));
  });

  test('guclu transient varsa gain peak guvenligine gore sinirlanir', () {
    final leveler = AudioStreamLeveler(
      targetRms: 24000,
      maxGain: 12,
      maxPeak: 12000,
      attack: 1,
      release: 1,
    );
    final input = _pcm16le(List<int>.filled(1600, 10000));

    final output = leveler.processPcm16le(input);

    expect(_peak(output), lessThanOrEqualTo(12000));
    expect(leveler.lastSnapshot.gain, closeTo(1.2, .01));
  });

  test('sessizden yuksek peak e geciste smoothing clip uretmez', () {
    final leveler = AudioStreamLeveler(
      targetRms: 3600,
      maxGain: 12,
      maxPeak: 12000,
      attack: 1,
      release: .05,
    );

    leveler.processPcm16le(_pcm16le(List<int>.filled(1600, 400)));
    final output =
        leveler.processPcm16le(_pcm16le(List<int>.filled(1600, 3000)));

    expect(_peak(output), lessThanOrEqualTo(12000));
    expect(leveler.lastSnapshot.gain, lessThanOrEqualTo(4));
  });
}

Uint8List _pcm16le(List<int> samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

double _rms(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final sampleCount = bytes.length ~/ 2;
  var sumSquares = 0;
  for (var i = 0; i < sampleCount; i++) {
    final sample = view.getInt16(i * 2, Endian.little);
    sumSquares += sample * sample;
  }
  return sqrt(sumSquares / sampleCount);
}

int _peak(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  var peak = 0;
  for (var i = 0; i < bytes.length ~/ 2; i++) {
    peak = max(peak, view.getInt16(i * 2, Endian.little).abs());
  }
  return peak;
}
