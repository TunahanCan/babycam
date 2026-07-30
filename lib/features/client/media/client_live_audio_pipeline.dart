import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/bytes/byte_chunk.dart';
import '../../../core/media/media_session_telemetry.dart';
import '../../../core/network/retry_policy.dart';
import 'pcm_audio_output.dart';
import 'wav_pcm_stream_parser.dart';

class ClientLiveAudioPipeline {
  ClientLiveAudioPipeline({
    PcmAudioSink audioOutput = const PcmAudioOutput(),
    HttpClient Function()? clientFactory,
    this.connectTimeout = const Duration(seconds: 5),
    this.readTimeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(milliseconds: 500),
    this.maxRetryDelay = const Duration(seconds: 4),
    this.frameDuration = const Duration(milliseconds: 20),
    this.minPlayoutDelay = const Duration(milliseconds: 60),
    this.maxPlayoutDelay = const Duration(milliseconds: 220),
    this.maxBufferedAudio = const Duration(milliseconds: 320),
    this.nativeQueueTarget = const Duration(milliseconds: 80),
    RetryPolicy? retryPolicy,
  })  : _audioOutputCoordinator = _coordinatorFor(audioOutput),
        _clientFactory = clientFactory,
        _retryPolicy = retryPolicy ??
            ExponentialBackoffPolicy(
              initialDelay: retryDelay,
              maxDelay: maxRetryDelay,
            );

  final _PcmAudioOutputCoordinator _audioOutputCoordinator;
  final HttpClient Function()? _clientFactory;
  final RetryPolicy _retryPolicy;
  final Duration connectTimeout;
  final Duration readTimeout;
  final Duration retryDelay;
  final Duration maxRetryDelay;
  final Duration frameDuration;
  final Duration minPlayoutDelay;
  final Duration maxPlayoutDelay;
  final Duration maxBufferedAudio;
  final Duration nativeQueueTarget;

  HttpClient? _client;
  _PipelineRun? _run;
  int _generation = 0;
  bool _outputStarted = false;
  bool _audioOutputStartInFlight = false;
  int? _audioOutputOwnerGeneration;
  Object? _audioOutputLease;
  Future<void>? _immediateAudioOutputStop;
  Future<void> _audioOutputOperation = Future<void>.value();
  final Stopwatch _playoutClock = Stopwatch()..start();
  ClientAudioJitterBuffer? _buffer;
  PcmAudioFrameAssembler? _frameAssembler;
  AdaptiveAudioJitterEstimator? _jitterEstimator;
  Timer? _playoutTimer;
  _PipelineRun? _playoutTimerRun;

  bool get isRunning => _run != null;

  static final Expando<_PcmAudioOutputCoordinator> _outputCoordinators =
      Expando<_PcmAudioOutputCoordinator>('miucamPcmAudioOutputCoordinator');

  static _PcmAudioOutputCoordinator _coordinatorFor(PcmAudioSink output) =>
      _outputCoordinators[output] ??= _PcmAudioOutputCoordinator(output);

  Future<void> start({
    required Uri uri,
    required String pairedServerHost,
    required int pairedServerPort,
    String? bearerToken,
    bool Function(Object error)? shouldRetry,
    VoidCallback? onAudioChunkWritten,
    ValueChanged<ClientLiveAudioStatus>? onStatus,
    ValueChanged<Object>? onError,
  }) async {
    await stop();
    final generation = ++_generation;
    final run = _PipelineRun(
      uri: uri,
      pairedServerHost: pairedServerHost,
      pairedServerPort: pairedServerPort,
      bearerToken: bearerToken,
      shouldRetry: shouldRetry,
      onAudioChunkWritten: onAudioChunkWritten,
      onStatus: onStatus,
      onError: onError,
    );
    _run = run;
    unawaited(_runLoop(generation, run));
  }

  Future<void> stop() async {
    cancelImmediately();
    await _stopAudioOutput();
  }

  /// Invalidates the run and closes network/native playback without waiting
  /// behind a pending platform start operation.
  void cancelImmediately() {
    _generation++;
    _run = null;
    _closeClient();
    _stopPlayoutTimer();
    _buffer = null;
    _frameAssembler = null;
    _jitterEstimator = null;
    final shouldStopOutput = _outputStarted ||
        _audioOutputStartInFlight ||
        _audioOutputOwnerGeneration != null;
    final lease = _audioOutputLease;
    _audioOutputLease = null;
    _audioOutputOwnerGeneration = null;
    _outputStarted = false;
    if (shouldStopOutput && lease != null) {
      late final Future<void> stopOperation;
      stopOperation = _audioOutputCoordinator
          .stop(owner: lease, timeout: connectTimeout)
          .whenComplete(() {
        if (identical(_immediateAudioOutputStop, stopOperation)) {
          _immediateAudioOutputStop = null;
        }
      });
      _immediateAudioOutputStop = stopOperation;
      unawaited(stopOperation);
    }
  }

