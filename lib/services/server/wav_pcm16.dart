import 'dart:typed_data';

import '../../core/media/pcm_audio_format.dart';

class WavPcm16 {
  const WavPcm16._();

  static Uint8List header({
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
    int dataSize = 0x7fffffff,
  }) {
    final format = PcmAudioFormat(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    );
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
    data.setUint32(28, format.bytesPerSecond, Endian.little);
    data.setUint16(32, format.bytesPerSampleFrame, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    return data.buffer.asUint8List();
  }
}
