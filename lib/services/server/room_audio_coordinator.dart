import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../platform/pcm_audio_output.dart';

enum RoomAudioMode { idle, comfort, talk }

class RoomAudioCoordinator {
  RoomAudioCoordinator({
    PcmAudioSink sink = const PcmAudioOutput(),
    this.sampleRate = 16000,
    this.channels = 1,
    this.frameDuration = const Duration(milliseconds: 20),
    ComfortPcmGenerator? generator,
  })  : _sink = sink,
        _generator = generator ?? ComfortPcmGenerator(sampleRate: sampleRate);

  final PcmAudioSink _sink;
  final ComfortPcmGenerator _generator;
  final int sampleRate;
  final int channels;
  final Duration frameDuration;

  Future<void> _operations = Future<void>.value();
  Timer? _comfortTimer;
  RoomAudioMode _mode = RoomAudioMode.idle;
  String? _comfortTrackId;
  double _comfortVolume = .5;
  bool _comfortRequested = false;
  bool _comfortWriteInFlight = false;
  bool _disposed = false;
  int _generation = 0;
  int _writesAccepted = 0;
  int _writesDropped = 0;
  int _bytesWritten = 0;
  int? _lastWriteAtMs;
  Object? _lastError;

  RoomAudioMode get mode => _mode;

  Future<void> applyComfort({
    required bool playing,
    required String? trackId,
    required double volume,
  }) =>
      _serialize(() async {
        _comfortRequested = playing && trackId != null;
        _comfortTrackId = trackId;
        _comfortVolume = volume.clamp(0, 1).toDouble();
        if (_mode == RoomAudioMode.talk) return;
        if (!_comfortRequested) {
          await _stopOutputLocked();
          return;
        }
        await _startComfortLocked();
      });

  Future<void> beginTalk({
    int sampleRate = 16000,
    int channels = 1,
  }) =>
      _serialize(() async {
        _generation++;
        _comfortTimer?.cancel();
        _comfortTimer = null;
        await _stopSinkBestEffort();
        await _sink.start(sampleRate: sampleRate, channels: channels);
        _mode = RoomAudioMode.talk;
        _lastError = null;
      });

  Future<bool> writeTalk(Uint8List pcm16le) async {
    var accepted = false;
    await _serialize(() async {
      if (_mode != RoomAudioMode.talk || pcm16le.length < 2) {
        _writesDropped++;
        return;
      }
      final alignedLength = pcm16le.length - (pcm16le.length % 2);
      if (alignedLength <= 0) {
        _writesDropped++;
        return;
      }
      final payload = alignedLength == pcm16le.length
          ? pcm16le
          : Uint8List.sublistView(pcm16le, 0, alignedLength);
      try {
        accepted = await _sink.write(payload);
        _recordWrite(accepted, payload.length);
      } catch (error) {
        _lastError = error;
        _writesDropped++;
      }
    });
    return accepted;
  }

  Future<void> endTalk() => _serialize(() async {
        if (_mode != RoomAudioMode.talk) return;
        await _stopSinkBestEffort();
        _mode = RoomAudioMode.idle;
        if (_comfortRequested && _comfortTrackId != null) {
          await _startComfortLocked();
        }
      });

  Future<Map<String, Object?>> snapshot() async {
    Map<String, Object?> native = const {};
    try {
      native = await _sink.status();
    } catch (error) {
      _lastError = error;
    }
    return {
      'mode': _mode.name,
      'comfortRequested': _comfortRequested,
      'comfortTrackId': _comfortTrackId,
      'writesAccepted': _writesAccepted,
      'writesDropped': _writesDropped,
      'bytesWritten': _bytesWritten,
      'lastWriteAtMs': _lastWriteAtMs,
      'lastError': _lastError?.toString(),
      'native': native,
    };
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _serialize(() async {
      _comfortRequested = false;
      await _stopOutputLocked();
    }, allowDisposed: true);
  }

  Future<void> _startComfortLocked() async {
    final trackId = _comfortTrackId;
    if (trackId == null) return;
    _generation++;
    final generation = _generation;
    _comfortTimer?.cancel();
    await _stopSinkBestEffort();
    _generator.reset(trackId);
    await _sink.start(sampleRate: sampleRate, channels: channels);
    _mode = RoomAudioMode.comfort;
    _lastError = null;
    _comfortTimer = Timer.periodic(frameDuration, (_) {
      _pumpComfort(generation);
    });
    _pumpComfort(generation);
  }

