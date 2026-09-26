import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/server/wav_pcm16.dart';

void main() {
  test('custom integer PCM format keeps WAV byte rate and block alignment', () {
    final header = WavPcm16.header(
      sampleRate: 48000,
      channels: 2,
      bitsPerSample: 24,
      dataSize: 600,
    );
    final data = ByteData.sublistView(header);

    expect(data.getUint32(28, Endian.little), 288000);
    expect(data.getUint16(32, Endian.little), 6);
    expect(data.getUint16(34, Endian.little), 24);
  });

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
}
