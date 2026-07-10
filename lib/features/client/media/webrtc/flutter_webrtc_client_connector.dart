import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/protocol/mimicam_protocol.dart';
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
  bool _initialized = false;
  bool _available = false;
  bool _disposed = false;

  @override
  bool get isAvailable => _initialized && _available && !_disposed;

  @override
  Future<bool> initialize() async {
    if (_disposed) return false;
    if (_initialized) return _available;
    _initialized = true;
    try {
      final video = await getRtpReceiverCapabilities('video');
      final audio = await getRtpReceiverCapabilities('audio');
      _available =
          _hasCodec(video, 'video/h264') && _hasCodec(audio, 'audio/opus');
    } catch (error) {
      _available = false;
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
    if (!await initialize()) {
      throw const WebRtcNegotiationException(
        'H.264/Opus WebRTC is unavailable on this device.',
      );
    }
    if (!video && !audio) {
      throw const WebRtcNegotiationException('No media track requested.');
    }

    final http = HttpClient()..connectionTimeout = negotiationTimeout;
    RTCPeerConnection? connection;
    RTCVideoRenderer? renderer;
    _FlutterWebRtcClientMediaHandle? handle;
    final pendingLocalCandidates = <WebRtcIceCandidateSignal>[];
    String? peerId;
    try {
      connection = await createPeerConnection(
        const {
          'iceServers': <Object>[],
          'sdpSemantics': 'unified-plan',
          'bundlePolicy': 'max-bundle',
          'rtcpMuxPolicy': 'require',
        },
      );
      renderer = RTCVideoRenderer();
      await renderer.initialize();

      if (audio) {
        final transceiver = await connection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.RecvOnly,
          ),
        );
        final capabilities = await getRtpReceiverCapabilities('audio');
        await transceiver.setCodecPreferences(
          _preferredFirst(capabilities.codecs ?? const [], 'audio/opus'),
        );
      }
      if (video) {
        final transceiver = await connection.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.RecvOnly,
          ),
        );
        final capabilities = await getRtpReceiverCapabilities('video');
        await transceiver.setCodecPreferences(
          _preferredFirst(capabilities.codecs ?? const [], 'video/h264'),
        );
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

      final offer = await connection.createOffer();
      await connection.setLocalDescription(offer);
      final response = await _postJson(
        http: http,
        session: session,
        path: MimiCamProtocolV2.webRtcOffer,
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
      final answer = WebRtcOfferResponse.fromJson(response);
      peerId = answer.peerId;
      handle = _FlutterWebRtcClientMediaHandle(
        peerId: answer.peerId,
        videoRenderer: renderer,
        connection: connection,
        onClose: () async {
          await _closeRemote(
            http: http,
            session: session,
            streamToken: streamToken,
            peerId: answer.peerId,
          );
          http.close(force: true);
        },
        onDisposed: (closed) => _handles.remove(closed),
      );
      _handles.add(handle);
      await connection.setRemoteDescription(RTCSessionDescription(
        answer.answer.sdp,
        answer.answer.type,
      ));
      for (final candidate in answer.iceCandidates) {
        await connection.addCandidate(_toRtcCandidate(candidate));
      }
      for (final candidate in pendingLocalCandidates) {
        await _sendCandidate(
          http: http,
          session: session,
          streamToken: streamToken,
          peerId: answer.peerId,
          candidate: candidate,
        );
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
      unawaited(polling.catchError((Object error) {
        onLog?.call('WebRTC ICE poll stopped: $error');
      }));
      return handle;
    } catch (error) {
      if (handle != null) {
        await handle.close();
      } else {
        await connection?.close();
        await connection?.dispose();
        await renderer?.dispose();
        http.close(force: true);
      }
      if (error is WebRtcNegotiationException) rethrow;
      throw WebRtcNegotiationException('WebRTC negotiation failed: $error');
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
    unawaited(connected.whenComplete(() => done = true));
    final deadline = DateTime.now().add(negotiationTimeout);
    while (!done && DateTime.now().isBefore(deadline)) {
      final response = await _getJson(
        http: http,
        session: session,
        path: MimiCamProtocolV2.webRtcIce,
        query: {'streamToken': streamToken, 'peerId': peerId},
      );
      final raw = response['iceCandidates'];
      if (raw is List) {
        for (final value in raw) {
          await connection.addCandidate(
            _toRtcCandidate(WebRtcIceCandidateSignal.fromJson(value)),
          );
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
      path: MimiCamProtocolV2.webRtcIce,
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
        path: MimiCamProtocolV2.webRtcClose,
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
    final request = await http.postUrl(
      ServerEndpointBuilder(session).http(path, query: query),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${session.sessionToken}');
    request.write(jsonEncode(body));
    return _readJson(await request.close());
  }

  Future<Map<String, Object?>> _getJson({
    required HttpClient http,
    required PairingSession session,
    required String path,
    required Map<String, String> query,
  }) async {
    final request = await http.getUrl(
      ServerEndpointBuilder(session).http(path, query: query),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${session.sessionToken}',
    );
    return _readJson(await request.close());
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
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final handles = _handles.toList(growable: false);
    for (final handle in handles) {
      await handle.close();
    }
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

  static List<RTCRtpCodecCapability> _preferredFirst(
    List<RTCRtpCodecCapability> codecs,
    String mimeType,
  ) =>
      [
        ...codecs.where((codec) => codec.mimeType.toLowerCase() == mimeType),
        ...codecs.where((codec) => codec.mimeType.toLowerCase() != mimeType)
      ];
}

class _FlutterWebRtcClientMediaHandle implements WebRtcClientMediaHandle {
  _FlutterWebRtcClientMediaHandle({
    required this.peerId,
    required this.videoRenderer,
    required RTCPeerConnection connection,
    required Future<void> Function() onClose,
    required void Function(_FlutterWebRtcClientMediaHandle handle) onDisposed,
  })  : _connection = connection,
        _onClose = onClose,
        _onDisposed = onDisposed;

  @override
  final String peerId;
  @override
  final RTCVideoRenderer videoRenderer;
  final RTCPeerConnection _connection;
  final Future<void> Function() _onClose;
  final void Function(_FlutterWebRtcClientMediaHandle handle) _onDisposed;
  final _states = StreamController<RTCPeerConnectionState>.broadcast();
  RTCPeerConnectionState _state =
      RTCPeerConnectionState.RTCPeerConnectionStateNew;
  bool _closed = false;

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
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _connection.onTrack = null;
    _connection.onIceCandidate = null;
    _connection.onConnectionState = null;
    await _onClose();
    videoRenderer.srcObject = null;
    await _connection.close();
    await _connection.dispose();
    await videoRenderer.dispose();
    await _states.close();
    _onDisposed(this);
  }
}
