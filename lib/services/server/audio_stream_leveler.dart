import 'dart:math';
import 'dart:typed_data';

class AudioStreamLeveler {
  AudioStreamLeveler({
    this.targetRms = 3600,
    this.minRmsForGain = 64,
    this.maxGain = 12,
    this.maxPeak = 30000,
    this.attack = .38,
    this.release = .16,
  }) : _lastSnapshot = const AudioStreamLevelerSnapshot(
          inputRms: 0,
          outputRms: 0,
          inputPeak: 0,
          outputPeak: 0,
          gain: 1,
        );

  factory AudioStreamLeveler.liveMonitor() => AudioStreamLeveler(
        targetRms: 5200,
        minRmsForGain: 8,
        maxGain: 24,
        maxPeak: 28000,
        attack: .52,
        release: .12,
      );

  final int targetRms;
  final int minRmsForGain;
  final double maxGain;
  final int maxPeak;
  final double attack;
  final double release;

  double _gain = 1;
  double _appliedGain = 1;
  AudioStreamLevelerSnapshot _lastSnapshot;

  AudioStreamLevelerSnapshot get lastSnapshot => _lastSnapshot;

  Uint8List processPcm16le(
    Uint8List input, {
    int sampleRate = 16000,
    int channels = 1,
  }) {
    if (sampleRate <= 0 ||
        channels <= 0 ||
        input.length % (channels * 2) != 0) {
      throw ArgumentError('PCM input must contain complete sample frames.');
    }
    if (input.length < 2) {
      _lastSnapshot = AudioStreamLevelerSnapshot(
        inputRms: 0,
        outputRms: 0,
        inputPeak: 0,
        outputPeak: 0,
        gain: _gain,
      );
      return input;
    }

    final sampleCount = input.length ~/ 2;
    final inputView = ByteData.sublistView(input, 0, sampleCount * 2);
    var inputSumSquares = 0;
    var inputPeak = 0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = inputView.getInt16(i * 2, Endian.little);
      final absSample = sample.abs();
      if (absSample > inputPeak) inputPeak = absSample;
      inputSumSquares += sample * sample;
    }

    final inputRms = sqrt(inputSumSquares / sampleCount);
    final peakLimitedGain = _peakLimitedGain(inputPeak);
    final desiredGain = _desiredGain(inputRms, inputPeak);
    final smoothing = desiredGain > _gain ? attack : release;
    _gain = _gain + ((desiredGain - _gain) * smoothing);
    _gain = min(_gain, peakLimitedGain);
    if ((_gain - 1).abs() < .02) _gain = 1;

    // The RMS controller updates once per chunk. Applying its new gain to
    // every sample instantly creates a step (and an audible click) even when
    // the source waveform is continuous. Ramp for 5 ms, sharing the same gain
    // across channels and retaining the actual endpoint for short chunks.
    // An imminent peak still takes precedence over a smooth transition.
    final startingGain = min(_appliedGain, peakLimitedGain);
    final rampFrames = max(1, sampleRate * 5 ~/ 1000);
    if (_gain <= 1 && startingGain <= 1) {
      _appliedGain = _gain;
      _lastSnapshot = AudioStreamLevelerSnapshot(
        inputRms: inputRms,
        outputRms: inputRms,
        inputPeak: inputPeak,
        outputPeak: inputPeak,
        gain: _gain,
      );
      return input;
    }

    final output = Uint8List(sampleCount * 2);
    final outputView = ByteData.sublistView(output);
    var outputSumSquares = 0;
    var outputPeak = 0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = inputView.getInt16(i * 2, Endian.little);
      final progress = min(1.0, (i ~/ channels + 1) / rampFrames);
      _appliedGain = startingGain + (_gain - startingGain) * progress;
      final amplified =
          (sample * _appliedGain).round().clamp(-32768, 32767).toInt();
      final absSample = amplified.abs();
      if (absSample > outputPeak) outputPeak = absSample;
      outputSumSquares += amplified * amplified;
      outputView.setInt16(i * 2, amplified, Endian.little);
    }

    _lastSnapshot = AudioStreamLevelerSnapshot(
      inputRms: inputRms,
      outputRms: sqrt(outputSumSquares / sampleCount),
      inputPeak: inputPeak,
      outputPeak: outputPeak,
      gain: _appliedGain,
    );
    return output;
  }

  void reset() {
    _gain = 1;
    _appliedGain = 1;
    _lastSnapshot = const AudioStreamLevelerSnapshot(
      inputRms: 0,
      outputRms: 0,
      inputPeak: 0,
      outputPeak: 0,
      gain: 1,
    );
  }

  double _desiredGain(double inputRms, int inputPeak) {
    if (inputRms < minRmsForGain) return 1;
    return (targetRms / inputRms)
        .clamp(1.0, min(maxGain, _peakLimitedGain(inputPeak)));
  }

  double _peakLimitedGain(int inputPeak) =>
      inputPeak > 0 ? max(1.0, maxPeak / inputPeak) : maxGain;
}

class AudioStreamLevelerSnapshot {
  const AudioStreamLevelerSnapshot({
    required this.inputRms,
    required this.outputRms,
    required this.inputPeak,
    required this.outputPeak,
    required this.gain,
  });

  final double inputRms;
  final double outputRms;
  final int inputPeak;
  final int outputPeak;
  final double gain;

  Map<String, Object?> toJson() => {
        'inputRms': double.parse(inputRms.toStringAsFixed(2)),
        'outputRms': double.parse(outputRms.toStringAsFixed(2)),
        'inputPeak': inputPeak,
        'outputPeak': outputPeak,
        'gain': double.parse(gain.toStringAsFixed(2)),
      };
}