  Future<void> _runLoop(int generation, _PipelineRun run) async {
    var retryAttempt = 0;
    try {
      while (_isCurrent(generation, run)) {
        try {
          await _connectAndPump(generation, run);
          retryAttempt = 0;
        } catch (error) {
          if (!_isCurrent(generation, run)) return;
          run.lastError = error;
          run.reconnects++;
          run.onError?.call(error);
          _emitStatus(run, 'error');
          if (run.shouldRetry?.call(error) == false) return;
          await Future<void>.delayed(
            _retryPolicy.delayForAttempt(retryAttempt),
          );
          retryAttempt++;
        }
      }
    } finally {
      if (_isCurrent(generation, run)) {
        _run = null;
      }
    }
  }

  Future<void> _connectAndPump(int generation, _PipelineRun run) async {
    _validateUri(run.uri, run.pairedServerHost, run.pairedServerPort);
    _stopPlayoutTimer(run);
    await _stopAudioOutput();
    if (!_isCurrent(generation, run)) return;
    final client = (_clientFactory?.call() ?? HttpClient())
      ..connectionTimeout = connectTimeout;
    _client = client;
    final parser = WavPcmStreamParser();
    _buffer = null;
    _frameAssembler = null;
    _jitterEstimator = null;
    run.connectedAtMs = _nowMs();
    _emitStatus(run, 'connecting');

    try {
      final request = await client.getUrl(run.uri).timeout(connectTimeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'audio/wav, audio/x-wav, application/octet-stream',
      );
      final bearerToken = run.bearerToken;
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      final response = await request.close().timeout(connectTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw ClientLiveAudioHttpException(
          statusCode: response.statusCode,
          uri: run.uri,
        );
      }

      await for (final chunk in response.timeout(readTimeout)) {
        if (!_isCurrent(generation, run)) return;
        run.networkBytesReceived += chunk.length;
        final parsed = parser.add(chunk.asUint8ListView());
        if (!_outputStarted && parsed.isConfigured) {
          run.wavHeaderParsed = true;
          final started = await _startAudioOutput(
            generation: generation,
            run: run,
            sampleRate: parsed.sampleRate,
            channels: parsed.channels,
          );
          if (!started || !_isCurrent(generation, run)) return;
          _buffer = ClientAudioJitterBuffer(
            bytesPerFrame: parsed.channels * 2,
            maxBytes: _bufferBytesFor(
              sampleRate: parsed.sampleRate,
              channels: parsed.channels,
            ),
          );
          _jitterEstimator = AdaptiveAudioJitterEstimator(
            frameDuration: frameDuration,
            minDelay: minPlayoutDelay,
            maxDelay: maxPlayoutDelay,
          );
          run.sampleRate = parsed.sampleRate;
          run.channels = parsed.channels;
          run.playoutFrameBytes = _durationBytesFor(
            duration: frameDuration,
            sampleRate: parsed.sampleRate,
            channels: parsed.channels,
          );
          _frameAssembler = PcmAudioFrameAssembler(
            frameBytes: run.playoutFrameBytes,
          );
          run.targetPlayoutDelayMs = minPlayoutDelay.inMilliseconds;
          _emitStatus(run, 'started');
        }
        if (parsed.pcm16le.isEmpty || !_outputStarted) continue;
        run.pcmChunksParsed++;
        run.pcmBytesParsed += parsed.pcm16le.length;
        final buffer = _buffer;
        if (buffer == null) continue;
        final arrivalMs = _nowMs();
        final frames = _frameAssembler?.add(parsed.pcm16le) ?? const [];
        if (frames.isNotEmpty) {
          final estimator = _jitterEstimator;
          estimator?.observe(
            arrivalMs: arrivalMs,
            mediaDurationMs: frameDuration.inMilliseconds * frames.length,
          );
          run.estimatedJitterMs = estimator?.jitterMs ?? 0;
          run.targetPlayoutDelayMs =
              estimator?.targetDelayMs ?? minPlayoutDelay.inMilliseconds;
        }
        for (final frame in frames) {
          final beforeDropped = buffer.droppedBytes;
          buffer.add(frame);
          final droppedBytes = buffer.droppedBytes - beforeDropped;
          run.droppedBufferBytes += droppedBytes;
          if (droppedBytes > 0) {
            run.droppedBufferFrames +=
                (droppedBytes / max(1, run.playoutFrameBytes)).ceil();
          }
        }
        await _startPlayoutIfReady(generation, run);
      }
      throw HttpException('Audio stream ended', uri: run.uri);
    } finally {
      _stopPlayoutTimer(run);
      if (_client == client) _client = null;
      client.close(force: true);
      await _stopAudioOutput(ownerGeneration: generation);
    }
  }

