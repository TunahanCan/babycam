import 'dart:typed_data';

/// Fixed-capacity sample ring for sliding-window audio analysis.
class AudioRingBuffer {
  AudioRingBuffer({
    required this.sampleRate,
    required this.windowMs,
    required this.hopMs,
  })  : windowSamples = _samplesFor(sampleRate, windowMs, 'windowMs'),
        hopSamples = _samplesFor(sampleRate, hopMs, 'hopMs'),
        _buffer = Int16List(_samplesFor(sampleRate, windowMs, 'windowMs') * 2);

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
    _sampleCount += samples.length;
    if (samples.length >= _buffer.length) {
      _buffer.setRange(
          0, _buffer.length, samples, samples.length - _buffer.length);
      _writeIndex = 0;
      return;
    }
    final available = _buffer.length - _writeIndex;
    final firstLength = samples.length < available ? samples.length : available;
    _buffer.setRange(_writeIndex, _writeIndex + firstLength, samples);
    if (firstLength < samples.length) {
      _buffer.setRange(0, samples.length - firstLength, samples, firstLength);
    }
    _writeIndex = (_writeIndex + samples.length) % _buffer.length;
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
    copyLatestWindow(out);
    return out;
  }

  /// Copies into caller-owned scratch space without allocating a new window.
  /// Returns false without changing [output] until a complete window exists.
  bool copyLatestWindow(Int16List output) {
    if (output.length != windowSamples) {
      throw ArgumentError.value(output.length, 'output.length',
          'must equal windowSamples ($windowSamples)');
    }
    if (!hasEnoughForWindow) return false;
    var start = (_writeIndex - windowSamples) % _buffer.length;
    if (start < 0) start += _buffer.length;
    final available = _buffer.length - start;
    final firstLength = windowSamples < available ? windowSamples : available;
    output.setRange(0, firstLength, _buffer, start);
    if (firstLength < windowSamples) {
      output.setRange(firstLength, windowSamples, _buffer);
    }
    return true;
  }

  void reset() {
    _buffer.fillRange(0, _buffer.length, 0);
    _writeIndex = 0;
    _sampleCount = 0;
    _lastAnalyzeSampleCount = null;
  }

  static int _samplesFor(int sampleRate, int durationMs, String field) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
    }
    final count = sampleRate * durationMs ~/ 1000;
    if (durationMs <= 0 || count <= 0) {
      throw ArgumentError.value(
          durationMs, field, 'must contain at least one sample');
    }
    return count;
  }
}
