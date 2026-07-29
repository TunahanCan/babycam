import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/client/media/wav_pcm_stream_parser.dart';

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

  test('streaming WAV data chunk buyuk olsa bile PCM hemen akar', () {
    final parser = WavPcmStreamParser();
    final wav = _wavBytes(
      sampleRate: 16000,
      channels: 1,
      dataSize: 0x7fffffff,
      pcm: Uint8List.fromList([1, 0, 2, 0]),
    );

    final parsed = parser.add(wav);

    expect(parsed.isConfigured, isTrue);
    expect(parsed.sampleRate, 16000);
    expect(parsed.channels, 1);
    expect(parsed.pcm16le, [1, 0, 2, 0]);
  });

  test('tek byte parcalar bounded header buffer ile parse edilir', () {
    final parser = WavPcmStreamParser();
    final wav = _wavBytes(
      sampleRate: 16000,
      channels: 1,
      pcm: Uint8List.fromList([1, 0, 2, 0]),
    );
    final output = <int>[];

    for (final byte in wav) {
      output.addAll(parser.add(Uint8List.fromList([byte])).pcm16le);
    }

    expect(output, [1, 0, 2, 0]);
    expect(parser.peakHeaderBytes, 44);
  });

  test('olcusuz WAV header bellek limitinde reddedilir', () {
    final parser = WavPcmStreamParser(maxHeaderBytes: 64);
    final header = ByteData(20);
    _writeAscii(header, 0, 'RIFF');
    _writeAscii(header, 8, 'WAVE');
    _writeAscii(header, 12, 'JUNK');
    header.setUint32(16, 1024, Endian.little);

    expect(
      () => parser.add(
        Uint8List.fromList([
          ...header.buffer.asUint8List(),
          ...List<int>.filled(64, 0),
        ]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(parser.peakHeaderBytes, 64);
  });

  test('desteklenmeyen sample rate ve channel degerleri reddedilir', () {
    final invalidRate = _wavBytes(
      sampleRate: 192000,
      channels: 1,
      pcm: Uint8List(0),
    );
    final invalidChannels = _wavBytes(
      sampleRate: 16000,
      channels: 8,
      pcm: Uint8List(0),
    );

    expect(
      () => WavPcmStreamParser().add(invalidRate),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => WavPcmStreamParser().add(invalidChannels),
      throwsA(isA<FormatException>()),
    );
  });
}

void _writeAscii(ByteData data, int offset, String value) {
  for (var i = 0; i < value.length; i++) {
    data.setUint8(offset + i, value.codeUnitAt(i));
  }
}

Uint8List _wavBytes({
  required int sampleRate,
  required int channels,
  required Uint8List pcm,
  int? dataSize,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final bytes = BytesBuilder(copy: false);
  final header = ByteData(44);
  _writeAscii(header, 0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  _writeAscii(header, 8, 'WAVE');
  _writeAscii(header, 12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  _writeAscii(header, 36, 'data');
  header.setUint32(40, dataSize ?? pcm.length, Endian.little);
  bytes
    ..add(header.buffer.asUint8List())
    ..add(pcm);
  return bytes.toBytes();
}
