// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:miucam/analysis/audio/audio_chunk.dart';
import 'package:miucam/analysis/audio/cry_audio_analyzer_v2.dart';
import 'package:miucam/analysis/video/luma_frame.dart';
import 'package:miucam/analysis/video/motion_analysis_config.dart';
import 'package:miucam/analysis/video/motion_analyzer_v2.dart';
import 'package:miucam/features/client/media/mjpeg_stream_parser.dart';

void main() {
  final results = <String, Object?>{
    'audioAnalysis': _benchmarkAudioAnalysis(),
    'motionAnalysis': _benchmarkMotionAnalysis(),
    'mjpegParser': _benchmarkMjpegParser(),
  };
  print(const JsonEncoder.withIndent('  ').convert(results));
}

Map<String, Object?> _benchmarkAudioAnalysis() {
  const iterations = 1000;
  const frameDurationMs = 20;
  final analyzer = CryAudioAnalyzerV2();
  final pcm = _sinePcm16(
    sampleRate: 16000,
    durationMs: frameDurationMs,
    frequencyHz: 700,
  );
  var resultsProduced = 0;
  for (var index = 0; index < 100; index++) {
    analyzer.addChunk(AudioChunk(
      pcm16le: pcm,
      sampleRate: 16000,
      channels: 1,
      timestampMs: index * frameDurationMs,
    ));
  }
  analyzer.reset();

  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    resultsProduced += analyzer
        .addChunk(AudioChunk(
          pcm16le: pcm,
          sampleRate: 16000,
          channels: 1,
          timestampMs: index * frameDurationMs,
        ))
        .length;
  }
  stopwatch.stop();
  return _timingResult(
    iterations: iterations,
    elapsed: stopwatch.elapsed,
    extra: {'analysisWindows': resultsProduced},
  );
}

Map<String, Object?> _benchmarkMotionAnalysis() {
  const iterations = 1000;
  const width = 640;
  const height = 480;
  final analyzer = MotionAnalyzerV2(
    config: const MotionAnalysisConfig(analysisFps: 1000),
  );
  final luma = Uint8List(width * height);
  for (var index = 0; index < luma.length; index++) {
    luma[index] = 80 + index % 40;
  }
  for (var index = 0; index < 50; index++) {
    analyzer.analyze(LumaFrame(
      yPlane: luma,
      width: width,
      height: height,
      rowStride: width,
      pixelStride: 1,
      timestampMs: index,
    ));
  }
  analyzer.reset();

  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    analyzer.analyze(LumaFrame(
      yPlane: luma,
      width: width,
      height: height,
      rowStride: width,
      pixelStride: 1,
      timestampMs: index,
    ));
  }
  stopwatch.stop();
  return _timingResult(iterations: iterations, elapsed: stopwatch.elapsed);
}

Map<String, Object?> _benchmarkMjpegParser() {
  const iterations = 30;
  const payloadBytes = 128 * 1024;
  const fragmentBytes = 257;
  final parser = MjpegStreamParser();
  final jpeg = Uint8List(payloadBytes);
  for (var index = 0; index < jpeg.length; index++) {
    jpeg[index] = index & 0xff;
  }
  var parsedFrames = 0;
  final stopwatch = Stopwatch()..start();
  for (var sequence = 1; sequence <= iterations; sequence++) {
    final header = latin1.encode(
      '--frame\r\nContent-Type: image/jpeg\r\n'
      'Content-Length: ${jpeg.length}\r\n'
      'X-MiuCam-Sequence: $sequence\r\n\r\n',
    );
    final part = Uint8List(header.length + jpeg.length + 2)
      ..setRange(0, header.length, header)
      ..setRange(header.length, header.length + jpeg.length, jpeg)
      ..setRange(header.length + jpeg.length, header.length + jpeg.length + 2,
          const [13, 10]);
    for (var offset = 0; offset < part.length; offset += fragmentBytes) {
      final end = min(offset + fragmentBytes, part.length);
      parsedFrames +=
          parser.addFrames(Uint8List.sublistView(part, offset, end)).length;
    }
  }
  stopwatch.stop();
  return _timingResult(
    iterations: iterations,
    elapsed: stopwatch.elapsed,
    extra: {
      'parsedFrames': parsedFrames,
      'payloadBytesPerFrame': payloadBytes,
      'fragmentBytes': fragmentBytes,
    },
  );
}

Map<String, Object?> _timingResult({
  required int iterations,
  required Duration elapsed,
  Map<String, Object?> extra = const {},
}) {
  final elapsedMicros = max(1, elapsed.inMicroseconds);
  return {
    'iterations': iterations,
    'elapsedMs': elapsedMicros / 1000,
    'averageMicros': elapsedMicros / iterations,
    'operationsPerSecond': iterations * 1000000 / elapsedMicros,
    ...extra,
  };
}

Uint8List _sinePcm16({
  required int sampleRate,
  required int durationMs,
  required int frequencyHz,
}) {
  final sampleCount = sampleRate * durationMs ~/ 1000;
  final bytes = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < sampleCount; index++) {
    final sample = (sin(2 * pi * frequencyHz * index / sampleRate) * 12000)
        .round()
        .clamp(-32768, 32767);
    data.setInt16(index * 2, sample, Endian.little);
  }
  return bytes;
}
