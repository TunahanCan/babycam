import 'dart:math';
import 'dart:typed_data';

class WavPcm16 {
  const WavPcm16._();

  static Uint8List header({
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
    int dataSize = 0x7fffffff,
  }) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final data = ByteData(44);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    return data.buffer.asUint8List();
  }

  static Uint8List sineTone({
    required int sampleRate,
    required int durationMs,
    required int frequencyHz,
    required double amplitude,
  }) {
    final sampleCount = (sampleRate * durationMs / 1000).round();
    final output = Uint8List(sampleCount * 2);
    final view = ByteData.sublistView(output);
    final amplitudeInt = (32767 * amplitude).round();
    final fadeSamples = min(sampleCount ~/ 2, (sampleRate * .008).round());

    for (var i = 0; i < sampleCount; i++) {
      final fade = fadeSamples <= 0
          ? 1.0
          : min(1.0, min(i + 1, sampleCount - i) / fadeSamples);
      final sample =
          (sin(2 * pi * frequencyHz * i / sampleRate) * amplitudeInt * fade)
              .round();
      view.setInt16(i * 2, sample, Endian.little);
    }
    return output;
  }
}