  Future<void> _startPlayoutIfReady(int generation, _PipelineRun run) async {
    final buffer = _buffer;
    if (buffer == null || _playoutTimer != null) return;
    final startupDelay = Duration(
      milliseconds: max(
        run.targetPlayoutDelayMs,
        nativeQueueTarget.inMilliseconds,
      ),
    );
    final targetBytes = _durationBytesFor(
      duration: startupDelay,
      sampleRate: run.sampleRate ?? 16000,
      channels: run.channels ?? 1,
    );
    if (buffer.bufferedBytes < max(run.playoutFrameBytes, targetBytes)) return;
    run.playoutStarts++;
    if (run.playoutStarts == 1 && run.connectedAtMs != null) {
      final startupMs = _nowMs() - run.connectedAtMs!;
      if (startupMs >= 0 && startupMs <= 120000) {
        MediaSessionTelemetry.shared.recordDurationUs(
          MediaMetricName.audioStartupToPlayout,
          startupMs * Duration.microsecondsPerMillisecond,
        );
      }
    }
    run.nativeQueueUntilUs = 0;
    unawaited(_emitStatus(run, 'playout_started'));
    final pumpInterval = Duration(
      microseconds: max(1000, frameDuration.inMicroseconds ~/ 2),
    );
    _playoutTimer = Timer.periodic(pumpInterval, (_) {
      unawaited(_pumpPlayout(generation, run));
    });
    _playoutTimerRun = run;
    await _pumpPlayout(generation, run);
  }

  Future<void> _pumpPlayout(int generation, _PipelineRun run) async {
    final buffer = _buffer;
    if (buffer == null || run.playoutWriteInFlight) return;
    if (!_isCurrent(generation, run)) {
      _stopPlayoutTimer(run);
      return;
    }

    final nowUs = _nowUs();
    final expiryGraceUs = max(2000, frameDuration.inMicroseconds ~/ 2);
    if (run.nativeQueueUntilUs > 0 &&
        nowUs > run.nativeQueueUntilUs + expiryGraceUs) {
      _stopPlayoutTimer(run);
      run.nativeQueueUntilUs = 0;
      run.playoutUnderruns++;
      MediaSessionTelemetry.shared
          .increment(MediaMetricName.audioUnderrunCount);
      await _emitStatus(run, 'underrun');
      await _startPlayoutIfReady(generation, run);
      return;
    }

    run.playoutWriteInFlight = true;
    try {
      while (_isCurrent(generation, run)) {
        final currentUs = _nowUs();
        final queuedUs = max(0, run.nativeQueueUntilUs - currentUs);
        if (queuedUs >= nativeQueueTarget.inMicroseconds) break;
        final frame = buffer.takeFrame(run.playoutFrameBytes);
        if (frame.isEmpty) break;
        final accepted = await _writeAudioFrame(generation, run, frame);
        if (!accepted) break;
        final acceptedAtUs = _nowUs();
        run.nativeQueueUntilUs = max(run.nativeQueueUntilUs, acceptedAtUs) +
            frameDuration.inMicroseconds;
      }
    } finally {
      run.playoutWriteInFlight = false;
    }
  }

