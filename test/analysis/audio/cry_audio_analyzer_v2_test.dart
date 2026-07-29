import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/analysis/audio/audio_analysis_config.dart';
import 'package:miucam/analysis/audio/audio_calibration_state.dart';
import 'package:miucam/analysis/audio/audio_chunk.dart';
import 'package:miucam/analysis/audio/cry_audio_analyzer_v2.dart';
import 'test_audio_generators.dart';

void main() {
  const sr = 16000;
  test('ekran cry eşiği için off eşiği daima daha düşük türetilir', () {
    expect(AudioAnalysisConfig.hysteresisOffThreshold(.20), closeTo(.14, 1e-9));
    expect(AudioAnalysisConfig.hysteresisOffThreshold(.50), closeTo(.35, 1e-9));
    expect(
        AudioAnalysisConfig.hysteresisOffThreshold(.95), closeTo(.665, 1e-9));
  });

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

  test('cry detection is not tied to exact synthetic center frequencies', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        cryOnThreshold: .35,
        cryOffThreshold: .20,
        minCryDurationMs: 750,
        smoothingAlpha: .6,
      ),
    );
    final results = analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 3000,
        amplitude: .8,
        frequencyOffsetHz: 37,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 3000,
    ));

    expect(results.any((result) => result.isCryLikely), isTrue);
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

  test('self-audio kesintisi kalibrasyonu koruyup cry adayını temizler', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        calibrationMs: 1000,
        cryOnThreshold: .30,
        cryOffThreshold: .15,
        minCryDurationMs: 1500,
        smoothingAlpha: 1,
      ),
    );
    analyzer.startCalibration(timestampMs: 0);
    analyzer.addChunk(AudioChunk(
      pcm16le: generateSinePcm16le(
        sampleRate: sr,
        frequencyHz: 440,
        durationMs: 1000,
        amplitude: 0,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 1000,
    ));
    analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 1000,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 2000,
    ));

    expect(analyzer.calibrationState, AudioCalibrationState.calibrated);
    expect(analyzer.diagnostics()['candidateActive'], isTrue);

    analyzer.markDiscontinuity();

    expect(analyzer.calibrationState, AudioCalibrationState.calibrated);
    expect(analyzer.diagnostics()['candidateActive'], isFalse);
  });

  test('kalibrasyondaki kısa yüksek ses oda baseline değerini bozmaz', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(calibrationMs: 10000),
    );
    analyzer.startCalibration(timestampMs: 0);

    analyzer.addChunk(AudioChunk(
      pcm16le: generateNoisePcm16le(
        sampleRate: sr,
        durationMs: 4000,
        amplitude: .02,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 4000,
    ));
    analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 1000,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 5000,
    ));
    final result = analyzer
        .addChunk(AudioChunk(
          pcm16le: generateNoisePcm16le(
            sampleRate: sr,
            durationMs: 8000,
            amplitude: .02,
            seed: 3,
          ),
          sampleRate: sr,
          channels: 1,
          timestampMs: 13000,
        ))
        .last;

    expect(result.calibrationState, AudioCalibrationState.calibrated);
    expect(result.ambientDbfs, inInclusiveRange(-45, -30));
  });

  test('kalibrasyon cry biçimli pencereleri oda gürültüsü diye öğrenmez', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(calibrationMs: 1000),
    )..startCalibration(timestampMs: 0);

    analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 2000,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 2000,
    ));

    expect(analyzer.calibrationState, AudioCalibrationState.calibrating);
    expect(analyzer.diagnostics()['calibrationAcceptedMs'], 0);

    analyzer.addChunk(AudioChunk(
      pcm16le: generateNoisePcm16le(
        sampleRate: sr,
        durationMs: 3000,
        amplitude: .02,
        seed: 9,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 5000,
    ));

    expect(analyzer.calibrationState, AudioCalibrationState.calibrated);
  });

  test('sürekli ağlama kalibrasyonu sonsuza kadar kilitlemez', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        calibrationMs: 1000,
        cryOnThreshold: .35,
        cryOffThreshold: .20,
        minCryDurationMs: 500,
        smoothingAlpha: 1,
      ),
    )..startCalibration(timestampMs: 0);

    final results = analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 8000,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 8000,
    ));

    expect(analyzer.calibrationState, AudioCalibrationState.calibrated);
    expect(analyzer.diagnostics()['calibrationTimedOut'], isTrue);
    expect(analyzer.diagnostics()['calibrationAcceptedMs'], 0);
    expect(results.any((result) => result.isCryLikely), isTrue);
  });

  test('clipped başlangıç sesi kalibrasyon sonrası da cry kanıtı olmaz', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        calibrationMs: 1000,
        cryOnThreshold: .30,
        cryOffThreshold: .15,
        minCryDurationMs: 0,
        smoothingAlpha: 1,
      ),
    )..startCalibration(timestampMs: 0);

    final results = analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 8000,
        amplitude: 3,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 8000,
    ));

    expect(analyzer.calibrationState, AudioCalibrationState.calibrated);
    expect(results.any((result) => result.isClipped), isTrue);
    expect(results.any((result) => result.isCryLikely), isFalse);
    expect(results.last.cryScore, 0);
  });

  test('kalibrasyon kesintisi timeout süresini ve kirli birikimi sıfırlar', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(calibrationMs: 1000),
    )..startCalibration(timestampMs: 0);

    analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 5000,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 5000,
    ));
    expect(analyzer.calibrationState, AudioCalibrationState.calibrating);

    analyzer.markDiscontinuity();
    analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 2000,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 7000,
    ));

    expect(analyzer.calibrationState, AudioCalibrationState.calibrating);
    expect(analyzer.diagnostics()['calibrationAcceptedMs'], 0);
    expect(analyzer.diagnostics()['calibrationTimedOut'], isFalse);
  });

  test(
      'dijital sessizlikten sonra fan benzeri gürültü cry olmaz ve baseline toparlar',
      () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        calibrationMs: 1000,
        cryOnThreshold: .45,
        cryOffThreshold: .31,
        minCryDurationMs: 0,
        smoothingAlpha: 1,
        ambientUpdateAlpha: .05,
      ),
    );
    analyzer.startCalibration(timestampMs: 0);
    analyzer.addChunk(AudioChunk(
      pcm16le: generateSinePcm16le(
        sampleRate: sr,
        frequencyHz: 440,
        durationMs: 1000,
        amplitude: 0,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 1000,
    ));

    final results = analyzer.addChunk(AudioChunk(
      pcm16le: generateNoisePcm16le(
        sampleRate: sr,
        durationMs: 12000,
        amplitude: .03,
        seed: 7,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 13000,
    ));

    expect(results.any((result) => result.isCryLikely), isFalse);
    expect(
      results.map((result) => result.cryScore).reduce((a, b) => a > b ? a : b),
      lessThan(.45),
    );
    expect(results.last.ambientDbfs, greaterThan(-50));
  });

  test('sabit alarm tonu ağlama benzeri süreyi başlatmaz', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        cryOnThreshold: .45,
        cryOffThreshold: .31,
        minCryDurationMs: 0,
        smoothingAlpha: 1,
      ),
    );

    final results = analyzer.addChunk(AudioChunk(
      pcm16le: generateSinePcm16le(
        sampleRate: sr,
        frequencyHz: 600,
        durationMs: 4000,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 4000,
    ));

    expect(results.any((result) => result.isCryLikely), isFalse);
    expect(results.last.amplitudeModulation, lessThan(.02));
  });

  test('yetişkin sesi benzeri düşük temel frekanslı harmonikler cry olmaz', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        cryOnThreshold: .45,
        cryOffThreshold: .31,
        minCryDurationMs: 0,
        smoothingAlpha: 1,
      ),
    );

    final results = analyzer.addChunk(AudioChunk(
      pcm16le: generateAdultVoiceLikePcm16le(
        sampleRate: sr,
        durationMs: 5000,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 5000,
    ));

    expect(results.any((result) => result.isCryLikely), isFalse);
  });

  test('fan ortamına kalibre olduktan sonra gerçek cry benzeri sinyal seçilir',
      () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        calibrationMs: 2000,
        cryOnThreshold: .50,
        cryOffThreshold: .35,
        minCryDurationMs: 500,
        smoothingAlpha: .6,
      ),
    );
    analyzer.startCalibration(timestampMs: 0);
    analyzer.addChunk(AudioChunk(
      pcm16le: generateNoisePcm16le(
        sampleRate: sr,
        durationMs: 2000,
        amplitude: .03,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 2000,
    ));

    final results = analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 2500,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 4500,
    ));

    expect(results.any((result) => result.isCryLikely), isTrue);
    expect(results.last.amplitudeModulation, greaterThan(.06));
  });

  test('audio timestamp boşluğu eski ve yeni cry adayını birleştirmez', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        cryOnThreshold: .30,
        cryOffThreshold: .15,
        minCryDurationMs: 1500,
        smoothingAlpha: 1,
      ),
    );
    analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 1000,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 1000,
    ));

    final result = analyzer
        .addChunk(AudioChunk(
          pcm16le: generateCryLikePcm16le(
            sampleRate: sr,
            durationMs: 1000,
            amplitude: .8,
          ),
          sampleRate: sr,
          channels: 1,
          timestampMs: 4000,
        ))
        .last;

    expect(result.isCryLikely, isFalse);
    expect(analyzer.diagnostics()['candidateActive'], isTrue);
  });

  test('beklenmeyen sample rate yanlış özellik üretmek yerine invalid döner',
      () {
    final analyzer = CryAudioAnalyzerV2();

    final result = analyzer
        .addChunk(AudioChunk(
          pcm16le: generateCryLikePcm16le(
            sampleRate: 8000,
            durationMs: 1000,
          ),
          sampleRate: 8000,
          channels: 1,
          timestampMs: 1000,
        ))
        .single;

    expect(result.invalidChunk, isTrue);
    expect(result.isCryLikely, isFalse);
  });

  test('truncated PCM eski ve yeni cry adayını birleştirmez', () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        cryOnThreshold: .30,
        cryOffThreshold: .15,
        minCryDurationMs: 1500,
        smoothingAlpha: 1,
      ),
    );
    analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 1000,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 1000,
    ));

    final invalid = analyzer.addChunk(AudioChunk(
      pcm16le: Uint8List(641),
      sampleRate: sr,
      channels: 1,
      timestampMs: 1000,
    ));
    final afterCorruption = analyzer
        .addChunk(AudioChunk(
          pcm16le: generateCryLikePcm16le(
            sampleRate: sr,
            durationMs: 1000,
            amplitude: .8,
          ),
          sampleRate: sr,
          channels: 1,
          timestampMs: 2000,
        ))
        .last;

    expect(invalid.single.invalidChunk, isTrue);
    expect(afterCorruption.isCryLikely, isFalse);
  });

  test('ayar reloadu kalibre baselineı koruyup 30 saniyelik blackout yaratmaz',
      () {
    final analyzer = CryAudioAnalyzerV2(
      config: const AudioAnalysisConfig(
        cryOnThreshold: .50,
        cryOffThreshold: .35,
        minCryDurationMs: 500,
        smoothingAlpha: .6,
      ),
    );
    analyzer.restoreCalibratedAmbient(-40);

    final results = analyzer.addChunk(AudioChunk(
      pcm16le: generateCryLikePcm16le(
        sampleRate: sr,
        durationMs: 2500,
        amplitude: .8,
      ),
      sampleRate: sr,
      channels: 1,
      timestampMs: 2500,
    ));

    expect(analyzer.calibrationState, AudioCalibrationState.calibrated);
    expect(results.any((result) => result.isCryLikely), isTrue);
  });
}
