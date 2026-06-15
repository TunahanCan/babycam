import 'dart:typed_data';

/// PCM16 little-endian audio chunk with timing metadata.
class AudioChunk {
  final Uint8List pcm16le;
  final int sampleRate;
  final int channels;
  final int timestampMs;

  const AudioChunk({
    required this.pcm16le,
    required this.sampleRate,
    required this.channels,
    required this.timestampMs,
  });
}
