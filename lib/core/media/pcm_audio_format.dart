/// The byte layout of interleaved, integer PCM audio.
///
/// A sample frame contains one sample for every channel; transport packets may
/// contain many sample frames. Timing and buffering policy remain with callers.
class PcmAudioFormat {
  static const pcm16BitsPerSample = 16;

  const PcmAudioFormat({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  })  : assert(sampleRate > 0),
        assert(channels > 0),
        assert(bitsPerSample > 0 && bitsPerSample % 8 == 0);

  const PcmAudioFormat.pcm16({
    required int sampleRate,
    required int channels,
  }) : this(
          sampleRate: sampleRate,
          channels: channels,
          bitsPerSample: pcm16BitsPerSample,
        );

  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  int get bytesPerSample => bitsPerSample ~/ 8;
  int get bytesPerSampleFrame => channels * bytesPerSample;
  int get bytesPerSecond => sampleRate * bytesPerSampleFrame;

  /// Rounds a byte count down to complete interleaved sample frames.
  int alignBytes(int byteCount) => byteCount - byteCount % bytesPerSampleFrame;

  /// Truncates fractional bytes; use [alignBytes] before consuming PCM frames.
  int bytesForDuration(Duration duration) =>
      bytesPerSecond *
      duration.inMicroseconds ~/
      Duration.microsecondsPerSecond;

  Duration durationForBytes(int byteCount) => Duration(
        microseconds:
            byteCount * Duration.microsecondsPerSecond ~/ bytesPerSecond,
      );
}

/// Shared wire/capture defaults for the live PCM audio path.
///
/// Comfort synthesis intervals, jitter targets and queue limits have different
/// purposes and intentionally do not inherit [frameDuration].
abstract final class LiveAudioDefaults {
  static const sampleRate = 16000;
  static const channels = 1;
  static const bitsPerSample = PcmAudioFormat.pcm16BitsPerSample;
  static const frameDuration = Duration(milliseconds: 20);
  static const format = PcmAudioFormat(
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bitsPerSample,
  );
}
