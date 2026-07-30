import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/bytes/byte_chunk.dart';
import '../../../core/async/serialized_async_executor.dart';
import '../../../core/media/media_session_telemetry.dart';
import '../../../core/network/retry_policy.dart';
import '../../../core/protocol/miucam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import 'active_stream_session.dart';
import 'client_live_audio_pipeline.dart';
import 'client_stream_health_state.dart';
import 'mjpeg_stream_parser.dart';
import 'pcm_audio_output.dart';

enum ClientMediaStreamFailureKind {
  unauthorized,
  clientLimit,
  timeout,
  http,
  network,
}

class ClientMediaStreamFailure implements Exception {
  const ClientMediaStreamFailure({
    required this.kind,
    required this.message,
    this.statusCode,
    this.uri,
    this.cause,
  });

  final ClientMediaStreamFailureKind kind;
  final String message;
  final int? statusCode;
  final Uri? uri;
  final Object? cause;

  bool get shouldRefreshSession =>
      kind == ClientMediaStreamFailureKind.unauthorized;

  bool get isTerminal =>
      kind == ClientMediaStreamFailureKind.unauthorized ||
      kind == ClientMediaStreamFailureKind.clientLimit;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' HTTP $statusCode';
    final target = uri == null ? '' : ' ($uri)';
    return '$message$code$target';
  }
}

class ClientMediaStreamUpdate {
  const ClientMediaStreamUpdate({
    required this.event,
    this.failure,
    this.videoReconnects = 0,
    this.audioReconnects = 0,
    this.firstVideoFrameSeen = false,
    this.firstAudioChunkSeen = false,
  });

  final String event;
  final ClientMediaStreamFailure? failure;
  final int videoReconnects;
  final int audioReconnects;
  final bool firstVideoFrameSeen;
  final bool firstAudioChunkSeen;
}

class ClientMediaStreamSupervisor {
  ClientMediaStreamSupervisor({
    required this.session,
    required this.activeStream,
    required bool audioEnabled,
    required this.onVideoFrame,
    this.healthState,
    this.audioOutput = const PcmAudioOutput(),
    this.videoClientFactory,
    this.audioPipelineFactory,
    this.connectTimeout = const Duration(seconds: 5),
    this.readTimeout = const Duration(seconds: 3),
    this.retryDelay = const Duration(milliseconds: 700),
    this.maxRetryDelay = const Duration(seconds: 4),
    RetryPolicy? retryPolicy,
    this.onStatus,
    this.onSessionRefreshRequired,
    this.onFatalError,
  })  : _audioEnabled = audioEnabled,
        _retryPolicy = retryPolicy ??
            ExponentialBackoffPolicy(
              initialDelay: retryDelay,
              maxDelay: maxRetryDelay,
            );

  final PairingSession session;
  final ActiveStreamSession activeStream;
  final ValueChanged<Uint8List> onVideoFrame;
  final ClientStreamHealthState? healthState;
  final PcmAudioSink audioOutput;
  final HttpClient Function()? videoClientFactory;
  final ClientLiveAudioPipeline Function(PcmAudioSink audioOutput)?
      audioPipelineFactory;
  final Duration connectTimeout;
  final Duration readTimeout;
  final Duration retryDelay;
  final Duration maxRetryDelay;
  final RetryPolicy _retryPolicy;
  final ValueChanged<ClientMediaStreamUpdate>? onStatus;
  final Future<void> Function(ClientMediaStreamFailure failure)?
      onSessionRefreshRequired;
  final ValueChanged<ClientMediaStreamFailure>? onFatalError;
  final _audioOperations = SerializedAsyncExecutor();
  final Set<Future<void>> _detachedAudioStops = {};

  HttpClient? _videoClient;
  ClientLiveAudioPipeline? _audioPipeline;
  bool _audioEnabled;
  bool _started = false;
  bool _terminalHandled = false;
  int _generation = 0;
  int _videoReconnects = 0;
  int _audioReconnects = 0;
  bool _firstVideoFrameSeen = false;
  bool _firstAudioChunkSeen = false;
  int? _lastVideoSequence;
  final _videoTransitEstimator = VideoTransitEstimator();

