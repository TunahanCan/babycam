import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/bytes/byte_chunk.dart';
import '../../../core/protocol/mimicam_protocol.dart';
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
    required this.audioEnabled,
    required this.onVideoFrame,
    this.healthState,
    this.audioOutput = const PcmAudioOutput(),
    this.videoClientFactory,
    this.audioPipelineFactory,
    this.connectTimeout = const Duration(seconds: 5),
    this.readTimeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(milliseconds: 700),
    this.maxRetryDelay = const Duration(seconds: 4),
    this.onStatus,
    this.onSessionRefreshRequired,
    this.onFatalError,
  });

  final PairingSession session;
  final ActiveStreamSession activeStream;
  final bool audioEnabled;
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
  final ValueChanged<ClientMediaStreamUpdate>? onStatus;
  final Future<void> Function(ClientMediaStreamFailure failure)?
      onSessionRefreshRequired;
  final ValueChanged<ClientMediaStreamFailure>? onFatalError;

  HttpClient? _videoClient;
  ClientLiveAudioPipeline? _audioPipeline;
  bool _started = false;
  bool _terminalHandled = false;
  int _generation = 0;
  int _videoReconnects = 0;
  int _audioReconnects = 0;
  bool _firstVideoFrameSeen = false;
  bool _firstAudioChunkSeen = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final generation = ++_generation;
    healthState?.setWatchActive(true);
    _emit('connecting');
    unawaited(_videoLoop(generation));
    if (audioEnabled) {
      final pipeline = _createAudioPipeline();
      _audioPipeline = pipeline;
      await pipeline.start(
        uri: _audioUri(),
        pairedServerHost: session.host,
        pairedServerPort: session.port,
        bearerToken: session.sessionToken,
        shouldRetry: _shouldRetryAudio,
        onAudioChunkWritten: _markAudioChunkWritten,
        onStatus: (status) {
          if (status.event == 'error') _audioReconnects = status.reconnects;
          _emit('audio_${status.event}');
        },
        onError: _handleAudioError,
      );
    }
  }

  Future<void> stop() async {
    if (!_started && _videoClient == null && _audioPipeline == null) return;
    _started = false;
    _generation++;
    _closeVideoClient();
    final audio = _audioPipeline;
    _audioPipeline = null;
    await audio?.stop();
  }

  Future<void> _videoLoop(int generation) async {
    var nextRetry = retryDelay;
    while (_isCurrent(generation)) {
      try {
        await _connectAndReadVideo(generation);
        nextRetry = retryDelay;
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
        healthState?.markReconnectAttempt();
        _emit('video_reconnecting', failure: failure);
        await Future<void>.delayed(nextRetry);
        nextRetry = Duration(
          milliseconds: min(
            maxRetryDelay.inMilliseconds,
            (nextRetry.inMilliseconds * 1.7).round(),
          ),
        );
      }
    }
  }

  Future<void> _connectAndReadVideo(int generation) async {
    final client = (videoClientFactory?.call() ?? HttpClient())
      ..connectionTimeout = connectTimeout;
    _videoClient = client;
    final parser = MjpegStreamParser();
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
        final frames = parser.add(chunk.asUint8ListView());
        if (frames.isEmpty) continue;
        for (final frame in frames) {
          healthState?.markVideoFrameReceived();
          onVideoFrame(frame);
        }
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
    if (failure.kind == ClientMediaStreamFailureKind.timeout) {
      healthState?.markAudioUnderrun();
    }
    healthState?.markReconnectAttempt();
    _emit('audio_reconnecting', failure: failure);
    return true;
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
        MimiCamProtocolV2.video,
        query: {'streamToken': activeStream.streamToken},
      );

  Uri _audioUri() => ServerEndpointBuilder(session).http(
        MimiCamProtocolV2.audio,
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

  void _closeVideoClient() {
    _videoClient?.close(force: true);
    _videoClient = null;
  }
}
