import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/analysis/audio/audio_chunk.dart';
import 'package:miucam/analysis/audio/cry_audio_analyzer_v2.dart';
import 'package:miucam/analysis/video/luma_frame.dart';
import 'package:miucam/analysis/video/motion_analyzer_v2.dart';

void main() {
  test('30 FPS 640x480 input performs only the configured 3 full analyses', () {
    final analyzer = MotionAnalyzerV2();
    final yPlane = Uint8List(640 * 480);
    for (var index = 0; index < yPlane.length; index++) {
      yPlane[index] = 80 + index % 32;
    }

    var analyzed = 0;
    var skipped = 0;
    for (var frameIndex = 0; frameIndex <= 30; frameIndex++) {
      final timestampMs = (frameIndex * 1000 / 30).round();
      final result = analyzer.analyze(
        LumaFrame(
          yPlane: yPlane,
          width: 640,
          height: 480,
          rowStride: 640,
          pixelStride: 1,
          timestampMs: timestampMs,
          monotonicTimestampMs: timestampMs,
        ),
      );
      expect(result.invalidFrame, isFalse);
      if (result.skippedByFrameRateGate) {
        skipped++;
      } else {
        analyzed++;
      }
    }

    expect(analyzed, 3);
    expect(skipped, 28);
    expect(analyzer.diagnostics()['analyzedFrames'], 3);
  });

  test('16 kHz audio stays within four feature passes per second', () {
    final analyzer = CryAudioAnalyzerV2()..restoreCalibratedAmbient(-45);
    final pcm = _generateModulatedPcm16le(durationMs: 20);
    var firstTenSecondWindows = 0;
    var steadyTenSecondWindows = 0;
    for (var chunkIndex = 1; chunkIndex <= 1000; chunkIndex++) {
      final results = analyzer.addChunk(
        AudioChunk(
          pcm16le: pcm,
          sampleRate: 16000,
          channels: 1,
          timestampMs: chunkIndex * 20,
        ),
      );
      expect(results.every((result) => !result.invalidChunk), isTrue);
      if (chunkIndex <= 500) {
        firstTenSecondWindows += results.length;
      } else {
        steadyTenSecondWindows += results.length;
      }
    }

    // The first one-second window delays startup. Twenty-millisecond capture
    // chunks do not divide the 250 ms hop exactly, so allow the safe 12/13
    // chunk scheduling variants while preventing per-chunk feature work.
    expect(firstTenSecondWindows, inInclusiveRange(35, 37));
    expect(steadyTenSecondWindows, inInclusiveRange(38, 40));
    expect(
      analyzer.diagnostics().values.whereType<Iterable<Object?>>(),
      isEmpty,
    );
  });
}

Uint8List _generateModulatedPcm16le({required int durationMs}) {
  const sampleRate = 16000;
  final sampleCount = sampleRate * durationMs ~/ 1000;
  final bytes = ByteData(sampleCount * 2);
  for (var index = 0; index < sampleCount; index++) {
    final time = index / sampleRate;
    final envelope = .65 + .25 * sin(2 * pi * 4 * time);
    final sample = (sin(2 * pi * 800 * time) * envelope * 12000).round();
    bytes.setInt16(index * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