  bool get audioEnabled => _audioEnabled;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final generation = ++_generation;
    _lastVideoSequence = null;
    healthState?.setWatchActive(true);
    healthState?.setAudioExpected(_audioEnabled);
    _emit('connecting');
    unawaited(_videoLoop(generation));
    if (_audioEnabled) {
      await _audioOperations.run(() => _startAudioPipeline(generation));
    }
  }

  Future<void> setAudioEnabled(bool enabled) => _audioOperations.run(() async {
        if (_audioEnabled == enabled &&
            (enabled ? _audioPipeline != null : _audioPipeline == null)) {
          return;
        }
        _audioEnabled = enabled;
        healthState?.setAudioExpected(enabled);
        if (!_started) return;
        if (enabled) {
          await _startAudioPipeline(_generation);
        } else {
          await _stopAudioPipeline();
        }
      });

  Future<void> _startAudioPipeline(int generation) async {
    if (!_isCurrent(generation) || _audioPipeline != null) return;
    final pipeline = _createAudioPipeline();
    _audioPipeline = pipeline;
    await pipeline.start(
      uri: _audioUri(),
      pairedServerHost: session.host,
      pairedServerPort: session.port,
      bearerToken: session.sessionToken,
      shouldRetry: (error) {
        if (!_isCurrentAudioPipeline(generation, pipeline)) return false;
        return _shouldRetryAudio(error);
      },
      onAudioChunkWritten: () {
        if (!_isCurrentAudioPipeline(generation, pipeline)) return;
        _markAudioChunkWritten();
      },
      onStatus: (status) {
        if (!_isCurrentAudioPipeline(generation, pipeline)) return;
        healthState?.updateAudioPipelineStatus(status.toJson());
        if (status.event == 'error') _audioReconnects = status.reconnects;
        _emit('audio_${status.event}');
      },
      onError: (error) {
        if (!_isCurrentAudioPipeline(generation, pipeline)) return;
        _handleAudioError(error);
      },
    );
    if (!_isCurrentAudioPipeline(generation, pipeline)) {
      pipeline.cancelImmediately();
      await pipeline.stop();
    }
  }

  Future<void> _stopAudioPipeline() async {
    final audio = _audioPipeline;
    _audioPipeline = null;
    await audio?.stop();
  }

  Future<void> stop() async {
    if (!_started &&
        _videoClient == null &&
        _audioPipeline == null &&
        _detachedAudioStops.isEmpty) {
      return;
    }
    final audio = _detachLocalTransports();
    if (audio != null) _trackDetachedAudioStop(audio);
    final pendingStops = List<Future<void>>.from(_detachedAudioStops);
    if (pendingStops.isNotEmpty) await Future.wait(pendingStops);
  }

  /// Stops socket reads and native audio eagerly for lifecycle teardown.
  ///
  /// The asynchronous [stop] remains useful for callers that can await full
  /// cleanup, while this method guarantees that pausing does not depend on a
  /// later widget frame or an already queued audio start operation.
  void cancelImmediately() {
    final audio = _detachLocalTransports();
    if (audio != null) _trackDetachedAudioStop(audio);
  }

  ClientLiveAudioPipeline? _detachLocalTransports() {
    _started = false;
    _generation++;
    healthState?.setAudioExpected(false);
    healthState?.setWatchActive(false);
    _closeVideoClient();
    final audio = _audioPipeline;
    _audioPipeline = null;
    audio?.cancelImmediately();
    return audio;
  }

  void _trackDetachedAudioStop(ClientLiveAudioPipeline audio) {
    late final Future<void> operation;
    operation = audio.stop().catchError((_) {}).whenComplete(() {
      _detachedAudioStops.remove(operation);
    });
    _detachedAudioStops.add(operation);
  }

  Future<void> _videoLoop(int generation) async {
    var retryAttempt = 0;
    while (_isCurrent(generation)) {
      try {
        await _connectAndReadVideo(generation);
        retryAttempt = 0;
      } catch (error) {
        if (!_isCurrent(generation)) return;
        final failure = _classify(error);
        if (failure.isTerminal) {
          _handleTerminalFailure(failure);
          return;
        }
        if (failure.kind == ClientMediaStreamFailureKind.timeout) {
          healthState?.markStreamTimeout();
        }
        _videoReconnects++;
        MediaSessionTelemetry.shared.increment(MediaMetricName.reconnectCount);
        healthState?.markReconnectAttempt();
        _emit('video_reconnecting', failure: failure);
        await Future<void>.delayed(
          _retryPolicy.delayForAttempt(retryAttempt),
        );
        retryAttempt++;
      }
    }
  }

  Future<void> _connectAndReadVideo(int generation) async {
    final client = (videoClientFactory?.call() ?? HttpClient())
      ..connectionTimeout = connectTimeout;
    _videoClient = client;
    final parser = MjpegStreamParser();
    _videoTransitEstimator.reset();
    final uri = _videoUri();
    try {
      final request = await client.getUrl(uri).timeout(connectTimeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'multipart/x-mixed-replace, image/jpeg',
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.sessionToken}',
      );
      final response = await request.close().timeout(connectTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw _failureForStatus(response.statusCode, uri);
      }

      await for (final chunk in response.timeout(readTimeout)) {
        if (!_isCurrent(generation)) return;
        final frames = parser.addFrames(chunk.asUint8ListView());
        if (frames.isEmpty) continue;
        final latest = frames.last;
        final coalescedFrames = frames.length - 1;
        if (coalescedFrames > 0) {
          healthState?.markVideoFramesCoalesced(coalescedFrames);
          MediaSessionTelemetry.shared.increment(
            MediaMetricName.videoCoalescedPresentationCount,
            coalescedFrames,
          );
        }

        // HTTP/TCP may combine several complete MJPEG parts in one chunk. Walk
        // every sequence number so those locally coalesced frames are not
        // mistaken for frames that disappeared before reaching the client.
        var sequenceCursor = _lastVideoSequence;
        var missingSequenceFrames = 0;
        for (final frame in frames) {
          final sequence = frame.sequence;
          if (sequence == null) continue;
          if (sequenceCursor != null && sequence > sequenceCursor + 1) {
            missingSequenceFrames += sequence - sequenceCursor - 1;
          }
          sequenceCursor = sequence;
        }
        _lastVideoSequence = sequenceCursor;
        if (missingSequenceFrames > 0) {
          healthState?.markVideoFramesSkipped(missingSequenceFrames);
          MediaSessionTelemetry.shared.increment(
            MediaMetricName.videoSkippedTransportCount,
            missingSequenceFrames,
          );
        }
        final arrivedAtMs = DateTime.now().millisecondsSinceEpoch;
        final sentAtMs = latest.sentAtMs;
        if (sentAtMs != null) {
          _videoTransitEstimator.observe(
            sentAtMs: sentAtMs,
            arrivedAtMs: arrivedAtMs,
          );
          _recordWallClockDuration(
            MediaMetricName.videoNetworkTransit,
            startedAtMs: sentAtMs,
            endedAtMs: arrivedAtMs,
          );
          healthState?.updateVideoTransport(
            jitterMs: _videoTransitEstimator.jitterMs,
            queueDelayMs: _videoTransitEstimator.queueDelayMs,
          );
        }
        final capturedAtMs = latest.capturedAtMs;
        if (capturedAtMs != null) {
          _recordWallClockDuration(
            MediaMetricName.videoCaptureToReceive,
            startedAtMs: capturedAtMs,
            endedAtMs: arrivedAtMs,
          );
        }
        healthState?.markVideoFrameReceived();
        onVideoFrame(latest.jpeg);
        if (!_firstVideoFrameSeen) {
          _firstVideoFrameSeen = true;
          _emit('first_video_frame');
        } else {
          _emit('video_frame');
        }
      }
      throw HttpException('Video stream ended', uri: uri);
    } finally {
      if (_videoClient == client) _videoClient = null;
      client.close(force: true);
    }
  }

  void _markAudioChunkWritten() {
    healthState?.markAudioChunkReceived();
    if (!_firstAudioChunkSeen) {
      _firstAudioChunkSeen = true;
      _emit('first_audio_chunk');
      return;
    }
    _emit('audio_chunk');
  }

  void _handleAudioError(Object error) {
    final failure = _classify(error);
    if (failure.isTerminal) _handleTerminalFailure(failure);
  }

  bool _shouldRetryAudio(Object error) {
    final failure = _classify(error);
    if (failure.isTerminal) return false;
    _audioReconnects++;
    MediaSessionTelemetry.shared.increment(MediaMetricName.reconnectCount);
    if (failure.kind == ClientMediaStreamFailureKind.timeout) {
      healthState?.markAudioUnderrun();
    }
    healthState?.markReconnectAttempt();
    _emit('audio_reconnecting', failure: failure);
    return true;
  }

  void _recordWallClockDuration(
    String metric, {
    required int startedAtMs,
    required int endedAtMs,
  }) {
    final durationMs = endedAtMs - startedAtMs;
    // Cross-device clocks may not be synchronized. Reject impossible samples
    // instead of corrupting percentiles; relative transit jitter remains
    // available through VideoTransitEstimator in that case.
    if (durationMs < 0 || durationMs > 120000) return;
    MediaSessionTelemetry.shared.recordDurationUs(
      metric,
      durationMs * Duration.microsecondsPerMillisecond,
    );
  }

  void _handleTerminalFailure(ClientMediaStreamFailure failure) {
    if (_terminalHandled) return;
    _terminalHandled = true;
    _emit('terminal_failure', failure: failure);
    if (failure.shouldRefreshSession) {
      final refresh = onSessionRefreshRequired;
      if (refresh != null) unawaited(refresh(failure));
    } else {
      onFatalError?.call(failure);
    }
    unawaited(stop());
  }

  ClientMediaStreamFailure _classify(Object error) {
    if (error is ClientMediaStreamFailure) return error;
    if (error is ClientLiveAudioHttpException) {
      return _failureForStatus(error.statusCode, error.uri, cause: error);
    }
    if (error is TimeoutException) {
      return ClientMediaStreamFailure(
        kind: ClientMediaStreamFailureKind.timeout,
        message: 'Media stream timed out.',
        cause: error,
      );
    }
    if (error is HttpException) {
      return ClientMediaStreamFailure(
        kind: ClientMediaStreamFailureKind.network,
        message: error.message,
        uri: error.uri,
        cause: error,
      );
    }
    return ClientMediaStreamFailure(
      kind: ClientMediaStreamFailureKind.network,
      message: 'Media stream failed.',
      cause: error,
    );
  }

  ClientMediaStreamFailure _failureForStatus(
    int statusCode,
    Uri uri, {
    Object? cause,
  }) {
    if (statusCode == HttpStatus.unauthorized ||
        statusCode == HttpStatus.forbidden) {
      return ClientMediaStreamFailure(
        kind: ClientMediaStreamFailureKind.unauthorized,
        message: 'Media stream authorization expired.',
        statusCode: statusCode,
        uri: uri,
        cause: cause,
      );
    }
    if (statusCode == HttpStatus.tooManyRequests) {
      return ClientMediaStreamFailure(
        kind: ClientMediaStreamFailureKind.clientLimit,
        message: 'Active watcher limit reached.',
        statusCode: statusCode,
        uri: uri,
        cause: cause,
      );
    }
    return ClientMediaStreamFailure(
      kind: ClientMediaStreamFailureKind.http,
      message: 'Media stream request failed.',
      statusCode: statusCode,
      uri: uri,
      cause: cause,
    );
  }

  ClientLiveAudioPipeline _createAudioPipeline() {
    final factory = audioPipelineFactory;
    if (factory != null) return factory(audioOutput);
    return ClientLiveAudioPipeline(
      audioOutput: audioOutput,
      connectTimeout: connectTimeout,
      readTimeout: readTimeout,
      retryDelay: retryDelay,
      maxRetryDelay: maxRetryDelay,
    );
  }

  Uri _videoUri() => ServerEndpointBuilder(session).http(
        MiuCamProtocolV2.video,
        query: {'streamToken': activeStream.streamToken},
      );

  Uri _audioUri() => ServerEndpointBuilder(session).http(
        MiuCamProtocolV2.audio,
        query: {'streamToken': activeStream.streamToken},
      );

  void _emit(String event, {ClientMediaStreamFailure? failure}) {
    onStatus?.call(ClientMediaStreamUpdate(
      event: event,
      failure: failure,
      videoReconnects: _videoReconnects,
      audioReconnects: _audioReconnects,
      firstVideoFrameSeen: _firstVideoFrameSeen,
      firstAudioChunkSeen: _firstAudioChunkSeen,
    ));
  }

  bool _isCurrent(int generation) => _started && generation == _generation;

  bool _isCurrentAudioPipeline(
    int generation,
    ClientLiveAudioPipeline pipeline,
  ) =>
      _isCurrent(generation) && identical(_audioPipeline, pipeline);

  void _closeVideoClient() {
    _videoClient?.close(force: true);
    _videoClient = null;
  }
}
