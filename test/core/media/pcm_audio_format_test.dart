import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/pcm_audio_format.dart';

void main() {
  test('fractional duration budgets retain complete stereo sample frames', () {
    const format = PcmAudioFormat(
      sampleRate: 44100,
      channels: 2,
      bitsPerSample: 16,
    );

    final budget = format.bytesForDuration(const Duration(microseconds: 1010));
    expect(budget, 178);
    expect(format.alignBytes(budget), 176);
    expect(format.durationForBytes(176), const Duration(microseconds: 997));
    expect(format.alignBytes(3), 0);
  });
}
