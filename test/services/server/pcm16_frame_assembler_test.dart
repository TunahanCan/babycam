import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/server/pcm16_frame_assembler.dart';

void main() {
  test('odd transport boundary preserves the split PCM16 sample', () {
    final assembler = Pcm16FrameAssembler(frameBytes: 4);

    expect(assembler.add([1, 2, 3]), isEmpty);
    final frames = assembler.add([4, 5, 6, 7, 8]);

    expect(frames, hasLength(2));
    expect(frames[0], [1, 2, 3, 4]);
    expect(frames[1], [5, 6, 7, 8]);
    expect(assembler.pendingBytes, 0);
  });

  test('aligned tail flushes while incomplete final sample remains visible',
      () {
    final assembler = Pcm16FrameAssembler(frameBytes: 8);
    assembler.add([1, 2, 3, 4, 5]);

    expect(assembler.flushAlignedTail(), [1, 2, 3, 4]);
    expect(assembler.hasPartialSample, isTrue);
    expect(assembler.pendingBytes, 1);
  });
}
