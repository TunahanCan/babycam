import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/analysis/audio/pcm16le_reader.dart';

void main() {
  test('reads zero sample', () {
    final b = ByteData(2)..setInt16(0, 0, Endian.little);
    expect(Pcm16LeReader.readMonoSamples(b.buffer.asUint8List()).single, 0);
  });
  test('reads signed extremes', () {
    final b = ByteData(4)
      ..setInt16(0, 32767, Endian.little)
      ..setInt16(2, -32768, Endian.little);
    expect(
        Pcm16LeReader.readMonoSamples(b.buffer.asUint8List()), [32767, -32768]);
  });
  test('odd length ignores trailing byte', () {
    expect(Pcm16LeReader.readMonoSamples(Uint8List.fromList([1, 0, 99])), [1]);
  });
  test('stereo averages to mono', () {
    final b = ByteData(4)
      ..setInt16(0, 1000, Endian.little)
      ..setInt16(2, -500, Endian.little);
    expect(
        Pcm16LeReader.readMonoSamples(b.buffer.asUint8List(), channels: 2)
            .single,
        250);
  });
  test('empty buffer is safe', () {
    expect(Pcm16LeReader.readMonoSamples(Uint8List(0)), isEmpty);
  });
}
