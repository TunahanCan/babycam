import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/analysis/audio/audio_ring_buffer.dart';

void main() {
  test('reused window matches independent history across multiple wraps', () {
    final ring = AudioRingBuffer(sampleRate: 17, windowMs: 1000, hopMs: 250);
    final random = Random(42);
    final history = <int>[];
    final output = Int16List(ring.windowSamples);
    for (var step = 0; step < 80; step++) {
      final input = Int16List.fromList(List.generate(
          random.nextInt(80), (_) => random.nextInt(65536) - 32768));
      ring.addSamples(input, timestampMs: step);
      history.addAll(input);
      if (history.length >= ring.windowSamples) {
        expect(ring.copyLatestWindow(output), isTrue);
        expect(output, history.sublist(history.length - ring.windowSamples));
        final retained = ring.readLatestWindow();
        output.fillRange(0, output.length, 0);
        expect(retained, history.sublist(history.length - ring.windowSamples));
      }
    }
    ring.reset();
    output.fillRange(0, output.length, 7);
    expect(ring.copyLatestWindow(output), isFalse);
    expect(output, everyElement(7));
    ring.addSamples(Int16List(17), timestampMs: 81);
    expect(ring.copyLatestWindow(output), isTrue);
    expect(output, everyElement(0));
  });

  test('invalid zero-sample timing fails instead of stalling the analysis loop',
      () {
    for (final config in [
      (rate: 0, window: 1000, hop: 250),
      (rate: 16000, window: 0, hop: 250),
      (rate: 16000, window: 1000, hop: 0),
      (rate: 1, window: 1000, hop: 250),
    ]) {
      expect(
          () => AudioRingBuffer(
              sampleRate: config.rate,
              windowMs: config.window,
              hopMs: config.hop),
          throwsArgumentError);
    }
    final ring = AudioRingBuffer(sampleRate: 10, windowMs: 1000, hopMs: 500);
    expect(() => ring.copyLatestWindow(Int16List(9)), throwsArgumentError);
  });

  test('window fill and latest window with overwrite', () {
    final rb = AudioRingBuffer(sampleRate: 10, windowMs: 1000, hopMs: 500);
    rb.addSamples(Int16List.fromList([1, 2, 3]), timestampMs: 0);
    expect(rb.hasEnoughForWindow, isFalse);
    rb.addSamples(Int16List.fromList([4, 5, 6, 7, 8, 9, 10]),
        timestampMs: 1000);
    expect(rb.hasEnoughForWindow, isTrue);
    expect(rb.readLatestWindow(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    rb.addSamples(Int16List.fromList([11, 12, 13, 14, 15]), timestampMs: 1500);
    expect(rb.readLatestWindow(), [6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
  });
  test('hop timing shouldAnalyze', () {
    final rb = AudioRingBuffer(sampleRate: 10, windowMs: 1000, hopMs: 500);
    rb.addSamples(Int16List.fromList(List.filled(10, 1)), timestampMs: 1000);
    expect(rb.shouldAnalyze(1000), isTrue);
    expect(rb.shouldAnalyze(1100), isFalse);
    rb.addSamples(Int16List.fromList(List.filled(5, 1)), timestampMs: 1500);
    expect(rb.shouldAnalyze(1500), isTrue);
  });
}
