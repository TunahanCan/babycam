import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../../services/server/audio_stream_leveler.dart';

typedef MicrophoneChunkHandler = void Function(MicrophonePcmChunk chunk);
typedef MicrophoneRecorderFactory = MicrophoneRecorderPort Function();

abstract class MicrophoneRecorderPort {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startStream(RecordConfig config);
  Future<void> stop();
  Future<void> dispose();
}

class RecordMicrophoneRecorder implements MicrophoneRecorderPort {
  RecordMicrophoneRecorder([AudioRecorder? recorder])
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      _recorder.startStream(config);

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

class MicrophoneCaptureService {
  MicrophoneCaptureService({
    required this.sampleRate,
    required this.channels,
    MicrophoneRecorderPort? recorder,
    MicrophoneRecorderFactory? recorderFactory,
    AudioStreamLeveler? streamLeveler,
    int Function()? nowMs,
  })  : _recorder = recorder,
        _recorderFactory = recorderFactory ?? RecordMicrophoneRecorder.new,
        _streamLeveler = streamLeveler ?? AudioStreamLeveler.liveMonitor(),
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int sampleRate;
  final int channels;
  MicrophoneRecorderPort? _recorder;
  final MicrophoneRecorderFactory _recorderFactory;
  final AudioStreamLeveler _streamLeveler;
  final int Function() _nowMs;

  StreamSubscription<Uint8List>? _subscription;
  Future<bool>? _startOperation;
  int _generation = 0;
  bool _disposed = false;
  bool _recorderCreated = false;
  bool? _permissionGranted;
  String? _lastFailureReason;
  String? _lastStartError;
  int _chunksCaptured = 0;
  int _bytesCaptured = 0;
  int? _lastStartAttemptAtMs;
  int? _lastChunkAtMs;
  int _lastChunkBytes = 0;

  bool get isActive => _subscription != null;
  MicrophoneCaptureSnapshot get snapshot => MicrophoneCaptureSnapshot(
        recorderCreated: _recorderCreated,
        permissionGranted: _permissionGranted,
        active: isActive,
        lastStartAttemptAtMs: _lastStartAttemptAtMs,
        lastChunkAtMs: _lastChunkAtMs,
        chunksCaptured: _chunksCaptured,
        bytesCaptured: _bytesCaptured,
        lastChunkBytes: _lastChunkBytes,
        failureReason: _lastFailureReason,
        lastStartError: _lastStartError,
        leveler: _streamLeveler.lastSnapshot,
      );

  Future<bool> start({
    required MicrophoneChunkHandler onChunk,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    if (_disposed) {
      return Future<bool>.error(
        StateError('MicrophoneCaptureService is disposed.'),
      );
    }
    if (_subscription != null) return Future<bool>.value(true);
    final current = _startOperation;
    if (current != null) return current;

    final generation = ++_generation;
    late final Future<bool> operation;
    operation = _start(
      generation: generation,
      onChunk: onChunk,
      onError: onError,
    ).whenComplete(() {
      if (identical(_startOperation, operation)) _startOperation = null;
    });
    _startOperation = operation;
    return operation;
  }

  Future<bool> _start({
    required int generation,
    required MicrophoneChunkHandler onChunk,
    required void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final recorder = _recorder ??= _recorderFactory();
    _recorderCreated = true;
    _lastStartAttemptAtMs = _nowMs();
    _lastFailureReason = null;
    _lastStartError = null;

    try {
      final hasPermission = await recorder.hasPermission();
      if (!_isCurrent(generation)) return false;
      _permissionGranted = hasPermission;
      if (!hasPermission) {
        _lastFailureReason = 'permissionDenied';
        _lastStartError = 'Microphone permission denied';
        return false;
      }

      final stream = await recorder.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
      ));
      if (!_isCurrent(generation)) {
        await _stopRecorder(recorder);
        return false;
      }
      late final StreamSubscription<Uint8List> subscription;
      subscription = stream.listen(
        (pcm16le) {
          if (_isCurrent(generation)) _handleChunk(pcm16le, onChunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_isCurrent(generation)) return;
          _lastFailureReason = 'captureStreamError';
          _lastStartError = error.toString();
          onError?.call(error, stackTrace);
        },
        onDone: () {
          if (_isCurrent(generation) &&
              identical(_subscription, subscription)) {
            _subscription = null;
          }
        },
      );
      if (!_isCurrent(generation)) {
        await subscription.cancel();
        await _stopRecorder(recorder);
        return false;
      }
      _subscription = subscription;
      return true;
    } catch (error) {
      _lastFailureReason = 'captureStartFailed';
      _lastStartError = error.toString();
      rethrow;
    }
  }

  Future<void> stop() async {
    _generation++;
    final starting = _startOperation;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {}
    }
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final recorder = _recorder;
    if (recorder == null) return;
    await _stopRecorder(recorder);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    final recorder = _recorder;
    _recorder = null;
    await recorder?.dispose();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _stopRecorder(MicrophoneRecorderPort recorder) async {
    try {
      await recorder.stop();
    } catch (_) {}
  }

  void resetDiagnostics() {
    _chunksCaptured = 0;
    _bytesCaptured = 0;
    _lastStartAttemptAtMs = null;
    _lastChunkAtMs = null;
    _lastChunkBytes = 0;
    _lastFailureReason = null;
    _lastStartError = null;
    _streamLeveler.reset();
  }

  void _handleChunk(Uint8List pcm16le, MicrophoneChunkHandler onChunk) {
    final now = _nowMs();
    _lastChunkAtMs = now;
    _lastChunkBytes = pcm16le.length;
    _chunksCaptured++;
    _bytesCaptured += pcm16le.length;
    _lastFailureReason = null;
    _lastStartError = null;
    onChunk(MicrophonePcmChunk(
      rawPcm16le: pcm16le,
      streamPcm16le: _streamLeveler.processPcm16le(pcm16le),
      sampleRate: sampleRate,
      channels: channels,
      timestampMs: now,
      leveler: _streamLeveler.lastSnapshot,
    ));
  }
}

class MicrophonePcmChunk {
  const MicrophonePcmChunk({
    required this.rawPcm16le,
    required this.streamPcm16le,
    required this.sampleRate,
    required this.channels,
    required this.timestampMs,
    required this.leveler,
  });

  final Uint8List rawPcm16le;
  final Uint8List streamPcm16le;
  final int sampleRate;
  final int channels;
  final int timestampMs;
  final AudioStreamLevelerSnapshot leveler;
}

class MicrophoneCaptureSnapshot {
  const MicrophoneCaptureSnapshot({
    required this.recorderCreated,
    required this.permissionGranted,
    required this.active,
    required this.lastStartAttemptAtMs,
    required this.lastChunkAtMs,
    required this.chunksCaptured,
    required this.bytesCaptured,
    required this.lastChunkBytes,
    required this.failureReason,
    required this.lastStartError,
    required this.leveler,
  });

  final bool recorderCreated;
  final bool? permissionGranted;
  final bool active;
  final int? lastStartAttemptAtMs;
  final int? lastChunkAtMs;
  final int chunksCaptured;
  final int bytesCaptured;
  final int lastChunkBytes;
  final String? failureReason;
  final String? lastStartError;
  final AudioStreamLevelerSnapshot leveler;
}
