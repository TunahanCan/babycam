import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/client/media/wav_pcm_stream_parser.dart';

void main() {
  test('WAV header parcalansa bile PCM payload ve format okunur', () {
    final parser = WavPcmStreamParser();
    final wav = _wavBytes(
      sampleRate: 16000,
      channels: 1,
      pcm: Uint8List.fromList([1, 0, 2, 0, 3, 0, 4, 0]),
    );

    final first = parser.add(Uint8List.sublistView(wav, 0, 20));
    final second = parser.add(Uint8List.sublistView(wav, 20));

    expect(first.isConfigured, isFalse);
    expect(first.pcm16le, isEmpty);
    expect(second.isConfigured, isTrue);
    expect(second.sampleRate, 16000);
    expect(second.channels, 1);
    expect(second.pcm16le, [1, 0, 2, 0, 3, 0, 4, 0]);
  });

  test('PCM chunklari frame boyuna hizalanir', () {
    final parser = WavPcmStreamParser();
    final wav = _wavBytes(
      sampleRate: 16000,
      channels: 1,
      pcm: Uint8List.fromList([10]),
    );

    final first = parser.add(wav);
    final second = parser.add(Uint8List.fromList([0, 11]));
    final third = parser.add(Uint8List.fromList([0]));

    expect(first.isConfigured, isTrue);
    expect(first.pcm16le, isEmpty);
    expect(second.pcm16le, [10, 0]);
    expect(third.pcm16le, [11, 0]);
  });
}

Uint8List _wavBytes({
  required int sampleRate,
  required int channels,
  required Uint8List pcm,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final bytes = BytesBuilder(copy: false);
  final header = ByteData(44);
  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  bytes
    ..add(header.buffer.asUint8List())
    ..add(pcm);
  return bytes.toBytes();
}
