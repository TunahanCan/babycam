import 'dart:typed_data';

/// Safe PCM16 little-endian decoder with optional mono downmixing.
class Pcm16LeReader {
  static Int16List readMonoSamples(Uint8List bytes, {int channels = 1}) {
    final safeChannels = channels <= 0 ? 1 : channels;
    final frameCount = (bytes.length ~/ 2) ~/ safeChannels;
    final out = Int16List(frameCount);
    if (frameCount == 0) return out;
    final data = ByteData.sublistView(bytes);
    for (var frame = 0; frame < frameCount; frame++) {
      var sum = 0;
      final base = frame * safeChannels * 2;
      for (var ch = 0; ch < safeChannels; ch++) {
        sum += data.getInt16(base + ch * 2, Endian.little);
      }
      out[frame] = (sum / safeChannels).round().clamp(-32768, 32767).toInt();
    }
    return out;
  }

  static double sampleToDouble(int sample) => (sample / 32768.0).clamp(-1.0, 1.0).toDouble();
}