  Future<bool> _writeAudioFrame(
    int generation,
    _PipelineRun run,
    Uint8List frame,
  ) async {
    final startedAtUs = MediaSessionTelemetry.shared.nowUs;
    final lease = _audioOutputLease;
    if (lease == null) return false;
    final accepted = await _audioOutputCoordinator.write(
      owner: lease,
      pcm16le: frame,
    );
    MediaSessionTelemetry.shared.recordDurationUs(
      MediaMetricName.audioOutputWrite,
      MediaSessionTelemetry.shared.nowUs - startedAtUs,
    );
    if (!_isCurrent(generation, run)) return false;
    run.nativeWriteAttempts++;
    run.chunksWritten++;
    run.bytesWritten += frame.length;
    if (accepted) {
      run.nativeWriteCallsAccepted++;
      run.nativeBytesWritten += frame.length;
      run.lastWriteAtMs = _nowMs();
      run.onAudioChunkWritten?.call();
    } else {
      run.nativeWriteCallsDropped++;
      run.droppedNativeWrites++;
    }
    if (run.chunksWritten == 1 || run.chunksWritten % 25 == 0) {
      await _emitStatus(run, 'write');
    }
    return accepted;
  }

  void _stopPlayoutTimer([_PipelineRun? owner]) {
    if (owner != null && !identical(_playoutTimerRun, owner)) return;
    _playoutTimer?.cancel();
    _playoutTimer = null;
    _playoutTimerRun = null;
  }

  int _durationBytesFor({
    required Duration duration,
    required int sampleRate,
    required int channels,
  }) {
    final bytesPerSampleFrame = max(1, channels * 2);
    final raw = sampleRate *
        bytesPerSampleFrame *
        duration.inMicroseconds ~/
        Duration.microsecondsPerSecond;
    final aligned = raw - (raw % bytesPerSampleFrame);
    return max(bytesPerSampleFrame, aligned);
  }

  int _mediaDurationMs(
    int bytes, {
    required int sampleRate,
    required int channels,
  }) {
    if (bytes <= 0) return 0;
    final bytesPerSecond = max(1, sampleRate * channels * 2);
    return max(1, bytes * 1000 ~/ bytesPerSecond);
  }

  Future<void> _emitStatus(_PipelineRun run, String event) async {
    if (!identical(_run, run)) return;
    Map<String, Object?> nativeStatus = const {};
    if (_outputStarted || event == 'error') {
      try {
        final lease = _audioOutputLease;
        if (lease != null) {
          nativeStatus = await _audioOutputCoordinator.status(owner: lease);
        }
      } catch (_) {}
    }
    if (!identical(_run, run)) return;
    final status = ClientLiveAudioStatus(
      event: event,
      connectedAtMs: run.connectedAtMs,
      sampleRate: run.sampleRate,
      channels: run.channels,
      wavHeaderParsed: run.wavHeaderParsed,
      networkBytesReceived: run.networkBytesReceived,
      pcmChunksParsed: run.pcmChunksParsed,
      pcmBytesParsed: run.pcmBytesParsed,
      bytesWritten: run.bytesWritten,
      chunksWritten: run.chunksWritten,
      bufferedBytes: _buffer?.bufferedBytes ?? 0,
      bufferedAudioMs: _mediaDurationMs(
        _buffer?.bufferedBytes ?? 0,
        sampleRate: run.sampleRate ?? 16000,
        channels: run.channels ?? 1,
      ),
      droppedBufferBytes: run.droppedBufferBytes,
      droppedBufferFrames: run.droppedBufferFrames,
      estimatedJitterMs: run.estimatedJitterMs,
      targetPlayoutDelayMs: run.targetPlayoutDelayMs,
      playoutStarts: run.playoutStarts,
      playoutUnderruns: run.playoutUnderruns,
      nativeWriteAttempts: run.nativeWriteAttempts,
      nativeWriteCallsAccepted: run.nativeWriteCallsAccepted,
      nativeWriteCallsDropped: run.nativeWriteCallsDropped,
      nativeBytesWritten: run.nativeBytesWritten,
      nativeStatusBytesWritten: _intFrom(nativeStatus['bytesWritten']),
      droppedNativeWrites: run.droppedNativeWrites,
      reconnects: run.reconnects,
      lastWriteAtMs: run.lastWriteAtMs,
      lastError: run.lastError,
      nativeStatus: nativeStatus,
    );
    run.onStatus?.call(status);
    if (kDebugMode) {
      debugPrint('MiuCam live audio ${status.toJson()}');
    }
  }

  bool _isCurrent(int generation, _PipelineRun run) =>
      generation == _generation && identical(_run, run);

