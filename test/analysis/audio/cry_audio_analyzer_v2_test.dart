import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/analysis/audio/audio_analysis_config.dart';
import 'package:mimicam/analysis/audio/audio_calibration_state.dart';
import 'package:mimicam/analysis/audio/audio_chunk.dart';
import 'package:mimicam/analysis/audio/cry_audio_analyzer_v2.dart';
import 'test_audio_generators.dart';

void main() {
  const sr = 16000;
  test('silence and low ambient noise stay low', () {
    final analyzer = CryAudioAnalyzerV2(
        config: const AudioAnalysisConfig(calibrationMs: 1000));
    final silence = generateSinePcm16le(
        sampleRate: sr, frequencyHz: 440, durationMs: 1000, amplitude: 0);
    final r1 = analyzer
        .addChunk(AudioChunk(
            pcm16le: silence, sampleRate: sr, channels: 1, timestampMs: 1000))
        .last;
    expect(r1.cryScore, lessThan(0.25));
    expect(r1.isCryLikely, isFalse);
    final noise =
        generateNoisePcm16le(sampleRate: sr, durationMs: 1000, amplitude: 0.01);
    final r2 = analyzer
        .addChunk(AudioChunk(
            pcm16le: noise, sampleRate: sr, channels: 1, timestampMs: 2000))
        .last;
    expect(r2.cryScore, lessThan(0.45));
  });

  test('calibration sets ambient dbfs', () {
    final analyzer = CryAudioAnalyzerV2(
        config: const AudioAnalysisConfig(calibrationMs: 1000));
    analyzer.startCalibration(timestampMs: 0);
    final noise =
        generateNoisePcm16le(sampleRate: sr, durationMs: 1000, amplitude: 0.02);
    final result = analyzer
        .addChunk(AudioChunk(
            pcm16le: noise, sampleRate: sr, channels: 1, timestampMs: 1000))
        .last;
    expect(result.calibrationState, AudioCalibrationState.calibrated);
    expect(result.ambientDbfs, inInclusiveRange(-50, -30));
  });

  test('short high energy burst does not become likely cry', () {
    final analyzer = CryAudioAnalyzerV2(
        config: const AudioAnalysisConfig(
            cryOnThreshold: 0.45,
            cryOffThreshold: 0.30,
            minCryDurationMs: 1500));
    final burst = generateCryLikePcm16le(
        sampleRate: sr, durationMs: 1000, amplitude: 0.9);
    final result = analyzer
        .addChunk(AudioChunk(
            pcm16le: burst, sampleRate: sr, channels: 1, timestampMs: 1000))
        .last;
    expect(result.cryScore, greaterThan(0.1));
    expect(result.isCryLikely, isFalse);
  });

  test('sustained cry-like signal becomes likely and raises cry band ratio',
      () {
    final analyzer = CryAudioAnalyzerV2(
        config: const AudioAnalysisConfig(
            cryOnThreshold: 0.35,
            cryOffThreshold: 0.20,
            minCryDurationMs: 750,
            smoothingAlpha: 0.6));
    final cry = generateCryLikePcm16le(
        sampleRate: sr, durationMs: 3000, amplitude: 0.8);
    final results = analyzer.addChunk(AudioChunk(
        pcm16le: cry, sampleRate: sr, channels: 1, timestampMs: 3000));
    expect(results.last.cryBandRatio, greaterThan(0.55));
    expect(results.any((r) => r.isCryLikely), isTrue);
  });

  test(
      'ambient-aware score stays modest when room noise rises after calibration',
      () {
    final analyzer = CryAudioAnalyzerV2(
        config: const AudioAnalysisConfig(calibrationMs: 1000));
    analyzer.startCalibration(timestampMs: 0);
    analyzer.addChunk(AudioChunk(
        pcm16le: generateNoisePcm16le(
            sampleRate: sr, durationMs: 1000, amplitude: 0.08),
        sampleRate: sr,
        channels: 1,
        timestampMs: 1000));
    final result = analyzer
        .addChunk(AudioChunk(
            pcm16le: generateNoisePcm16le(
                sampleRate: sr, durationMs: 1000, amplitude: 0.10, seed: 2),
            sampleRate: sr,
            channels: 1,
            timestampMs: 2000))
        .last;
    expect(result.ambientDeltaDb, lessThan(8));
    expect(result.rawCryScore, lessThan(0.65));
  });

  test('hysteresis holds candidate through modest score drop', () {
    final analyzer = CryAudioAnalyzerV2(
        config: const AudioAnalysisConfig(
            cryOnThreshold: 0.30,
            cryOffThreshold: 0.15,
            minCryDurationMs: 0,
            smoothingAlpha: 1));
    final loud = analyzer
        .addChunk(AudioChunk(
            pcm16le: generateCryLikePcm16le(
                sampleRate: sr, durationMs: 1000, amplitude: 0.8),
            sampleRate: sr,
            channels: 1,
            timestampMs: 1000))
        .last;
    expect(loud.isCryLikely, isTrue);
    final softer = analyzer
        .addChunk(AudioChunk(
            pcm16le: generateCryLikePcm16le(
                sampleRate: sr, durationMs: 1000, amplitude: 0.18),
            sampleRate: sr,
            channels: 1,
            timestampMs: 2000))
        .last;
    expect(softer.cryScore, greaterThan(0.15));
    expect(softer.isCryLikely, isTrue);
  });

  test('reset clears state and toJson returns core fields', () {
    final analyzer = CryAudioAnalyzerV2();
    final result = analyzer
        .addChunk(AudioChunk(
            pcm16le: generateCryLikePcm16le(sampleRate: sr, durationMs: 1000),
            sampleRate: sr,
            channels: 1,
            timestampMs: 1000))
        .last;
    expect(result.toJson().keys,
        containsAll(['timestampMs', 'cryScore', 'calibrationState', 'rms']));
    analyzer.startCalibration(timestampMs: 1000);
    analyzer.reset();
    expect(analyzer.calibrationState, AudioCalibrationState.uncalibrated);
    expect(analyzer.diagnostics()['candidateActive'], isFalse);
  });
}
