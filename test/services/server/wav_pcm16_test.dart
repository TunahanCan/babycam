import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/server/wav_pcm16.dart';

void main() {
  test('header PCM16 WAV alanlarini dogru yazar', () {
    final header = WavPcm16.header(
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
      dataSize: 3200,
    );

    expect(String.fromCharCodes(header.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(header.sublist(8, 12)), 'WAVE');
    expect(ByteData.sublistView(header, 24, 28).getUint32(0, Endian.little),
        16000);
    expect(
        ByteData.sublistView(header, 34, 36).getUint16(0, Endian.little), 16);
    expect(
        ByteData.sublistView(header, 40, 44).getUint32(0, Endian.little), 3200);
  });

  test('sineTone fade uygulanan PCM16 test tonu uretir', () {
    final pcm = WavPcm16.sineTone(
      sampleRate: 16000,
      durationMs: 200,
      frequencyHz: 1000,
      amplitude: 0.25,
    );

    expect(pcm.length, 16000 * 200 ~/ 1000 * 2);
    expect(_pcmPeak(pcm), greaterThan(1000));
    expect(_pcmPeak(pcm), lessThanOrEqualTo((32767 * 0.25).ceil()));
  });
}

int _pcmPeak(Uint8List pcm16le) {
  final view = ByteData.sublistView(pcm16le);
  var peak = 0;
  for (var i = 0; i < pcm16le.length ~/ 2; i++) {
    final sample = view.getInt16(i * 2, Endian.little).abs();
    if (sample > peak) peak = sample;
  }
  return peak;
}