  Future<bool> _startAudioOutput({
    required int generation,
    required _PipelineRun run,
    required int sampleRate,
    required int channels,
  }) =>
      _queueAudioOutputOperation(() async {
        if (!_isCurrent(generation, run)) return false;
        final lease = Object();
        _audioOutputLease = lease;
        _audioOutputStartInFlight = true;
        try {
          await _audioOutputCoordinator.start(
            owner: lease,
            sampleRate: sampleRate,
            channels: channels,
            timeout: connectTimeout,
          );
        } catch (_) {
          if (identical(_audioOutputLease, lease)) {
            _audioOutputLease = null;
          }
          rethrow;
        } finally {
          _audioOutputStartInFlight = false;
        }
        if (!_isCurrent(generation, run)) {
          await _audioOutputCoordinator.stop(
            owner: lease,
            timeout: connectTimeout,
          );
          if (identical(_audioOutputLease, lease)) {
            _audioOutputLease = null;
          }
          return false;
        }
        _audioOutputOwnerGeneration = generation;
        _outputStarted = true;
        return true;
      });

  Future<void> _stopAudioOutput({int? ownerGeneration}) =>
      _queueAudioOutputOperation(() async {
        final immediateStop = _immediateAudioOutputStop;
        if (immediateStop != null) {
          try {
            await immediateStop.timeout(connectTimeout);
          } catch (_) {}
        }
        if (ownerGeneration != null &&
            _audioOutputOwnerGeneration != ownerGeneration) {
          return;
        }
        final lease = _audioOutputLease;
        try {
          if (lease != null) {
            await _audioOutputCoordinator.stop(
              owner: lease,
              timeout: connectTimeout,
            );
          }
        } catch (_) {
        } finally {
          if (ownerGeneration == null ||
              _audioOutputOwnerGeneration == ownerGeneration) {
            if (identical(_audioOutputLease, lease)) {
              _audioOutputLease = null;
            }
            _audioOutputOwnerGeneration = null;
            _outputStarted = false;
          }
        }
      });

