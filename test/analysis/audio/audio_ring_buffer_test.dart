import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/analysis/audio/audio_ring_buffer.dart';

void main() {
  test('window fill and latest window with overwrite', () {
    final rb = AudioRingBuffer(sampleRate: 10, windowMs: 1000, hopMs: 500);
    rb.addSamples(Int16List.fromList([1, 2, 3]), timestampMs: 0);
    expect(rb.hasEnoughForWindow, isFalse);
    rb.addSamples(Int16List.fromList([4, 5, 6, 7, 8, 9, 10]), timestampMs: 1000);
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
