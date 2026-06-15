import 'dart:typed_data';

/// Fixed-capacity sample ring for sliding-window audio analysis.
class AudioRingBuffer {
  AudioRingBuffer({
    required this.sampleRate,
    required this.windowMs,
    required this.hopMs,
  })  : windowSamples = sampleRate * windowMs ~/ 1000,
        hopSamples = sampleRate * hopMs ~/ 1000,
        _buffer = Int16List((sampleRate * windowMs ~/ 1000) * 2);

  final int sampleRate;
  final int windowMs;
  final int hopMs;
  final int windowSamples;
  final int hopSamples;
  final Int16List _buffer;
  var _writeIndex = 0;
  var _sampleCount = 0;
  int? _lastAnalyzeSampleCount;

  bool get hasEnoughForWindow => _sampleCount >= windowSamples;

  void addSamples(Int16List samples, {required int timestampMs}) {
    for (final sample in samples) {
      _buffer[_writeIndex] = sample;
      _writeIndex = (_writeIndex + 1) % _buffer.length;
      _sampleCount++;
    }
  }

  bool shouldAnalyze(int timestampMs) {
    if (!hasEnoughForWindow) return false;
    final last = _lastAnalyzeSampleCount;
    if (last == null || _sampleCount - last >= hopSamples) {
      _lastAnalyzeSampleCount = _sampleCount;
      return true;
    }
    return false;
  }

  Int16List readLatestWindow() {
    if (!hasEnoughForWindow) return Int16List(0);
    final out = Int16List(windowSamples);
    var start = (_writeIndex - windowSamples) % _buffer.length;
    if (start < 0) start += _buffer.length;
    for (var i = 0; i < windowSamples; i++) {
      out[i] = _buffer[(start + i) % _buffer.length];
    }
    return out;
  }

  void reset() {
    _buffer.fillRange(0, _buffer.length, 0);
    _writeIndex = 0;
    _sampleCount = 0;
    _lastAnalyzeSampleCount = null;
  }
}
