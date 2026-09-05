import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/protocol/miucam_protocol.dart';
import '../../../../core/protocol/pairing_session.dart';
import '../../../../core/protocol/server_endpoint_builder.dart';
import '../../../../core/protocol/webrtc_signaling.dart';
import 'webrtc_client_connector.dart';

class FlutterWebRtcClientConnector implements WebRtcClientConnector {
  FlutterWebRtcClientConnector({
    this.negotiationTimeout = const Duration(seconds: 8),
    this.icePollInterval = const Duration(milliseconds: 250),
    this.onLog,
  });

  final Duration negotiationTimeout;
  final Duration icePollInterval;
  final void Function(String message)? onLog;
  final _handles = <_FlutterWebRtcClientMediaHandle>{};
  final _pendingConnections = <_PendingWebRtcConnection>{};
  Future<bool>? _initializeOperation;
  bool _initialized = false;
  bool _available = false;
  bool _disposed = false;

  @override
  bool get isAvailable => _initialized && _available && !_disposed;

  @override
  Future<bool> initialize() {
    if (_disposed) return Future<bool>.value(false);
    if (_initialized) return Future<bool>.value(_available);
    final current = _initializeOperation;
    if (current != null) return current;
    late final Future<bool> operation;
    operation = _initialize().whenComplete(() {
      if (identical(_initializeOperation, operation)) {
        _initializeOperation = null;
      }
    });
    _initializeOperation = operation;
    return operation;
  }

  Future<bool> _initialize() async {
    try {
      final video = await getRtpReceiverCapabilities('video').timeout(
        negotiationTimeout,
      );
      final audio = await getRtpReceiverCapabilities('audio').timeout(
        negotiationTimeout,
      );
      _available =
          _hasCodec(video, 'video/h264') && _hasCodec(audio, 'audio/opus');
      _initialized = true;
    } catch (error) {
      _available = false;
      _initialized = false;
      onLog?.call('WebRTC receiver capability probe failed: $error');
    }
    return _available;
  }

