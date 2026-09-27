import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/server/pcm16_frame_assembler.dart';

void main() {
  test('large arbitrarily split input retains exact PCM and bounded carry', () {
    final random = Random(73);
    final input =
        List<int>.generate(256 * 1024 + 1, (_) => random.nextInt(256));
    final assembler = Pcm16FrameAssembler(frameBytes: 640);
    final output = <int>[];
    var offset = 0;
    while (offset < input.length) {
      final end = min(input.length, offset + random.nextInt(65536) + 1);
      final frames = assembler.add(input.sublist(offset, end));
      for (final frame in frames) {
        expect(frame.length, 640);
        output.addAll(frame);
      }
      expect(assembler.pendingBytes, lessThan(640));
      offset = end;
    }
    output.addAll(assembler.flushAlignedTail() ?? []);
    expect(output, input.sublist(0, input.length - 1));
    expect(assembler.pendingBytes, 1);
    assembler.add([17]);
    expect(assembler.flushAlignedTail(), [input.last, 17]);
  });

  test('emitted frames own their bytes across input reuse and clear', () {
    final assembler = Pcm16FrameAssembler(frameBytes: 4);
    assembler.add([1]);
    final input = Uint8List.fromList([2, 3, 4, 5, 6, 7, 8, 9]);
    final frames = assembler.add(input);
    input.fillRange(0, input.length, 0);
    assembler.clear();
    assembler.add([10, 11, 12, 13]);
    expect(frames, [
      [1, 2, 3, 4],
      [5, 6, 7, 8]
    ]);
    expect(assembler.pendingBytes, 0);
    expect(assembler.flushAlignedTail(), isNull);
  });

  test('invalid frame sizes fail before processing any audio', () {
    for (final size in [0, -2, 3]) {
      expect(() => Pcm16FrameAssembler(frameBytes: size), throwsArgumentError);
    }
  });

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