  Future<T> _queueAudioOutputOperation<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _audioOutputOperation = _audioOutputOperation.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void _validateUri(Uri uri, String pairedHost, int pairedPort) {
    final allowed = (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host == pairedHost &&
        uri.port == pairedPort;
    if (!allowed) {
      throw StateError('Audio stream host is not the paired server.');
    }
  }

  int _bufferBytesFor({required int sampleRate, required int channels}) {
    final bytesPerSecond = sampleRate * channels * 2;
    return max(2048, bytesPerSecond * maxBufferedAudio.inMilliseconds ~/ 1000);
  }

  void _closeClient() {
    _client?.close(force: true);
    _client = null;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  int _nowUs() => _playoutClock.elapsedMicroseconds;

  int? _intFrom(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class _PcmAudioOutputCoordinator {
  _PcmAudioOutputCoordinator(this._output);

  final PcmAudioSink _output;
  final Set<Object> _cancelledOwners = HashSet<Object>.identity();
  Object? _activeOwner;
  Object? _startingOwner;
  Future<void>? _settlingStart;
  Completer<void>? _settlingCompleter;

  Future<void> start({
    required Object owner,
    required int sampleRate,
    required int channels,
    required Duration timeout,
  }) async {
    await _waitUntilStartSettled(timeout);

    final settle = Completer<void>();
    _settlingCompleter = settle;
    _settlingStart = settle.future;
    _startingOwner = owner;

    final previousOwner = _activeOwner;
    _activeOwner = null;
    if (previousOwner != null && !identical(previousOwner, owner)) {
      await _stopNative(timeout);
    }
    if (_cancelledOwners.contains(owner)) {
      await _stopNative(timeout);
      _finishStart(owner, settle);
      throw StateError('PCM audio output start was cancelled.');
    }

    late final Future<void> nativeStart;
    try {
      nativeStart = _output.start(
        sampleRate: sampleRate,
        channels: channels,
      );
    } catch (_) {
      _finishStart(owner, settle);
      rethrow;
    }

    try {
      await nativeStart.timeout(timeout);
    } on TimeoutException {
      _cancelledOwners.add(owner);
      unawaited(_stopNative(timeout));
      unawaited(_settleLateStart(
        owner: owner,
        operation: nativeStart,
        settle: settle,
        timeout: timeout,
      ));
      rethrow;
    } catch (_) {
      _finishStart(owner, settle);
      rethrow;
    }

    if (_cancelledOwners.contains(owner)) {
      await _stopNative(timeout);
      _finishStart(owner, settle);
      throw StateError('PCM audio output start was cancelled.');
    }
    _activeOwner = owner;
    _finishStart(owner, settle);
  }

  Future<void> stop({
    required Object owner,
    required Duration timeout,
  }) async {
    if (identical(_startingOwner, owner)) {
      _cancelledOwners.add(owner);
      await _stopNative(timeout);
      return;
    }
    if (!identical(_activeOwner, owner)) return;
    _activeOwner = null;
    await _stopNative(timeout);
  }

  Future<bool> write({
    required Object owner,
    required Uint8List pcm16le,
  }) async {
    if (!identical(_activeOwner, owner)) return false;
    return _output.write(pcm16le);
  }

  Future<Map<String, Object?>> status({required Object owner}) async {
    if (!identical(_activeOwner, owner)) return const {};
    return _output.status();
  }

  Future<void> _waitUntilStartSettled(Duration timeout) async {
    while (true) {
      final settling = _settlingStart;
      if (settling == null) return;
      await settling.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'A previous PCM audio output start is still settling.',
          timeout,
        ),
      );
    }
  }

  Future<void> _settleLateStart({
    required Object owner,
    required Future<void> operation,
    required Completer<void> settle,
    required Duration timeout,
  }) async {
    try {
      await operation;
    } catch (_) {
      // The start failed after its caller timed out. The native stop below is
      // still required because platform calls can fail after partial setup.
    }
    await _stopNative(timeout);
    _finishStart(owner, settle);
  }

  Future<void> _stopNative(Duration timeout) async {
    try {
      await _output.stop().timeout(timeout);
    } catch (_) {}
  }

  void _finishStart(Object owner, Completer<void> settle) {
    _cancelledOwners.remove(owner);
    if (identical(_startingOwner, owner)) _startingOwner = null;
    if (identical(_settlingCompleter, settle)) {
      _settlingCompleter = null;
      _settlingStart = null;
    }
    if (!settle.isCompleted) settle.complete();
  }
}

class PcmAudioFrameAssembler {
  PcmAudioFrameAssembler({required this.frameBytes})
      : assert(frameBytes > 0, 'frameBytes must be positive');

  final int frameBytes;
  Uint8List _pending = Uint8List(0);

  int get pendingBytes => _pending.length;

  List<Uint8List> add(Uint8List bytes) {
    if (bytes.isEmpty) return const [];
    final combined = Uint8List(_pending.length + bytes.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + bytes.length, bytes);
    final frameCount = combined.length ~/ frameBytes;
    if (frameCount == 0) {
      _pending = combined;
      return const [];
    }
    final frames = List<Uint8List>.generate(
      frameCount,
      (index) => Uint8List.sublistView(
        combined,
        index * frameBytes,
        (index + 1) * frameBytes,
      ),
      growable: false,
    );
    final consumed = frameCount * frameBytes;
    _pending = consumed == combined.length
        ? Uint8List(0)
        : Uint8List.fromList(Uint8List.sublistView(combined, consumed));
    return frames;
  }

  Uint8List takeRemainder() {
    final remainder = _pending;
    _pending = Uint8List(0);
    return remainder;
  }
}

class ClientAudioJitterBuffer {
  ClientAudioJitterBuffer({
    required this.bytesPerFrame,
    required this.maxBytes,
  });

  final int bytesPerFrame;
  final int maxBytes;
  final _chunks = ListQueue<Uint8List>();
  int _bufferedBytes = 0;
  int droppedBytes = 0;

  int get bufferedBytes => _bufferedBytes;
  bool get hasData => _bufferedBytes > 0;

  void add(Uint8List bytes) {
    final alignedLength = bytes.length - (bytes.length % bytesPerFrame);
    if (alignedLength <= 0) return;
    var aligned = Uint8List.sublistView(bytes, 0, alignedLength);
    final alignedMaxBytes = maxBytes - (maxBytes % bytesPerFrame);
    if (aligned.length > alignedMaxBytes) {
      final keepBytes = max(bytesPerFrame, alignedMaxBytes);
      droppedBytes += aligned.length - keepBytes;
      aligned = Uint8List.sublistView(
        bytes,
        alignedLength - keepBytes,
        alignedLength,
      );
    }
    _chunks.addLast(aligned);
    _bufferedBytes += aligned.length;
    _trimToBudget();
  }

  Uint8List takeNext({required int maxBytes}) {
    if (_chunks.isEmpty) return Uint8List(0);
    final first = _chunks.removeFirst();
    if (first.length <= maxBytes) {
      _bufferedBytes -= first.length;
      return first;
    }

    final alignedMax =
        max(bytesPerFrame, maxBytes - (maxBytes % bytesPerFrame));
    final head = Uint8List.sublistView(first, 0, alignedMax);
    final tail = Uint8List.sublistView(first, alignedMax);
    _chunks.addFirst(tail);
    _bufferedBytes -= head.length;
    return head;
  }

  Uint8List takeFrame(int requestedBytes) {
    final alignedRequested = requestedBytes - (requestedBytes % bytesPerFrame);
    if (alignedRequested <= 0 || _bufferedBytes < alignedRequested) {
      return Uint8List(0);
    }
    final output = Uint8List(alignedRequested);
    var written = 0;
    while (written < alignedRequested && _chunks.isNotEmpty) {
      final first = _chunks.removeFirst();
      final needed = alignedRequested - written;
      final take = min(needed, first.length);
      output.setRange(written, written + take, first);
      written += take;
      _bufferedBytes -= take;
      if (take < first.length) {
        _chunks.addFirst(Uint8List.sublistView(first, take));
      }
    }
    return output;
  }

  void _trimToBudget() {
    while (_bufferedBytes > maxBytes && _chunks.isNotEmpty) {
      final overflow = _bufferedBytes - maxBytes;
      final alignedOverflow =
          max(bytesPerFrame, overflow - (overflow % bytesPerFrame));
      final first = _chunks.first;
      if (first.length <= alignedOverflow) {
        final dropped = _chunks.removeFirst();
        _bufferedBytes -= dropped.length;
        droppedBytes += dropped.length;
      } else {
        _chunks
          ..removeFirst()
          ..addFirst(Uint8List.sublistView(first, alignedOverflow));
        _bufferedBytes -= alignedOverflow;
        droppedBytes += alignedOverflow;
      }
    }
  }
}

/// RFC 3550-style smoothed interarrival variation used to choose a bounded
/// playout target. It reacts to spikes quickly enough for voice while the
/// 1/16 EWMA gain prevents one delayed TCP chunk from causing oscillation.
class AdaptiveAudioJitterEstimator {
  AdaptiveAudioJitterEstimator({
    this.frameDuration = const Duration(milliseconds: 20),
    this.minDelay = const Duration(milliseconds: 60),
    this.maxDelay = const Duration(milliseconds: 220),
  }) : assert(maxDelay >= minDelay);

  final Duration frameDuration;
  final Duration minDelay;
  final Duration maxDelay;
  int? _lastArrivalMs;
  double _jitterMs = 0;

  double get jitterMs => _jitterMs;

  int get targetDelayMs {
    final raw = minDelay.inMilliseconds + 4 * _jitterMs;
    final clamped = raw.clamp(
      minDelay.inMilliseconds.toDouble(),
      maxDelay.inMilliseconds.toDouble(),
    );
    final quantum = max(1, frameDuration.inMilliseconds);
    return (clamped / quantum).ceil() * quantum;
  }

  void observe({required int arrivalMs, required int mediaDurationMs}) {
    final previous = _lastArrivalMs;
    _lastArrivalMs = arrivalMs;
    if (previous == null) return;
    final arrivalSpacingMs = max(0, arrivalMs - previous);
    final variation = (arrivalSpacingMs - max(1, mediaDurationMs)).abs();
    _jitterMs += (variation - _jitterMs) / 16;
  }

  void reset() {
    _lastArrivalMs = null;
    _jitterMs = 0;
  }
}

class ClientLiveAudioStatus {
  const ClientLiveAudioStatus({
    required this.event,
    required this.connectedAtMs,
    required this.sampleRate,
    required this.channels,
    required this.wavHeaderParsed,
    required this.networkBytesReceived,
    required this.pcmChunksParsed,
    required this.pcmBytesParsed,
    required this.bytesWritten,
    required this.chunksWritten,
    required this.bufferedBytes,
    required this.bufferedAudioMs,
    required this.droppedBufferBytes,
    required this.droppedBufferFrames,
    required this.estimatedJitterMs,
    required this.targetPlayoutDelayMs,
    required this.playoutStarts,
    required this.playoutUnderruns,
    required this.nativeWriteAttempts,
    required this.nativeWriteCallsAccepted,
    required this.nativeWriteCallsDropped,
    required this.nativeBytesWritten,
    required this.nativeStatusBytesWritten,
    required this.droppedNativeWrites,
    required this.reconnects,
    required this.lastWriteAtMs,
    required this.lastError,
    required this.nativeStatus,
  });

  final String event;
  final int? connectedAtMs;
  final int? sampleRate;
  final int? channels;
  final bool wavHeaderParsed;
  final int networkBytesReceived;
  final int pcmChunksParsed;
  final int pcmBytesParsed;
  final int bytesWritten;
  final int chunksWritten;
  final int bufferedBytes;
  final int bufferedAudioMs;
  final int droppedBufferBytes;
  final int droppedBufferFrames;
  final double estimatedJitterMs;
  final int targetPlayoutDelayMs;
  final int playoutStarts;
  final int playoutUnderruns;
  final int nativeWriteAttempts;
  final int nativeWriteCallsAccepted;
  final int nativeWriteCallsDropped;
  final int nativeBytesWritten;
  final int? nativeStatusBytesWritten;
  final int droppedNativeWrites;
  final int reconnects;
  final int? lastWriteAtMs;
  final Object? lastError;
  final Map<String, Object?> nativeStatus;

  Map<String, Object?> toJson() => {
        'event': event,
        'connectedAtMs': connectedAtMs,
        'sampleRate': sampleRate,
        'channels': channels,
        'wavHeaderParsed': wavHeaderParsed,
        'networkBytesReceived': networkBytesReceived,
        'pcmChunksParsed': pcmChunksParsed,
        'pcmBytesParsed': pcmBytesParsed,
        'bytesWritten': bytesWritten,
        'chunksWritten': chunksWritten,
        'bufferedBytes': bufferedBytes,
        'bufferedAudioMs': bufferedAudioMs,
        'jitterBufferedBytes': bufferedBytes,
        'droppedBufferBytes': droppedBufferBytes,
        'jitterDroppedBytes': droppedBufferBytes,
        'droppedBufferFrames': droppedBufferFrames,
        'estimatedJitterMs': estimatedJitterMs,
        'targetPlayoutDelayMs': targetPlayoutDelayMs,
        'playoutStarts': playoutStarts,
        'playoutUnderruns': playoutUnderruns,
        'nativeWriteAttempts': nativeWriteAttempts,
        'nativeWriteCallsAccepted': nativeWriteCallsAccepted,
        'nativeWriteCallsDropped': nativeWriteCallsDropped,
        'nativeBytesWritten': nativeBytesWritten,
        'nativeStatusBytesWritten': nativeStatusBytesWritten,
        'droppedNativeWrites': droppedNativeWrites,
        'reconnects': reconnects,
        'lastWriteAtMs': lastWriteAtMs,
        if (lastError != null) 'lastError': lastError.toString(),
        'native': nativeStatus,
      };
}

class _PipelineRun {
  _PipelineRun({
    required this.uri,
    required this.pairedServerHost,
    required this.pairedServerPort,
    required this.bearerToken,
    required this.shouldRetry,
    required this.onAudioChunkWritten,
    required this.onStatus,
    required this.onError,
  });

  final Uri uri;
  final String pairedServerHost;
  final int pairedServerPort;
  final String? bearerToken;
  final bool Function(Object error)? shouldRetry;
  final VoidCallback? onAudioChunkWritten;
  final ValueChanged<ClientLiveAudioStatus>? onStatus;
  final ValueChanged<Object>? onError;

  int? connectedAtMs;
  int? sampleRate;
  int? channels;
  bool wavHeaderParsed = false;
  int networkBytesReceived = 0;
  int pcmChunksParsed = 0;
  int pcmBytesParsed = 0;
  int bytesWritten = 0;
  int chunksWritten = 0;
  int droppedBufferBytes = 0;
  int droppedBufferFrames = 0;
  int playoutFrameBytes = 640;
  double estimatedJitterMs = 0;
  int targetPlayoutDelayMs = 60;
  int playoutStarts = 0;
  int playoutUnderruns = 0;
  int nativeWriteAttempts = 0;
  int nativeWriteCallsAccepted = 0;
  int nativeWriteCallsDropped = 0;
  int nativeBytesWritten = 0;
  int droppedNativeWrites = 0;
  int reconnects = 0;
  int? lastWriteAtMs;
  Object? lastError;
  bool playoutWriteInFlight = false;
  int nativeQueueUntilUs = 0;
}

class ClientLiveAudioHttpException implements Exception {
  const ClientLiveAudioHttpException({
    required this.statusCode,
    required this.uri,
  });

  final int statusCode;
  final Uri uri;

  @override
  String toString() => 'Audio stream failed with HTTP $statusCode ($uri)';
}