  @override
  Future<WebRtcClientMediaHandle> connect({
    required PairingSession session,
    required String streamToken,
    required bool video,
    required bool audio,
  }) async {
    if (!await initialize() || _disposed) {
      throw const WebRtcNegotiationException(
        'H.264/Opus WebRTC is unavailable on this device.',
      );
    }
    if (!video && !audio) {
      throw const WebRtcNegotiationException('No media track requested.');
    }

    final http = HttpClient()..connectionTimeout = negotiationTimeout;
    final pending = _PendingWebRtcConnection(http: http);
    _pendingConnections.add(pending);
    RTCPeerConnection? connection;
    RTCVideoRenderer? renderer;
    _FlutterWebRtcClientMediaHandle? handle;
    final pendingLocalCandidates = <WebRtcIceCandidateSignal>[];
    String? peerId;
    try {
      connection = await _awaitNativeResource<RTCPeerConnection>(
        createPeerConnection(const {
          'iceServers': <Object>[],
          'sdpSemantics': 'unified-plan',
          'bundlePolicy': 'max-bundle',
          'rtcpMuxPolicy': 'require',
        }),
        (lateConnection) async {
          await _bestEffort(lateConnection.close, negotiationTimeout);
          await _bestEffort(lateConnection.dispose, negotiationTimeout);
        },
      );
      pending
        ..connection = connection
        ..ensureActive();
      final initializingRenderer = RTCVideoRenderer();
      // Transfer ownership only after initialization. Disposing an unfinished
      // renderer can throw before peer cleanup and leave its late texture alive.
      renderer = await _awaitNativeResource<RTCVideoRenderer>(
        initializingRenderer.initialize().then((_) => initializingRenderer),
        (lateRenderer) => _bestEffort(lateRenderer.dispose, negotiationTimeout),
      );
      pending.renderer = renderer;
      pending.ensureActive();

      if (audio) {
        final transceiver = await connection
            .addTransceiver(
              kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
              init: RTCRtpTransceiverInit(
                direction: TransceiverDirection.RecvOnly,
              ),
            )
            .timeout(negotiationTimeout);
        final capabilities = await getRtpReceiverCapabilities('audio').timeout(
          negotiationTimeout,
        );
        await transceiver
            .setCodecPreferences(
              _pilotCodecs(capabilities.codecs ?? const [], 'audio/opus'),
            )
            .timeout(negotiationTimeout);
        pending.ensureActive();
      }
      if (video) {
        final transceiver = await connection
            .addTransceiver(
              kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
              init: RTCRtpTransceiverInit(
                direction: TransceiverDirection.RecvOnly,
              ),
            )
            .timeout(negotiationTimeout);
        final capabilities = await getRtpReceiverCapabilities('video').timeout(
          negotiationTimeout,
        );
        await transceiver
            .setCodecPreferences(
              _pilotCodecs(capabilities.codecs ?? const [], 'video/h264'),
            )
            .timeout(negotiationTimeout);
        pending.ensureActive();
      }

      final connected = Completer<void>();
      connection.onTrack = (event) {
        if (event.streams.isNotEmpty) renderer!.srcObject = event.streams.first;
      };
      connection.onIceCandidate = (candidate) {
        final value = candidate.candidate?.trim();
        if (value == null || value.isEmpty) return;
        final signal = WebRtcIceCandidateSignal(
          candidate: value,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        );
        final resolvedPeerId = peerId;
        if (resolvedPeerId == null) {
          pendingLocalCandidates.add(signal);
        } else {
          unawaited(_sendCandidate(
            http: http,
            session: session,
            streamToken: streamToken,
            peerId: resolvedPeerId,
            candidate: signal,
          ).catchError((Object error) {
            onLog?.call('WebRTC ICE send failed: $error');
          }));
        }
      };
      connection.onConnectionState = (state) {
        handle?._setConnectionState(state);
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
            !connected.isCompleted) {
          connected.complete();
        } else if ((state ==
                    RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) &&
            !connected.isCompleted) {
          connected.completeError(
            WebRtcNegotiationException('WebRTC connection failed: $state'),
          );
        }
      };

      final offer = await connection.createOffer().timeout(negotiationTimeout);
      pending.ensureActive();
      await connection.setLocalDescription(offer).timeout(negotiationTimeout);
      pending.ensureActive();
      final response = await _postJson(
        http: http,
        session: session,
        path: MiuCamProtocolV2.webRtcOffer,
        query: {'streamToken': streamToken},
        body: WebRtcOfferRequest(
          offer: WebRtcSignalDescription(
            sdp: offer.sdp ?? '',
            type: offer.type ?? 'offer',
          ),
          video: video,
          audio: audio,
        ).toJson(),
      );
      pending.ensureActive();
      final answer = WebRtcOfferResponse.fromJson(response);
      peerId = answer.peerId;
      handle = _FlutterWebRtcClientMediaHandle(
        peerId: answer.peerId,
        videoRenderer: renderer,
        connection: connection,
        onClose: () async {
          try {
            await _closeRemote(
              http: http,
              session: session,
              streamToken: streamToken,
              peerId: answer.peerId,
            );
          } finally {
            http.close(force: true);
          }
        },
        onDisposed: (closed) => _handles.remove(closed),
        cleanupTimeout: negotiationTimeout,
      );
      _handles.add(handle);
      pending
        ..handle = handle
        ..connection = null
        ..renderer = null;
      await connection
          .setRemoteDescription(RTCSessionDescription(
            answer.answer.sdp,
            answer.answer.type,
          ))
          .timeout(negotiationTimeout);
      pending.ensureActive();
      for (final candidate in answer.iceCandidates) {
        await connection
            .addCandidate(_toRtcCandidate(candidate))
            .timeout(negotiationTimeout);
        pending.ensureActive();
      }
      for (final candidate in pendingLocalCandidates) {
        await _sendCandidate(
          http: http,
          session: session,
          streamToken: streamToken,
          peerId: answer.peerId,
          candidate: candidate,
        ).timeout(negotiationTimeout);
        pending.ensureActive();
      }
      pendingLocalCandidates.clear();

      final polling = _pollRemoteCandidates(
        http: http,
        session: session,
        streamToken: streamToken,
        peerId: answer.peerId,
        connection: connection,
        connected: connected.future,
      );
      await connected.future.timeout(negotiationTimeout);
      pending.ensureActive();
      unawaited(polling.catchError((Object error) {
        onLog?.call('WebRTC ICE poll stopped: $error');
      }));
      pending.release();
      return handle;
    } catch (error) {
      await pending.cleanup(negotiationTimeout);
      if (error is WebRtcNegotiationException) rethrow;
      throw WebRtcNegotiationException('WebRTC negotiation failed: $error');
    } finally {
      _pendingConnections.remove(pending);
    }
  }

  Future<T> _awaitNativeResource<T>(
    Future<T> operation,
    Future<void> Function(T value) disposeLate,
  ) async {
    try {
      return await operation.timeout(negotiationTimeout);
    } on TimeoutException {
      // Future.timeout does not cancel platform work. Always release native
      // resources that finish after the negotiation has already failed.
      unawaited(operation.then<void>(
        disposeLate,
        onError: (Object _, StackTrace __) {},
      ));
      rethrow;
    }
  }

  Future<void> _pollRemoteCandidates({
    required HttpClient http,
    required PairingSession session,
    required String streamToken,
    required String peerId,
    required RTCPeerConnection connection,
    required Future<void> connected,
  }) async {
    var done = false;
    unawaited(connected.then<void>(
      (_) => done = true,
      onError: (Object _, StackTrace __) => done = true,
    ));
    final deadline = DateTime.now().add(negotiationTimeout);
    while (!done && DateTime.now().isBefore(deadline)) {
      final response = await _getJson(
        http: http,
        session: session,
        path: MiuCamProtocolV2.webRtcIce,
        query: {'streamToken': streamToken, 'peerId': peerId},
      );
      final raw = response['iceCandidates'];
      if (raw is List) {
        for (final value in raw) {
          await connection
              .addCandidate(
                _toRtcCandidate(WebRtcIceCandidateSignal.fromJson(value)),
              )
              .timeout(negotiationTimeout);
        }
      }
      if (!done) await Future<void>.delayed(icePollInterval);
    }
  }

  Future<void> _sendCandidate({
    required HttpClient http,
    required PairingSession session,
    required String streamToken,
    required String peerId,
    required WebRtcIceCandidateSignal candidate,
  }) async {
    await _postJson(
      http: http,
      session: session,
      path: MiuCamProtocolV2.webRtcIce,
      query: {'streamToken': streamToken, 'peerId': peerId},
      body: {'candidate': candidate.toJson()},
    );
  }

  Future<void> _closeRemote({
    required HttpClient http,
    required PairingSession session,
    required String streamToken,
    required String peerId,
  }) async {
    try {
      await _postJson(
        http: http,
        session: session,
        path: MiuCamProtocolV2.webRtcClose,
        query: {'streamToken': streamToken, 'peerId': peerId},
        body: const {},
      );
    } catch (_) {}
  }

  Future<Map<String, Object?>> _postJson({
    required HttpClient http,
    required PairingSession session,
    required String path,
    required Map<String, String> query,
    required Map<String, Object?> body,
  }) async {
    final request = await http
        .postUrl(ServerEndpointBuilder(session).http(path, query: query))
        .timeout(negotiationTimeout);
    request.followRedirects = false;
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${session.sessionToken}');
    request.write(jsonEncode(body));
    return _readJson(await request.close().timeout(negotiationTimeout));
  }

  Future<Map<String, Object?>> _getJson({
    required HttpClient http,
    required PairingSession session,
    required String path,
    required Map<String, String> query,
  }) async {
    final request = await http
        .getUrl(ServerEndpointBuilder(session).http(path, query: query))
        .timeout(negotiationTimeout);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${session.sessionToken}',
    );
    return _readJson(await request.close().timeout(negotiationTimeout));
  }

  Future<Map<String, Object?>> _readJson(HttpClientResponse response) async {
    final body = await utf8.decoder.bind(response).join().timeout(
          negotiationTimeout,
        );
    if (response.statusCode != HttpStatus.ok) {
      throw WebRtcNegotiationException(
        'WebRTC signaling failed (${response.statusCode}): $body',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const WebRtcNegotiationException(
        'WebRTC signaling returned invalid JSON.',
      );
    }
    return Map<String, Object?>.from(decoded);
  }

  @override
  Future<void> cancelPendingConnections() async {
    final pending = _pendingConnections.toList(growable: false);
    // Calling cancel marks every negotiation and force-closes its signaling
    // client synchronously, before this method reaches its first await.
    final cancellations = <Future<void>>[
      for (final connection in pending) connection.cancel(negotiationTimeout),
    ];
    await Future.wait(cancellations);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancelPendingConnections();
    final handles = _handles.toList(growable: false);
    await Future.wait([
      for (final handle in handles)
        _bestEffort(
          handle.close,
          negotiationTimeout,
        ),
    ]);
    _handles.clear();
    _available = false;
  }

  static RTCIceCandidate _toRtcCandidate(WebRtcIceCandidateSignal signal) =>
      RTCIceCandidate(
        signal.candidate,
        signal.sdpMid,
        signal.sdpMLineIndex,
      );

  static bool _hasCodec(RTCRtpCapabilities capabilities, String mimeType) =>
      (capabilities.codecs ?? const []).any(
        (codec) => codec.mimeType.toLowerCase() == mimeType,
      );

  static List<RTCRtpCodecCapability> _pilotCodecs(
    List<RTCRtpCodecCapability> codecs,
    String mimeType,
  ) =>
      codecs
          .where((codec) => codec.mimeType.toLowerCase() == mimeType)
          .toList(growable: false);
}