  void _pumpComfort(int generation) {
    if (_comfortWriteInFlight ||
        _disposed ||
        generation != _generation ||
        _mode != RoomAudioMode.comfort) {
      if (_comfortWriteInFlight) _writesDropped++;
      return;
    }
    final trackId = _comfortTrackId;
    if (trackId == null) return;
    _comfortWriteInFlight = true;
    final frame = _generator.nextFrame(
      trackId: trackId,
      volume: _comfortVolume,
      duration: frameDuration,
    );
    unawaited(() async {
      try {
        final accepted = await _sink.write(frame);
        if (generation == _generation) _recordWrite(accepted, frame.length);
      } catch (error) {
        _lastError = error;
        _writesDropped++;
      } finally {
        _comfortWriteInFlight = false;
      }
    }());
  }

  void _recordWrite(bool accepted, int byteCount) {
    if (accepted) {
      _writesAccepted++;
      _bytesWritten += byteCount;
      _lastWriteAtMs = DateTime.now().millisecondsSinceEpoch;
    } else {
      _writesDropped++;
    }
  }

  Future<void> _stopOutputLocked() async {
    _generation++;
    _comfortTimer?.cancel();
    _comfortTimer = null;
    await _stopSinkBestEffort();
    _mode = RoomAudioMode.idle;
  }

  Future<void> _stopSinkBestEffort() async {
    try {
      await _sink.stop();
    } catch (error) {
      _lastError = error;
    }
  }

  Future<void> _serialize(
    Future<void> Function() operation, {
    bool allowDisposed = false,
  }) {
    Future<void> run() async {
      if (_disposed && !allowDisposed) {
        return;
      }
      try {
        await operation();
      } catch (error, stackTrace) {
        _lastError = error;
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    final next = _operations.then<void>(
      (_) => run(),
      onError: (_) => run(),
    );
    // A failed native start/write must reach its caller, but must not poison
    // the serialized lifecycle queue. Later stop/retry commands still run.
    _operations = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}

class ComfortPcmGenerator {
  ComfortPcmGenerator({required this.sampleRate, int seed = 0x51f15e})
      : _noiseState = seed;

  final int sampleRate;
  int _noiseState;
  int _sampleCursor = 0;
  double _pinkState = 0;
  String? _trackId;

  void reset(String trackId) {
    if (_trackId == trackId) return;
    _trackId = trackId;
    _sampleCursor = 0;
    _pinkState = 0;
  }

  Uint8List nextFrame({
    required String trackId,
    required double volume,
    required Duration duration,
  }) {
    reset(trackId);
    final sampleCount = max(
      1,
      sampleRate * duration.inMicroseconds ~/ Duration.microsecondsPerSecond,
    );
    final output = Uint8List(sampleCount * 2);
    final data = ByteData.sublistView(output);
    final gain = volume.clamp(0, 1).toDouble();
    for (var index = 0; index < sampleCount; index++) {
      final value = switch (trackId) {
        'pink_noise' => _pinkNoise(),
        'rain' => _rain(),
        'soft_lullaby' => _lullaby(),
        _ => _whiteNoise(),
      };
      final sample = (value * gain * 32767).round().clamp(-32768, 32767);
      data.setInt16(index * 2, sample, Endian.little);
      _sampleCursor++;
    }
    return output;
  }

  double _whiteNoise() => _randomSigned() * .22;

  double _pinkNoise() {
    _pinkState = (_pinkState * .985) + (_randomSigned() * .015);
    return (_pinkState * 1.8).clamp(-.28, .28);
  }

  double _rain() {
    final base = _pinkNoise() * .45;
    final drop = (_nextRandom() & 0x7ff) == 0 ? _randomSigned() * .55 : 0.0;
    return (base + drop).clamp(-.5, .5);
  }

  double _lullaby() {
    const notes = [
      261.63,
      329.63,
      392.00,
      329.63,
      293.66,
      349.23,
      440.00,
      349.23
    ];
    final noteFrames = max(1, sampleRate * 3 ~/ 4);
    final note = notes[(_sampleCursor ~/ noteFrames) % notes.length];
    final phase = 2 * pi * note * _sampleCursor / sampleRate;
    final envelopePhase = (_sampleCursor % noteFrames) / noteFrames;
    final envelope = sin(pi * envelopePhase).clamp(0, 1);
    return (sin(phase) * .16 + sin(phase / 2) * .05) * envelope;
  }

  double _randomSigned() => (_nextRandom() / 0x7fffffff) * 2 - 1;

  int _nextRandom() {
    var value = _noiseState & 0x7fffffff;
    value ^= (value << 13) & 0x7fffffff;
    value ^= value >> 17;
    value ^= (value << 5) & 0x7fffffff;
    _noiseState = value & 0x7fffffff;
    return _noiseState;
  }
}
