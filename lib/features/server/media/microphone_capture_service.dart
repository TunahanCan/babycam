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
  bool _recorderCreated = false;
  bool? _permissionGranted;
  String? _lastStartError;
  int _chunksCaptured = 0;
  int? _lastChunkAtMs;
  int _lastChunkBytes = 0;

  bool get isActive => _subscription != null;
  MicrophoneCaptureSnapshot get snapshot => MicrophoneCaptureSnapshot(
        recorderCreated: _recorderCreated,
        permissionGranted: _permissionGranted,
        active: isActive,
        lastChunkAtMs: _lastChunkAtMs,
        chunksCaptured: _chunksCaptured,
        lastChunkBytes: _lastChunkBytes,
        lastStartError: _lastStartError,
        leveler: _streamLeveler.lastSnapshot,
      );

  Future<bool> start({
    required MicrophoneChunkHandler onChunk,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    if (_subscription != null) return true;
    final recorder = _recorder ??= _recorderFactory();
    _recorderCreated = true;
    _lastStartError = null;

    try {
      final hasPermission = await recorder.hasPermission();
      _permissionGranted = hasPermission;
      if (!hasPermission) return false;

      final stream = await recorder.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
      ));
      _subscription = stream.listen(
        (pcm16le) => _handleChunk(pcm16le, onChunk),
        onError: (Object error, StackTrace stackTrace) {
          _lastStartError = error.toString();
          onError?.call(error, stackTrace);
        },
      );
      return true;
    } catch (error) {
      _lastStartError = error.toString();
      rethrow;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    final recorder = _recorder;
    if (recorder == null) return;
    try {
      await recorder.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    final recorder = _recorder;
    _recorder = null;
    await recorder?.dispose();
  }

  void resetDiagnostics() {
    _chunksCaptured = 0;
    _lastChunkAtMs = null;
    _lastChunkBytes = 0;
    _lastStartError = null;
    _streamLeveler.reset();
  }

  void _handleChunk(Uint8List pcm16le, MicrophoneChunkHandler onChunk) {
    final now = _nowMs();
    _lastChunkAtMs = now;
    _lastChunkBytes = pcm16le.length;
    _chunksCaptured++;
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
    required this.lastChunkAtMs,
    required this.chunksCaptured,
    required this.lastChunkBytes,
    required this.lastStartError,
    required this.leveler,
  });

  final bool recorderCreated;
  final bool? permissionGranted;
  final bool active;
  final int? lastChunkAtMs;
  final int chunksCaptured;
  final int lastChunkBytes;
  final String? lastStartError;
  final AudioStreamLevelerSnapshot leveler;
}
