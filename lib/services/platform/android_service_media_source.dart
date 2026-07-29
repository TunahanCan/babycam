import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../analysis/video/luma_frame.dart';
import '../../core/async/serialized_async_executor.dart';
import '../../features/server/media/server_media_source.dart';

/// Testable port around the Android service-owned media platform channels.
abstract interface class AndroidServiceMediaBridgePort {
  Stream<Object?> get events;

  Future<Map<Object?, Object?>> attach({
    required int jpegQuality,
    required int maxVideoFps,
  });

  Future<Map<Object?, Object?>> setConsumerDemand({
    required bool video,
    required bool audio,
    bool encodeVideo = true,
  });

  Future<Map<Object?, Object?>> setMediaPolicy({
    required int jpegQuality,
    required int maxVideoFps,
  });

  Future<Map<Object?, Object?>> awaitReady({
    required bool video,
    required bool audio,
    required Duration timeout,
  });

  Future<Map<Object?, Object?>> detach();
  Future<Map<Object?, Object?>> snapshot();
  Future<Map<Object?, Object?>> resetDiagnostics();
}

class MethodChannelAndroidServiceMediaBridge
    implements AndroidServiceMediaBridgePort {
  MethodChannelAndroidServiceMediaBridge({
    MethodChannel methodChannel =
        const MethodChannel('miucam/android_service_media'),
    EventChannel eventChannel =
        const EventChannel('miucam/android_service_media_events'),
  })  : _methodChannel = methodChannel,
        _eventChannel = eventChannel;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Stream<Object?> get events =>
      _eventChannel.receiveBroadcastStream().cast<Object?>();

  @override
  Future<Map<Object?, Object?>> attach({
    required int jpegQuality,
    required int maxVideoFps,
  }) =>
      _invokeMap('attach', {
        'jpegQuality': jpegQuality,
        'maxVideoFps': maxVideoFps,
      });

  @override
  Future<Map<Object?, Object?>> setConsumerDemand({
    required bool video,
    required bool audio,
    bool encodeVideo = true,
  }) =>
      _invokeMap('setConsumerDemand', {
        'video': video,
        'audio': audio,
        'encodeVideo': encodeVideo,
      });

  @override
  Future<Map<Object?, Object?>> setMediaPolicy({
    required int jpegQuality,
    required int maxVideoFps,
  }) =>
      _invokeMap('setMediaPolicy', {
        'jpegQuality': jpegQuality,
        'maxVideoFps': maxVideoFps,
      });

  @override
  Future<Map<Object?, Object?>> awaitReady({
    required bool video,
    required bool audio,
    required Duration timeout,
  }) =>
      _invokeMap('awaitReady', {
        'video': video,
        'audio': audio,
        'timeoutMs': timeout.inMilliseconds,
      });

  @override
  Future<Map<Object?, Object?>> detach() => _invokeMap('detach');

  @override
  Future<Map<Object?, Object?>> snapshot() => _invokeMap('snapshot');

  @override
  Future<Map<Object?, Object?>> resetDiagnostics() =>
      _invokeMap('resetDiagnostics');

  Future<Map<Object?, Object?>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final result = await _methodChannel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    return result == null
        ? const <Object?, Object?>{}
        : Map<Object?, Object?>.unmodifiable(result);
  }
}

