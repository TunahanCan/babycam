import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/protocol/webrtc_signaling.dart';
import 'webrtc_server_gateway.dart';

class FlutterWebRtcServerGateway
    implements
        WebRtcServerGateway,
        WebRtcPeerLifecycleSource,
        WebRtcPendingOfferController,
        WebRtcMediaPolicyController,
        WebRtcBackgroundMediaController {
  FlutterWebRtcServerGateway({
    this.maxPeers = 1,
    this.onLog,
    this.nativeOperationTimeout = const Duration(seconds: 10),
    this.cleanupTimeout = const Duration(seconds: 2),
  })  : assert(nativeOperationTimeout > Duration.zero),
        assert(cleanupTimeout > Duration.zero);

  final int maxPeers;
  final void Function(String message)? onLog;
  final Duration nativeOperationTimeout;
  final Duration cleanupTimeout;
  final _peers = <String, _ServerPeer>{};
  final _reservations = <String>{};
  final _pendingOffers = <String, _PendingServerOffer>{};
  final _peerEvents = StreamController<WebRtcPeerLifecycleEvent>.broadcast();
  Future<bool>? _initializeOperation;
  bool _initialized = false;
  bool _available = false;
  bool _disposed = false;

  @override
  bool get isAvailable => _initialized && _available && !_disposed;

  @override
  int get activePeerCount => _peers.length;

  @override
  Stream<WebRtcPeerLifecycleEvent> get peerEvents => _peerEvents.stream;

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
      final video = await getRtpSenderCapabilities('video').timeout(
        nativeOperationTimeout,
      );
      final audio = await getRtpSenderCapabilities('audio').timeout(
        nativeOperationTimeout,
      );
      _available =
          _hasCodec(video, 'video/h264') && _hasCodec(audio, 'audio/opus');
      if (_available) {
        await _probeOfferAnswer(
          video: video,
          audio: audio,
        ).timeout(nativeOperationTimeout);
      }
      _initialized = true;
    } catch (error) {
      _available = false;
      _initialized = false;
      onLog?.call('WebRTC capability probe failed: $error');
    }
    return _available;
  }

  @override
  Future<WebRtcOfferResponse> acceptOffer({
    required String clientId,
    required WebRtcOfferRequest request,
  }) async {
    if (!await initialize() || _disposed) {
      throw const WebRtcPilotUnavailableException();
    }
    if (!request.video && !request.audio) {
      throw const FormatException('At least one media track is required.');
    }
    final peerId = _newPeerId();
    final pending = _PendingServerOffer(
      clientId: clientId,
      peerId: peerId,
    );
    final previous = _pendingOffers[clientId];
    if (previous != null) {
      previous.cancel();
      unawaited(_cleanupPendingOffer(previous));
    }
    _pendingOffers[clientId] = pending;
    try {
      await _closeClient(clientId, notify: false);
      pending.ensureOwnedBy(_pendingOffers, disposed: _disposed);
      if (_peers.length + _reservations.length >= maxPeers) {
        throw const WebRtcPilotCapacityException();
      }
      _reservations.add(peerId);

      final connection = await _createConnection(
        const {
          'iceServers': <Object>[],
          'sdpSemantics': 'unified-plan',
          'bundlePolicy': 'max-bundle',
          'rtcpMuxPolicy': 'require',
        },
        const {
          'mandatory': <String, Object>{},
          'optional': <Object>[],
        },
      );
      pending.connection = connection;
      pending.ensureOwnedBy(_pendingOffers, disposed: _disposed);

      final localStream = await _getUserMedia({
        'audio': request.audio
            ? <String, Object>{
                'echoCancellation': false,
                'noiseSuppression': false,
                'autoGainControl': false,
              }
            : false,
        'video': request.video
            ? <String, Object>{
                'facingMode': 'environment',
                'width': <String, int>{'ideal': 1280},
                'height': <String, int>{'ideal': 720},
                'frameRate': <String, int>{'ideal': 20, 'max': 24},
              }
            : false,
      });
      pending.localStream = localStream;
      pending.ensureOwnedBy(_pendingOffers, disposed: _disposed);

      for (final track in localStream.getTracks()) {
        await connection.addTrack(track, localStream).timeout(
              nativeOperationTimeout,
            );
        pending.ensureOwnedBy(_pendingOffers, disposed: _disposed);
      }

      final peer = _ServerPeer(
        id: peerId,
        clientId: clientId,
        connection: connection,
        localStream: localStream,
      );
      connection.onIceCandidate = (candidate) {
        final value = candidate.candidate?.trim();
        if (value == null || value.isEmpty || peer.closed) return;
        peer.localCandidates.add(WebRtcIceCandidateSignal(
          candidate: value,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ));
      };
      connection.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          unawaited(_closeEntry(
            peer,
            reason: state == RTCPeerConnectionState.RTCPeerConnectionStateFailed
                ? WebRtcPeerCloseReason.failed
                : WebRtcPeerCloseReason.connectionClosed,
          ));
        }
      };

      await _preferCodecs(connection).timeout(nativeOperationTimeout);
      pending.ensureOwnedBy(_pendingOffers, disposed: _disposed);
      await connection
          .setRemoteDescription(
            RTCSessionDescription(request.offer.sdp, request.offer.type),
          )
          .timeout(nativeOperationTimeout);
      pending.ensureOwnedBy(_pendingOffers, disposed: _disposed);
      final answer =
          await connection.createAnswer().timeout(nativeOperationTimeout);
      pending.ensureOwnedBy(_pendingOffers, disposed: _disposed);
      await connection.setLocalDescription(answer).timeout(
            nativeOperationTimeout,
          );
      pending.ensureOwnedBy(_pendingOffers, disposed: _disposed);
      final localDescription = await connection.getLocalDescription().timeout(
                nativeOperationTimeout,
              ) ??
          answer;
      pending.ensureOwnedBy(_pendingOffers, disposed: _disposed);

      pending
        ..connection = null
        ..localStream = null;
      _peers[peerId] = peer;
      return WebRtcOfferResponse(
        peerId: peerId,
        answer: WebRtcSignalDescription(
          sdp: localDescription.sdp ?? answer.sdp ?? '',
          type: localDescription.type ?? answer.type ?? 'answer',
        ),
        iceCandidates: drainLocalCandidates(
          clientId: clientId,
          peerId: peerId,
        ),
      );
    } catch (_) {
      pending.cancel();
      await _cleanupPendingOffer(pending);
      rethrow;
    } finally {
      if (identical(_pendingOffers[clientId], pending)) {
        _pendingOffers.remove(clientId);
      }
      _reservations.remove(peerId);
    }
  }

  @override
  Future<void> cancelPendingOffer(String clientId) {
    final pending = _pendingOffers.remove(clientId);
    if (pending == null) return Future<void>.value();
    pending.cancel();
    _reservations.remove(pending.peerId);
    return _cleanupPendingOffer(pending);
  }

  @override
  Future<void> addRemoteCandidate({
    required String clientId,
    required String peerId,
    required WebRtcIceCandidateSignal candidate,
  }) async {
    final peer = _peerFor(clientId, peerId);
    await peer.connection.addCandidate(RTCIceCandidate(
      candidate.candidate,
      candidate.sdpMid,
      candidate.sdpMLineIndex,
    ));
  }

  @override
  List<WebRtcIceCandidateSignal> drainLocalCandidates({
    required String clientId,
    required String peerId,
  }) {
    final peer = _peerFor(clientId, peerId);
    final result = List<WebRtcIceCandidateSignal>.of(peer.localCandidates);
    peer.localCandidates.clear();
    return result;
  }

  @override
  Future<void> closePeer({
    required String clientId,
    required String peerId,
  }) async {
    final peer = _peerFor(clientId, peerId);
    await _closeEntry(peer, reason: WebRtcPeerCloseReason.requested);
  }

  @override
  Future<void> closeClient(String clientId) async {
    await _closeClient(clientId, notify: true);
  }

  Future<void> _closeClient(String clientId, {required bool notify}) async {
    final owned = _peers.values
        .where((peer) => peer.clientId == clientId)
        .toList(growable: false);
    for (final peer in owned) {
      await _closeEntry(
        peer,
        reason: WebRtcPeerCloseReason.requested,
        notify: notify,
      );
    }
  }

  @override
  Future<void> applyMediaPolicy(WebRtcMediaPolicy policy) async {
    final peers = _peers.values.toList(growable: false);
    for (final peer in peers) {
      final senders = await peer.connection.getSenders().timeout(
            nativeOperationTimeout,
          );
      for (final sender in senders) {
        final track = sender.track;
        if (track?.kind != 'video') continue;
        track!.enabled = policy.videoEnabled;
        final parameters = sender.parameters;
        final encodings = parameters.encodings;
        if (encodings == null || encodings.isEmpty) continue;
        for (final encoding in encodings) {
          encoding
            ..active = policy.videoEnabled
            ..maxBitrate = policy.maxVideoBitrateBps
            ..maxFramerate = policy.maxVideoFrameRate
            ..scaleResolutionDownBy = policy.scaleResolutionDownBy;
        }
        try {
          await sender.setParameters(parameters).timeout(
                nativeOperationTimeout,
              );
        } catch (error) {
          onLog?.call('WebRTC sender policy could not be applied: $error');
        }
      }
    }
  }

  @override
  Future<void> suspendVideoForBackground() async {
    for (final peer in _peers.values.toList(growable: false)) {
      for (final track in peer.localStream.getVideoTracks()) {
        await _boundedCleanup('background video stop', track.stop);
      }
    }
  }

  @override
  Future<void> reconnectPeersForForeground() async {
    final peers = _peers.values.toList(growable: false);
    for (final peer in peers) {
      await _closeEntry(
        peer,
        reason: WebRtcPeerCloseReason.platformPause,
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pendingOffers = _pendingOffers.values.toList(growable: false);
    _pendingOffers.clear();
    for (final pending in pendingOffers) {
      pending.cancel();
      _reservations.remove(pending.peerId);
    }
    _reservations.clear();
    final peers = _peers.values.toList(growable: false);
    _peers.clear();
    await Future.wait([
      for (final pending in pendingOffers) _cleanupPendingOffer(pending),
      for (final peer in peers) _disposePeer(peer),
    ]);
    _available = false;
    try {
      await _peerEvents.close().timeout(cleanupTimeout);
    } catch (error) {
      onLog?.call('WebRTC lifecycle stream close failed: $error');
    }
  }

  _ServerPeer _peerFor(String clientId, String peerId) {
    final peer = _peers[peerId];
    if (peer == null || peer.clientId != clientId || peer.closed) {
      throw const WebRtcPeerNotFoundException();
    }
    return peer;
  }

  Future<void> _closeEntry(
    _ServerPeer peer, {
    required WebRtcPeerCloseReason reason,
    bool notify = true,
  }) async {
    if (!identical(_peers[peer.id], peer)) return;
    _peers.remove(peer.id);
    if (notify && !_peerEvents.isClosed) {
      _peerEvents.add(WebRtcPeerLifecycleEvent(
        clientId: peer.clientId,
        peerId: peer.id,
        reason: reason,
      ));
    }
    await _disposePeer(peer);
  }

  Future<void> _disposePeer(_ServerPeer peer) async {
    if (peer.closed) return;
    peer.closed = true;
    peer.connection.onIceCandidate = null;
    peer.connection.onConnectionState = null;
    await _disposeNativeResources(
      connection: peer.connection,
      localStream: peer.localStream,
    );
  }

  Future<void> _cleanupPendingOffer(_PendingServerOffer pending) async {
    final connection = pending.connection;
    final localStream = pending.localStream;
    pending
      ..connection = null
      ..localStream = null;
    if (connection == null && localStream == null) return;
    await _disposeNativeResources(
      connection: connection,
      localStream: localStream,
    );
  }

  Future<void> _disposeNativeResources({
    RTCPeerConnection? connection,
    MediaStream? localStream,
  }) async {
    if (localStream != null) {
      // Mute every source before awaiting plugin cleanup. A stuck native stop
      // must not keep sending the room's audio/video during access removal.
      final tracks = localStream.getTracks();
      for (final track in tracks) {
        // The native enabled setter dispatches an unreturned plugin Future.
        // Capture that asynchronous failure too, then continue bounded stop.
        runZonedGuarded<void>(
          () => track.enabled = false,
          (error, _) => onLog?.call('WebRTC track mute failed: $error'),
        );
      }
      await Future.wait([
        for (final track in tracks)
          _boundedCleanup(
            'track stop',
            track.stop,
          ),
      ]);
      await _boundedCleanup('stream dispose', localStream.dispose);
    }
    if (connection != null) {
      connection.onIceCandidate = null;
      connection.onConnectionState = null;
      await _boundedCleanup('peer close', connection.close);
      await _boundedCleanup('peer dispose', connection.dispose);
    }
  }

  Future<void> _boundedCleanup(
    String label,
    Future<void> Function() operation,
  ) async {
    try {
      await Future<void>.sync(operation).timeout(cleanupTimeout);
    } catch (error) {
      onLog?.call('WebRTC $label failed: $error');
    }
  }

  Future<RTCPeerConnection> _createConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const <String, dynamic>{},
  ]) {
    final operation = createPeerConnection(configuration, constraints);
    return _awaitNativeResource(
      operation,
      (connection) => _disposeNativeResources(connection: connection),
    );
  }

  Future<MediaStream> _getUserMedia(
    Map<String, dynamic> constraints,
  ) {
    final operation = navigator.mediaDevices.getUserMedia(constraints);
    return _awaitNativeResource(
      operation,
      (stream) => _disposeNativeResources(localStream: stream),
    );
  }

  Future<T> _awaitNativeResource<T>(
    Future<T> operation,
    Future<void> Function(T value) disposeLate,
  ) async {
    try {
      return await operation.timeout(nativeOperationTimeout);
    } on TimeoutException {
      unawaited(operation.then<void>(
        (value) => disposeLate(value),
        onError: (Object _, StackTrace __) {},
      ));
      rethrow;
    }
  }

  Future<void> _preferCodecs(RTCPeerConnection connection) async {
    final video = await getRtpSenderCapabilities('video');
    final audio = await getRtpSenderCapabilities('audio');
    for (final transceiver in await connection.getTransceivers()) {
      final kind = transceiver.sender.track?.kind;
      if (kind == 'video') {
        await transceiver.setCodecPreferences(
          _pilotCodecs(video.codecs ?? const [], 'video/h264'),
        );
      } else if (kind == 'audio') {
        await transceiver.setCodecPreferences(
          _pilotCodecs(audio.codecs ?? const [], 'audio/opus'),
        );
      }
    }
  }

  Future<void> _probeOfferAnswer({
    required RTCRtpCapabilities video,
    required RTCRtpCapabilities audio,
  }) async {
    RTCPeerConnection? offerer;
    RTCPeerConnection? answerer;
    try {
      offerer = await _createConnection(const {
        'iceServers': <Object>[],
        'sdpSemantics': 'unified-plan',
      });
      answerer = await _createConnection(const {
        'iceServers': <Object>[],
        'sdpSemantics': 'unified-plan',
      });
      final audioTransceiver = await offerer
          .addTransceiver(
            kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
            init:
                RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
          )
          .timeout(nativeOperationTimeout);
      await audioTransceiver
          .setCodecPreferences(
            _pilotCodecs(audio.codecs ?? const [], 'audio/opus'),
          )
          .timeout(nativeOperationTimeout);
      final videoTransceiver = await offerer
          .addTransceiver(
            kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
            init:
                RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
          )
          .timeout(nativeOperationTimeout);
      await videoTransceiver
          .setCodecPreferences(
            _pilotCodecs(video.codecs ?? const [], 'video/h264'),
          )
          .timeout(nativeOperationTimeout);
      final offer = await offerer.createOffer().timeout(nativeOperationTimeout);
      await offerer.setLocalDescription(offer).timeout(nativeOperationTimeout);
      await answerer
          .setRemoteDescription(offer)
          .timeout(nativeOperationTimeout);
      final answer =
          await answerer.createAnswer().timeout(nativeOperationTimeout);
      await answerer
          .setLocalDescription(answer)
          .timeout(nativeOperationTimeout);
      await offerer
          .setRemoteDescription(answer)
          .timeout(nativeOperationTimeout);
    } finally {
      if (offerer != null) {
        await _disposeNativeResources(connection: offerer);
      }
      if (answerer != null) {
        await _disposeNativeResources(connection: answerer);
      }
    }
  }

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

  static String _newPeerId() {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class _ServerPeer {
  _ServerPeer({
    required this.id,
    required this.clientId,
    required this.connection,
    required this.localStream,
  });

  final String id;
  final String clientId;
  final RTCPeerConnection connection;
  final MediaStream localStream;
  final localCandidates = <WebRtcIceCandidateSignal>[];
  bool closed = false;
}

class _PendingServerOffer {
  _PendingServerOffer({
    required this.clientId,
    required this.peerId,
  });

  final String clientId;
  final String peerId;
  RTCPeerConnection? connection;
  MediaStream? localStream;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
  }

  void ensureOwnedBy(
    Map<String, _PendingServerOffer> pendingOffers, {
    required bool disposed,
  }) {
    if (disposed || cancelled || !identical(pendingOffers[clientId], this)) {
      throw const _WebRtcOfferCancelled();
    }
  }
}

class _WebRtcOfferCancelled implements Exception {
  const _WebRtcOfferCancelled();
}