class _FlutterWebRtcClientMediaHandle
    implements
        WebRtcClientMediaHandle,
        WebRtcClientStatsSource,
        WebRtcClientAudioController {
  _FlutterWebRtcClientMediaHandle({
    required this.peerId,
    required this.videoRenderer,
    required RTCPeerConnection connection,
    required Future<void> Function() onClose,
    required void Function(_FlutterWebRtcClientMediaHandle handle) onDisposed,
    required Duration cleanupTimeout,
  })  : _connection = connection,
        _onClose = onClose,
        _onDisposed = onDisposed,
        _cleanupTimeout = cleanupTimeout;

  @override
  final String peerId;
  @override
  final RTCVideoRenderer videoRenderer;
  final RTCPeerConnection _connection;
  final Future<void> Function() _onClose;
  final void Function(_FlutterWebRtcClientMediaHandle handle) _onDisposed;
  final Duration _cleanupTimeout;
  final _states = StreamController<RTCPeerConnectionState>.broadcast();
  RTCPeerConnectionState _state =
      RTCPeerConnectionState.RTCPeerConnectionStateNew;
  bool _closed = false;
  Future<void>? _closeOperation;

  @override
  RTCPeerConnectionState get connectionState => _state;

  @override
  Stream<RTCPeerConnectionState> get connectionStates => _states.stream;

  void _setConnectionState(RTCPeerConnectionState state) {
    if (_closed) return;
    _state = state;
    _states.add(state);
  }

  @override
  Future<WebRtcClientStatsSnapshot> collectStats() async {
    final reports = await _connection.getStats();
    final codecs = <String, String>{};
    for (final report in reports) {
      if (report.type != 'codec') continue;
      final mimeType = report.values['mimeType']?.toString();
      if (mimeType != null && mimeType.isNotEmpty) codecs[report.id] = mimeType;
    }
    var videoBytes = 0;
    var audioBytes = 0;
    var framesDecoded = 0;
    var framesDropped = 0;
    var packetsReceived = 0;
    var packetsLost = 0;
    double? jitterMs;
    double? jitterBufferDelayMs;
    String? videoCodec;
    String? audioCodec;
    for (final report in reports) {
      if (report.type != 'inbound-rtp') continue;
      final values = report.values;
      final kind = (values['kind'] ?? values['mediaType'])?.toString();
      final bytes = _intStat(values['bytesReceived']);
      packetsReceived += _intStat(values['packetsReceived']);
      packetsLost += _intStat(values['packetsLost']);
      final reportJitter = _doubleStat(values['jitter']);
      if (reportJitter != null) jitterMs = reportJitter * 1000;
      final emitted = _doubleStat(values['jitterBufferEmittedCount']);
      final delay = _doubleStat(values['jitterBufferDelay']);
      if (emitted != null && emitted > 0 && delay != null) {
        jitterBufferDelayMs = delay * 1000 / emitted;
      }
      final codec = codecs[values['codecId']?.toString()];
      if (kind == 'video') {
        videoBytes += bytes;
        framesDecoded += _intStat(values['framesDecoded']);
        framesDropped += _intStat(values['framesDropped']);
        videoCodec ??= codec;
      } else if (kind == 'audio') {
        audioBytes += bytes;
        audioCodec ??= codec;
      }
    }
    return WebRtcClientStatsSnapshot(
      videoBytesReceived: videoBytes,
      audioBytesReceived: audioBytes,
      videoFramesDecoded: framesDecoded,
      videoFramesDropped: framesDropped,
      packetsReceived: packetsReceived,
      packetsLost: packetsLost,
      jitterMs: jitterMs,
      jitterBufferDelayMs: jitterBufferDelayMs,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      measuredAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> setAudioEnabled(bool enabled) async {
    for (final receiver in await _connection.getReceivers()) {
      final track = receiver.track;
      if (track?.kind == 'audio') track!.enabled = enabled;
    }
  }

  @override
  Future<void> close() {
    final current = _closeOperation;
    if (current != null) return current;
    if (_closed) return Future<void>.value();
    _closed = true;
    _connection.onTrack = null;
    _connection.onIceCandidate = null;
    _connection.onConnectionState = null;
    Object? detachError;
    StackTrace? detachStackTrace;
    try {
      videoRenderer.srcObject = null;
    } catch (error, stackTrace) {
      detachError = error;
      detachStackTrace = stackTrace;
    }
    final operation = _closeResources(
      detachError: detachError,
      detachStackTrace: detachStackTrace,
    );
    _closeOperation = operation;
    return operation;
  }

  Future<void> _closeResources({
    Object? detachError,
    StackTrace? detachStackTrace,
  }) async {
    Object? firstError = detachError;
    StackTrace? firstStackTrace = detachStackTrace;
    Future<void> attempt(Future<void> Function() operation) async {
      try {
        await Future<void>.sync(operation).timeout(_cleanupTimeout);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    // Remote signaling is best-effort and must never hold the renderer or
    // native peer alive. Attach error handling immediately, then tear local
    // resources down in their required order.
    final remoteClose = attempt(_onClose);
    await attempt(_connection.close);
    await attempt(_connection.dispose);
    await attempt(videoRenderer.dispose);
    await attempt(_states.close);
    await remoteClose;
    try {
      _onDisposed(this);
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, firstStackTrace ?? StackTrace.current);
    }
  }

  static int _intStat(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _doubleStat(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _PendingWebRtcConnection {
  _PendingWebRtcConnection({required this.http});

  final HttpClient http;
  RTCPeerConnection? connection;
  RTCVideoRenderer? renderer;
  _FlutterWebRtcClientMediaHandle? handle;
  bool _cancelled = false;
  Future<void>? _cleanupOperation;

  void ensureActive() {
    if (_cancelled) {
      throw const WebRtcNegotiationException(
        'WebRTC negotiation was cancelled.',
      );
    }
  }

  Future<void> cancel(Duration timeout) {
    _cancelled = true;
    http.close(force: true);
    return cleanup(timeout);
  }

  Future<void> cleanup(Duration timeout) {
    final current = _cleanupOperation;
    if (current != null) return current;
    late final Future<void> operation;
    operation = _cleanup(timeout).whenComplete(() {
      if (identical(_cleanupOperation, operation)) {
        _cleanupOperation = null;
      }
    });
    _cleanupOperation = operation;
    return operation;
  }

  Future<void> _cleanup(Duration timeout) async {
    http.close(force: true);
    final pendingHandle = handle;
    handle = null;
    final pendingConnection = connection;
    connection = null;
    final pendingRenderer = renderer;
    renderer = null;

    if (pendingHandle != null) {
      await _bestEffort(pendingHandle.close, timeout);
      return;
    }

    if (pendingConnection != null) {
      pendingConnection.onTrack = null;
      pendingConnection.onIceCandidate = null;
      pendingConnection.onConnectionState = null;
    }
    if (pendingRenderer != null) pendingRenderer.srcObject = null;
    if (pendingConnection != null) {
      await _bestEffort(pendingConnection.close, timeout);
      await _bestEffort(pendingConnection.dispose, timeout);
    }
    if (pendingRenderer != null) {
      await _bestEffort(pendingRenderer.dispose, timeout);
    }
  }

  void release() {
    handle = null;
    connection = null;
    renderer = null;
  }
}

Future<void> _bestEffort(
  Future<void> Function() operation,
  Duration timeout,
) async {
  try {
    await Future<void>.sync(operation).timeout(timeout);
  } catch (_) {}
}