/// [ServerMediaSource] adapter for the CameraX/AudioRecord engine owned by the
/// Android foreground service.
///
/// This class never starts camera or microphone hardware itself. The existing
/// [PlatformRuntimeContract] publishes exact hardware demand first; this
/// adapter then attaches to the service stream and waits for native readiness.
class AndroidServiceMediaSource extends ServerMediaSource
    implements
        ServerJpegPreviewSource,
        ServerLumaFrameSource,
        ServerMediaPolicySink,
        ServerAudioChunkMetadataSource {
  AndroidServiceMediaSource({
    AndroidServiceMediaBridgePort? bridge,
    this.jpegQuality = 68,
    this.maxVideoFps = 8,
    this.readyTimeout = const Duration(seconds: 8),
    List<Duration> reconnectBackoff = _defaultReconnectBackoff,
  })  : _bridge = bridge ?? MethodChannelAndroidServiceMediaBridge(),
        reconnectBackoff = List<Duration>.unmodifiable(reconnectBackoff) {
    if (jpegQuality < 35 || jpegQuality > 90) {
      throw ArgumentError.value(jpegQuality, 'jpegQuality', 'must be 35..90');
    }
    if (maxVideoFps < 1 || maxVideoFps > 15) {
      throw ArgumentError.value(maxVideoFps, 'maxVideoFps', 'must be 1..15');
    }
    if (readyTimeout < const Duration(milliseconds: 500) ||
        readyTimeout > const Duration(seconds: 15)) {
      throw ArgumentError.value(
        readyTimeout,
        'readyTimeout',
        'must be 500ms..15s',
      );
    }
    if (reconnectBackoff.isEmpty || reconnectBackoff.length > 10) {
      throw ArgumentError.value(
        reconnectBackoff,
        'reconnectBackoff',
        'must contain 1..10 delays',
      );
    }
    if (reconnectBackoff.any(
      (delay) => delay.isNegative || delay > const Duration(seconds: 30),
    )) {
      throw ArgumentError.value(
        reconnectBackoff,
        'reconnectBackoff',
        'delays must be 0ms..30s',
      );
    }
  }

  final AndroidServiceMediaBridgePort _bridge;
  final int jpegQuality;
  final int maxVideoFps;
  final Duration readyTimeout;
  final List<Duration> reconnectBackoff;
  late int _effectiveJpegQuality = jpegQuality;
  late int _effectiveMaxVideoFps = maxVideoFps;

  StreamSubscription<Object?>? _eventSubscription;
  final StreamController<Uint8List> _previewFrames =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<LumaFrame> _lumaFrames =
      StreamController<LumaFrame>.broadcast(sync: true);
  final _operations = SerializedAsyncExecutor();
  ServerVideoFrameSink? _videoSink;
  ServerAudioChunkSink? _audioSink;
  ServerMediaErrorSink? _errorSink;
  bool _attached = false;
  bool _nativeConsumerAttached = false;
  bool _videoDemand = false;
  bool _audioDemand = false;
  bool _videoEncodingDemand = true;
  bool _videoActive = false;
  bool _audioActive = false;
  int _videoFrames = 0;
  int _audioChunks = 0;
  int? _lastVideoFrameAtMs;
  int _lastVideoFrameBytes = 0;
  int? _lastAudioChunkAtMs;
  int _lastAudioChunkBytes = 0;
  ServerAudioChunkMetadata? _currentAudioChunkMetadata;
  int? _lastNativeAudioSequence;
  int? _lastAudioCapturedAtMonoUs;
  bool _audioDiscontinuityPending = true;
  String? _lastError;
  String? _lastNativeStateErrorKey;
  Uint8List? _latestPreviewFrame;
  int _demandGeneration = 0;
  int _eventStreamGeneration = 0;
  int? _reconnectLoopGeneration;
  Timer? _reconnectTimer;
  Completer<bool>? _reconnectDelayCompleter;

  @override
  bool get isActive => _videoActive || _audioActive;

  bool get videoActive => _videoActive;
  bool get audioActive => _audioActive;

  @override
  Uint8List? get latestPreviewFrame => _latestPreviewFrame;

  @override
  Stream<Uint8List> get previewFrames => _previewFrames.stream;

  @override
  Stream<LumaFrame> get lumaFrames => _lumaFrames.stream;

  @override
  ServerAudioChunkMetadata? get currentAudioChunkMetadata =>
      _currentAudioChunkMetadata;

  @override
  ServerMediaSourceSnapshot get snapshot => ServerMediaSourceSnapshot(
        active: isActive,
        videoFrames: _videoFrames,
        audioChunks: _audioChunks,
        lastVideoFrameAtMs: _lastVideoFrameAtMs,
        lastVideoFrameBytes: _lastVideoFrameBytes,
        lastAudioChunkAtMs: _lastAudioChunkAtMs,
        lastAudioChunkBytes: _lastAudioChunkBytes,
        lastError: _lastError,
      );

  Future<Map<Object?, Object?>> nativeSnapshot() => _bridge.snapshot();

  /// Controls expensive JPEG production independently from camera/luma
  /// capture. Motion-only notification demand needs luma frames, not an MJPEG
  /// payload on every analysis frame.
  Future<void> setVideoEncodingDemand(bool enabled) =>
      _operations.run(() async {
        _videoEncodingDemand = enabled;
        if (_attached) {
          await _bridge.setConsumerDemand(
            video: _videoDemand,
            audio: _audioDemand,
            encodeVideo: _videoDemand && enabled,
          );
        }
      });

  @override
  Future<void> applyMediaPolicy({
    required int jpegQuality,
    required int maxVideoFps,
  }) {
    final quality = jpegQuality.clamp(35, this.jpegQuality).toInt();
    final fps = maxVideoFps.clamp(1, this.maxVideoFps).toInt();
    return _operations.run(() => _applyMediaPolicy(quality, fps));
  }

  Future<void> _applyMediaPolicy(int jpegQuality, int maxVideoFps) async {
    _effectiveJpegQuality = jpegQuality;
    _effectiveMaxVideoFps = maxVideoFps;
    if (_attached) {
      await _bridge.setMediaPolicy(
        jpegQuality: jpegQuality,
        maxVideoFps: maxVideoFps,
      );
    }
  }

  @override
  Future<void> reconcile({
    required bool video,
    required bool audio,
    required ServerVideoFrameSink onVideoFrame,
    required ServerAudioChunkSink onAudioChunk,
    ServerMediaErrorSink? onError,
  }) {
    final generation = _beginDemandGeneration();
    return _operations.run(
      () async {
        if (generation != _demandGeneration) return;
        await _applyDemand(
          generation: generation,
          video: video,
          audio: audio,
          onVideoFrame: onVideoFrame,
          onAudioChunk: onAudioChunk,
          onError: onError,
        );
      },
    );
  }

  @override
  Future<void> stop() {
    final generation = _beginDemandGeneration();
    return _operations.run(() async {
      if (generation != _demandGeneration) return;
      await _stopConsumer();
    });
  }

  @override
  void resetDiagnostics() {
    _videoFrames = 0;
    _audioChunks = 0;
    _lastVideoFrameAtMs = null;
    _lastVideoFrameBytes = 0;
    _lastAudioChunkAtMs = null;
    _lastAudioChunkBytes = 0;
    _lastError = null;
    unawaited(_bridge.resetDiagnostics().catchError(
          (Object error, StackTrace stack) => <Object?, Object?>{},
        ));
  }

  Future<void> _applyDemand({
    required int generation,
    required bool video,
    required bool audio,
    required ServerVideoFrameSink onVideoFrame,
    required ServerAudioChunkSink onAudioChunk,
    required ServerMediaErrorSink? onError,
  }) async {
    if (audio != _audioDemand) {
      _resetAudioContinuity();
    }
    _videoSink = onVideoFrame;
    _audioSink = onAudioChunk;
    _errorSink = onError;
    _videoDemand = video;
    _audioDemand = audio;
    if (!video) _latestPreviewFrame = null;
    if (!video && !audio) {
      await _stopConsumer();
      return;
    }

    try {
      await _ensureAttached(generation);
      await _bridge.setConsumerDemand(
        video: video,
        audio: audio,
        encodeVideo: video && _videoEncodingDemand,
      );
      await _bridge.awaitReady(
        video: video,
        audio: audio,
        timeout: readyTimeout,
      );
      if (generation != _demandGeneration || !_attached) {
        throw StateError(
          'Android service media demand changed during native readiness.',
        );
      }
      _videoActive = video;
      _audioActive = audio;
      _lastError = null;
    } catch (error, stack) {
      _recordError(error, stack);
      await _bestEffortDetach();
      rethrow;
    }
  }

  Future<void> _ensureAttached(int generation) async {
    if (_attached) return;
    final eventStreamGeneration = ++_eventStreamGeneration;
    _eventSubscription = _bridge.events.listen(
      _handleNativeEvent,
      onError: (Object error, StackTrace stack) => _recordError(error, stack),
      onDone: () => _handleEventStreamDone(
        demandGeneration: generation,
        eventStreamGeneration: eventStreamGeneration,
      ),
      cancelOnError: false,
    );
    try {
      await _bridge.attach(
        jpegQuality: _effectiveJpegQuality,
        maxVideoFps: _effectiveMaxVideoFps,
      );
      _nativeConsumerAttached = true;
      if (eventStreamGeneration != _eventStreamGeneration) {
        throw StateError(
          'Android service media event stream closed while attaching.',
        );
      }
      _attached = true;
    } catch (_) {
      _eventStreamGeneration += 1;
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      rethrow;
    }
  }

  Future<void> _stopConsumer() async {
    Object? firstError;
    StackTrace? firstStack;
    if (_nativeConsumerAttached) {
      try {
        await _bridge.setConsumerDemand(
          video: false,
          audio: false,
          encodeVideo: false,
        );
      } catch (error, stack) {
        firstError = error;
        firstStack = stack;
      }
      try {
        await _bridge.detach();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    _eventStreamGeneration += 1;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _attached = false;
    _nativeConsumerAttached = false;
    _videoDemand = false;
    _audioDemand = false;
    _videoActive = false;
    _audioActive = false;
    _latestPreviewFrame = null;
    _videoSink = null;
    _audioSink = null;
    _resetAudioContinuity();
    _errorSink = null;
    _lastNativeStateErrorKey = null;
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }

  Future<void> _bestEffortDetach() async {
    try {
      if (_nativeConsumerAttached) {
        await _bridge.setConsumerDemand(
          video: false,
          audio: false,
          encodeVideo: false,
        );
        await _bridge.detach();
      }
    } catch (_) {
      // Preserve the acquisition error that caused cleanup.
    }
    _eventStreamGeneration += 1;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _attached = false;
    _nativeConsumerAttached = false;
    _videoDemand = false;
    _audioDemand = false;
    _videoActive = false;
    _audioActive = false;
    _latestPreviewFrame = null;
    _resetAudioContinuity();
    _lastNativeStateErrorKey = null;
  }

  int _beginDemandGeneration() {
    final generation = ++_demandGeneration;
    _cancelReconnectDelay();
    return generation;
  }

  bool _hasDemandFor(int generation) =>
      generation == _demandGeneration && (_videoDemand || _audioDemand);

  void _handleEventStreamDone({
    required int demandGeneration,
    required int eventStreamGeneration,
  }) {
    if (eventStreamGeneration != _eventStreamGeneration) return;
    _eventStreamGeneration += 1;
    _eventSubscription = null;
    _attached = false;
    _resetMediaContinuity();
    if (!_hasDemandFor(demandGeneration)) return;

    _recordError(
      const ServerMediaStreamDiscontinuity(
        'Android service media event stream closed unexpectedly.',
      ),
      StackTrace.current,
    );
    _startReconnectLoop(demandGeneration);
  }

  void _startReconnectLoop(int generation) {
    if (_reconnectLoopGeneration == generation) return;
    _reconnectLoopGeneration = generation;
    unawaited(_runReconnectLoop(generation));
  }

  Future<void> _runReconnectLoop(int generation) async {
    try {
      var attempt = 0;
      while (_hasDemandFor(generation)) {
        final backoffIndex = min(attempt, reconnectBackoff.length - 1);
        final shouldRetry = await _waitForReconnectDelay(
          reconnectBackoff[backoffIndex],
          generation,
        );
        if (!shouldRetry) return;

        attempt += 1;
        final result = await _operations.run(
          () => _tryReconnect(
            generation: generation,
            attempt: attempt,
          ),
        );
        if (result == _ReconnectResult.succeeded &&
            _hasDemandFor(generation) &&
            !_attached) {
          // The replacement stream may close between native readiness and
          // this loop resuming. Keep this generation's recovery alive.
          continue;
        }
        if (result != _ReconnectResult.failed) return;
      }
    } finally {
      if (_reconnectLoopGeneration == generation) {
        _reconnectLoopGeneration = null;
      }
    }
  }

  Future<bool> _waitForReconnectDelay(
    Duration delay,
    int generation,
  ) async {
    if (!_hasDemandFor(generation)) return false;
    if (delay == Duration.zero) {
      await Future<void>.delayed(Duration.zero);
      return _hasDemandFor(generation);
    }

    final completer = Completer<bool>();
    _reconnectDelayCompleter = completer;
    _reconnectTimer = Timer(delay, () {
      if (!completer.isCompleted) completer.complete(true);
    });
    final elapsed = await completer.future;
    if (identical(_reconnectDelayCompleter, completer)) {
      _reconnectDelayCompleter = null;
      _reconnectTimer = null;
    }
    return elapsed && _hasDemandFor(generation);
  }

  void _cancelReconnectDelay() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final completer = _reconnectDelayCompleter;
    _reconnectDelayCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
  }

  Future<_ReconnectResult> _tryReconnect({
    required int generation,
    required int attempt,
  }) async {
    if (!_hasDemandFor(generation)) return _ReconnectResult.cancelled;
    try {
      await _ensureAttached(generation);
      if (!_hasDemandFor(generation)) {
        await _detachPreservingDemand();
        return _ReconnectResult.cancelled;
      }
      await _bridge.setConsumerDemand(
        video: _videoDemand,
        audio: _audioDemand,
        encodeVideo: _videoDemand && _videoEncodingDemand,
      );
      await _bridge.awaitReady(
        video: _videoDemand,
        audio: _audioDemand,
        timeout: readyTimeout,
      );
      if (!_hasDemandFor(generation)) {
        await _detachPreservingDemand();
        return _ReconnectResult.cancelled;
      }
      if (!_attached) {
        throw StateError(
          'Android service media event stream closed during recovery.',
        );
      }
      _videoActive = _videoDemand;
      _audioActive = _audioDemand;
      _lastError = null;
      _lastNativeStateErrorKey = null;
      return _ReconnectResult.succeeded;
    } catch (error, stack) {
      if (_hasDemandFor(generation)) {
        _recordError(
          StateError(
            'Android service media recovery attempt '
            '$attempt failed: $error',
          ),
          stack,
        );
      }
      await _detachPreservingDemand();
      return _hasDemandFor(generation)
          ? _ReconnectResult.failed
          : _ReconnectResult.cancelled;
    }
  }

  Future<void> _detachPreservingDemand() async {
    try {
      if (_nativeConsumerAttached) {
        await _bridge.setConsumerDemand(
          video: false,
          audio: false,
          encodeVideo: false,
        );
        await _bridge.detach();
      }
    } catch (_) {
      // The retry telemetry already carries the actionable acquisition error.
    }
    _eventStreamGeneration += 1;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _attached = false;
    _nativeConsumerAttached = false;
    _resetMediaContinuity();
    _lastNativeStateErrorKey = null;
  }

  void _resetMediaContinuity() {
    _videoActive = false;
    _audioActive = false;
    _latestPreviewFrame = null;
    _resetAudioContinuity();
  }

  void _handleNativeEvent(Object? rawEvent) {
    if (rawEvent is! Map) return;
    final event = Map<Object?, Object?>.from(rawEvent);
    switch (event['type']) {
      case 'video':
        if (!_videoDemand) return;
        try {
          _emitLumaFrame(event);
        } catch (error, stack) {
          _recordError(error, stack);
        }
        final bytes = _bytes(event['bytes']);
        final sink = _videoSink;
        if (bytes == null || bytes.isEmpty || sink == null) return;
        try {
          _latestPreviewFrame = bytes;
          if (_previewFrames.hasListener) _previewFrames.add(bytes);
          sink(bytes);
          _videoFrames += 1;
          _lastVideoFrameAtMs = _eventTimestamp(event);
          _lastVideoFrameBytes = bytes.length;
        } catch (error, stack) {
          _recordError(error, stack);
        }
        break;
      case 'audio':
        if (!_audioDemand) return;
        final bytes = _bytes(event['bytes']);
        final sink = _audioSink;
        if (bytes == null || bytes.isEmpty || sink == null) return;
        final metadata = _audioMetadata(event, bytes.length);
        try {
          _currentAudioChunkMetadata = metadata;
          sink(bytes);
          _audioChunks += 1;
          _lastAudioChunkAtMs = metadata.capturedAtMs;
          _lastAudioChunkBytes = bytes.length;
        } catch (error, stack) {
          _recordError(error, stack);
        } finally {
          _currentAudioChunkMetadata = null;
        }
        break;
      case 'error':
        final resource = event['resource']?.toString() ?? 'native_media';
        final message = event['message']?.toString() ?? 'unknown error';
        _recordNativeStateError(resource, message);
        break;
      case 'captureState':
        _handleCaptureState(event);
        break;
    }
  }

  void _handleCaptureState(Map<Object?, Object?> event) {
    final previousVideoActive = _videoActive;
    final previousAudioActive = _audioActive;
    final cameraActive = event['cameraActive'] as bool? ?? false;
    final microphoneActive = event['microphoneActive'] as bool? ?? false;
    final cameraError = event['cameraError']?.toString();
    final microphoneError = event['microphoneError']?.toString();

    _videoActive = _videoDemand && cameraActive;
    _audioActive = _audioDemand && microphoneActive;
    if (previousAudioActive != _audioActive) {
      _resetAudioContinuity();
    }
    if (_videoDemand && cameraError != null && cameraError.isNotEmpty) {
      _recordNativeStateError('camera', cameraError);
    } else if (_audioDemand &&
        microphoneError != null &&
        microphoneError.isNotEmpty) {
      _recordNativeStateError('microphone', microphoneError);
    } else if (_videoDemand && previousVideoActive && !_videoActive) {
      _recordNativeStateError('camera', 'capture became inactive');
    } else if (_audioDemand && previousAudioActive && !_audioActive) {
      _recordNativeStateError('microphone', 'capture became inactive');
    } else if ((!_videoDemand || _videoActive) &&
        (!_audioDemand || _audioActive)) {
      _lastNativeStateErrorKey = null;
      _lastError = null;
    }
  }

  void _emitLumaFrame(Map<Object?, Object?> event) {
    if (!_lumaFrames.hasListener) return;
    final bytes = _bytes(event['lumaBytes']);
    final width = (event['lumaWidth'] as num?)?.toInt() ?? 0;
    final height = (event['lumaHeight'] as num?)?.toInt() ?? 0;
    if (bytes == null || width <= 0 || height <= 0) return;
    final requiredBytes = width * height;
    if (bytes.length < requiredBytes) return;
    _lumaFrames.add(LumaFrame(
      yPlane: bytes.length == requiredBytes
          ? bytes
          : Uint8List.sublistView(bytes, 0, requiredBytes),
      width: width,
      height: height,
      rowStride: width,
      pixelStride: 1,
      timestampMs: _eventTimestamp(event),
      monotonicTimestampMs: _eventMonotonicTimestamp(event),
    ));
  }

  void _recordNativeStateError(String resource, String message) {
    final key = '$resource:$message';
    if (_lastNativeStateErrorKey == key) return;
    _lastNativeStateErrorKey = key;
    _recordError(StateError(key), StackTrace.current);
  }

  Uint8List? _bytes(Object? value) => switch (value) {
        Uint8List bytes => bytes,
        ByteData data => data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          ),
        List<int> values => Uint8List.fromList(values),
        _ => null,
      };

  int _eventTimestamp(Map<Object?, Object?> event) =>
      (event['timestampMs'] as num?)?.toInt() ??
      DateTime.now().millisecondsSinceEpoch;

  int? _eventMonotonicTimestamp(Map<Object?, Object?> event) {
    final capturedAtMonoUs = event['capturedAtMonoUs'];
    return capturedAtMonoUs is num ? capturedAtMonoUs.toInt() ~/ 1000 : null;
  }

  ServerAudioChunkMetadata _audioMetadata(
    Map<Object?, Object?> event,
    int byteLength,
  ) {
    final capturedAtMs = _eventTimestamp(event);
    final capturedAtMonoUs = _positiveInt(event['capturedAtMonoUs']);
    final sequence = _positiveInt(event['audioSequence']);
    final sampleRate = _positiveInt(event['sampleRate']);
    final channels = _positiveInt(event['channels']);
    var discontinuityBefore = _audioDiscontinuityPending;

    final lastSequence = _lastNativeAudioSequence;
    if (lastSequence != null &&
        (sequence == null || sequence != lastSequence + 1)) {
      discontinuityBefore = true;
    }

    final lastCapturedAtMonoUs = _lastAudioCapturedAtMonoUs;
    if (lastCapturedAtMonoUs != null && capturedAtMonoUs != null) {
      final durationUs = sampleRate == null || channels == null
          ? 0
          : byteLength * 1000000 ~/ max(1, sampleRate * channels * 2);
      final gapUs = capturedAtMonoUs - durationUs - lastCapturedAtMonoUs;
      if (gapUs.abs() > _maxContinuousAudioGapUs) {
        discontinuityBefore = true;
      }
    }

    _lastNativeAudioSequence = sequence;
    _lastAudioCapturedAtMonoUs = capturedAtMonoUs;
    _audioDiscontinuityPending = false;
    return ServerAudioChunkMetadata(
      capturedAtMs: capturedAtMs,
      capturedAtMonoUs: capturedAtMonoUs,
      sequence: sequence,
      sampleRate: sampleRate,
      channels: channels,
      discontinuityBefore: discontinuityBefore,
    );
  }

  int? _positiveInt(Object? value) {
    if (value is! num) return null;
    final parsed = value.toInt();
    return parsed > 0 ? parsed : null;
  }

  void _resetAudioContinuity() {
    _currentAudioChunkMetadata = null;
    _lastNativeAudioSequence = null;
    _lastAudioCapturedAtMonoUs = null;
    _audioDiscontinuityPending = true;
  }

  void _recordError(Object error, StackTrace stack) {
    _lastError = error.toString();
    try {
      _errorSink?.call(error, stack);
    } catch (_) {
      // Diagnostics must not interrupt capture recovery.
    }
  }
}

const _maxContinuousAudioGapUs = 250000;
const _defaultReconnectBackoff = <Duration>[
  Duration(milliseconds: 100),
  Duration(milliseconds: 200),
  Duration(milliseconds: 400),
  Duration(milliseconds: 800),
  Duration(milliseconds: 1600),
  Duration(milliseconds: 3200),
  Duration(milliseconds: 6400),
  Duration(milliseconds: 12800),
  Duration(seconds: 30),
];

enum _ReconnectResult { succeeded, failed, cancelled }
