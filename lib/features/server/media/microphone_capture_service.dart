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
    this.restartBaseDelay = const Duration(milliseconds: 250),
    this.restartMaxDelay = const Duration(seconds: 5),
    this.cleanupTimeout = const Duration(seconds: 2),
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
  final Duration restartBaseDelay;
  final Duration restartMaxDelay;
  final Duration cleanupTimeout;

  StreamSubscription<Uint8List>? _subscription;
  Future<({bool granted, bool current})>? _permissionOperation;
  Future<bool>? _startOperation;
  Timer? _restartTimer;
  int _restartAttempt = 0;
  int? _terminalHandledGeneration;
  int _generation = 0;
  int _permissionGeneration = 0;
  bool _captureRequested = false;
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
  Uint8List _pendingPcmBytes = Uint8List(0);

  bool get isActive =>
      _subscription != null ||
      _restartTimer != null ||
      (_captureRequested && _startOperation != null);
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

  /// Resolves microphone permission without starting capture.
  ///
  /// A successful result is cached so a caller can safely obtain permission
  /// before opening a remote media session and then call [start] without a
  /// second platform permission prompt.
  Future<bool> ensurePermission({
    bool preserveResolvedDecisionWhenCancelled = false,
  }) async {
    if (_disposed) {
      throw StateError('MicrophoneCaptureService is disposed.');
    }
    if (_permissionGranted == true) return true;
    var operation = _permissionOperation;
    if (operation == null) {
      final generation = _permissionGeneration;
      final recorder = _recorder ??= _recorderFactory();
      _recorderCreated = true;
      late final Future<({bool granted, bool current})> nextOperation;
      nextOperation = _ensurePermission(
        recorder: recorder,
        generation: generation,
      ).whenComplete(() {
        if (identical(_permissionOperation, nextOperation)) {
          _permissionOperation = null;
        }
      });
      _permissionOperation = nextOperation;
      operation = nextOperation;
    }
    final result = await operation;
    return result.granted &&
        (result.current || preserveResolvedDecisionWhenCancelled);
  }

  Future<({bool granted, bool current})> _ensurePermission({
    required MicrophoneRecorderPort recorder,
    required int generation,
  }) async {
    try {
      final granted = await recorder.hasPermission();
      final current = _isPermissionCurrent(generation);
      if (current) {
        _permissionGranted = granted;
        if (!granted) {
          _lastFailureReason = 'permissionDenied';
          _lastStartError = 'Microphone permission denied';
        }
      }
      return (granted: granted, current: current);
    } catch (error) {
      if (_isPermissionCurrent(generation)) {
        _lastFailureReason = 'permissionCheckFailed';
        _lastStartError = error.toString();
      }
      rethrow;
    }
  }

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

    _captureRequested = true;
    final generation = ++_generation;
    _pendingPcmBytes = Uint8List(0);
    _streamLeveler.reset();
    late final Future<bool> operation;
    operation = _start(
      generation: generation,
      onChunk: onChunk,
      onError: onError,
    ).whenComplete(() {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
        if (_subscription == null && _restartTimer == null) {
          _captureRequested = false;
        }
      }
    });
    _startOperation = operation;
    return operation;
  }

  Future<bool> _start({
    required int generation,
    required MicrophoneChunkHandler onChunk,
    required void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    _lastStartAttemptAtMs = _nowMs();
    _lastFailureReason = null;
    _lastStartError = null;

    try {
      final hasPermission = await ensurePermission();
      if (!_isCurrent(generation)) return false;
      if (!hasPermission) {
        _lastFailureReason = 'permissionDenied';
        _lastStartError = 'Microphone permission denied';
        return false;
      }

      final recorder = _recorder ??= _recorderFactory();
      _recorderCreated = true;
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
          unawaited(_handleTerminalCapture(
            generation: generation,
            subscription: subscription,
            onChunk: onChunk,
            onError: onError,
          ));
        },
        onDone: () {
          if (_isCurrent(generation) &&
              identical(_subscription, subscription)) {
            _lastFailureReason = 'captureStreamEnded';
            unawaited(_handleTerminalCapture(
              generation: generation,
              subscription: subscription,
              onChunk: onChunk,
              onError: onError,
            ));
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
    _restartTimer?.cancel();
    _restartTimer = null;
    _restartAttempt = 0;
    _terminalHandledGeneration = null;
    _generation++;
    _pendingPcmBytes = Uint8List(0);
    _permissionGeneration++;
    // A permission can be revoked while the app is in system settings. Keep
    // the grant only for the preflight-to-start handoff of one capture lease;
    // the next talk/capture must query the platform again.
    _permissionGranted = null;
    _captureRequested = false;
    final starting = _startOperation;
    final permission = _permissionOperation;
    final recorderAtStop = _recorder;
    final operationsSettled = await _waitForCleanup([
      if (starting != null) starting,
      if (permission != null) permission,
    ]);
    if (!operationsSettled && recorderAtStop != null) {
      if (identical(_startOperation, starting)) _startOperation = null;
      if (identical(_permissionOperation, permission)) {
        _permissionOperation = null;
      }
      // A start/permission call that outlives this capture lease can complete
      // after the next lease has begun. Never let that stale operation share
      // a recorder with the next capture, otherwise its cleanup could stop the
      // newer stream.
      await _discardRecorder(recorderAtStop);
    }
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel().timeout(cleanupTimeout);
      } catch (_) {}
    }
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
    if (recorder != null) {
      try {
        await recorder.dispose().timeout(cleanupTimeout);
      } catch (_) {}
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
  bool _isPermissionCurrent(int generation) =>
      !_disposed && generation == _permissionGeneration;

  Future<bool> _waitForCleanup(List<Future<Object?>> operations) async {
    if (operations.isEmpty) return true;
    try {
      await Future.wait(
        operations.map((operation) => operation.catchError((_) => null)),
      ).timeout(cleanupTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleTerminalCapture({
    required int generation,
    required StreamSubscription<Uint8List> subscription,
    required MicrophoneChunkHandler onChunk,
    required void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    if (!_isCurrent(generation) ||
        _terminalHandledGeneration == generation ||
        !identical(_subscription, subscription)) {
      return;
    }
    _terminalHandledGeneration = generation;
    _subscription = null;
    try {
      await subscription.cancel().timeout(cleanupTimeout);
    } catch (_) {}
    final recorder = _recorder;
    if (recorder != null) await _stopRecorder(recorder);
    if (!_isCurrent(generation)) return;
    _scheduleRestart(onChunk: onChunk, onError: onError);
  }

  void _scheduleRestart({
    required MicrophoneChunkHandler onChunk,
    required void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    if (_disposed || _restartTimer != null) return;
    final exponent = _restartAttempt.clamp(0, 8).toInt();
    final delayMs = (restartBaseDelay.inMilliseconds * (1 << exponent))
        .clamp(
          restartBaseDelay.inMilliseconds,
          restartMaxDelay.inMilliseconds,
        )
        .toInt();
    _restartAttempt++;
    final scheduledGeneration = _generation;
    _restartTimer = Timer(Duration(milliseconds: delayMs), () {
      _restartTimer = null;
      if (!_isCurrent(scheduledGeneration)) return;
      final restarting = start(onChunk: onChunk, onError: onError);
      final restartGeneration = _generation;
      unawaited(restarting.then<void>(
        (started) {
          if (!started && _isCurrent(restartGeneration)) {
            _scheduleRestart(onChunk: onChunk, onError: onError);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_isCurrent(restartGeneration)) return;
          _lastFailureReason = 'captureRestartFailed';
          _lastStartError = error.toString();
          onError?.call(error, stackTrace);
          _scheduleRestart(onChunk: onChunk, onError: onError);
        },
      ));
    });
  }

  Future<bool> _stopRecorder(MicrophoneRecorderPort recorder) async {
    try {
      await recorder.stop().timeout(cleanupTimeout);
      return true;
    } catch (_) {
      // A timed-out/failed native recorder is not safe to reuse. Detach and
      // dispose it best-effort so the next capture lease gets a fresh instance.
      await _discardRecorder(recorder);
      return false;
    }
  }

  Future<void> _discardRecorder(MicrophoneRecorderPort recorder) async {
    if (identical(_recorder, recorder)) _recorder = null;
    try {
      await recorder.dispose().timeout(cleanupTimeout);
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
    if (pcm16le.isEmpty) return;
    _restartAttempt = 0;
    _terminalHandledGeneration = null;
    final now = _nowMs();
    _lastChunkAtMs = now;
    _lastChunkBytes = pcm16le.length;
    _chunksCaptured++;
    _bytesCaptured += pcm16le.length;
    _lastFailureReason = null;
    _lastStartError = null;
    // Recorder/plugin chunks can split a PCM sample. Align before analysis
    // and gain processing so no trailing byte is lost or read as a new sample.
    final pending = _pendingPcmBytes;
    final combined = pending.isEmpty
        ? pcm16le
        : (Uint8List(pending.length + pcm16le.length)
          ..setRange(0, pending.length, pending)
          ..setRange(pending.length, pending.length + pcm16le.length, pcm16le));
    final frameBytes = channels * 2;
    final alignedLength = combined.length - combined.length % frameBytes;
    _pendingPcmBytes = alignedLength == combined.length
        ? Uint8List(0)
        : Uint8List.fromList(Uint8List.sublistView(combined, alignedLength));
    if (alignedLength == 0) return;
    final aligned = alignedLength == combined.length
        ? combined
        : Uint8List.sublistView(combined, 0, alignedLength);
    onChunk(MicrophonePcmChunk(
      rawPcm16le: aligned,
      streamPcm16le: _streamLeveler.processPcm16le(
        aligned,
        sampleRate: sampleRate,
        channels: channels,
      ),
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
