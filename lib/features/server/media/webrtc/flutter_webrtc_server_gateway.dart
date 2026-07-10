import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/protocol/webrtc_signaling.dart';
import 'webrtc_server_gateway.dart';

class FlutterWebRtcServerGateway implements WebRtcServerGateway {
  FlutterWebRtcServerGateway({
    this.maxPeers = 1,
    this.onLog,
  });

  final int maxPeers;
  final void Function(String message)? onLog;
  final _peers = <String, _ServerPeer>{};
  bool _initialized = false;
  bool _available = false;
  bool _disposed = false;

  @override
  bool get isAvailable => _initialized && _available && !_disposed;

  @override
  int get activePeerCount => _peers.length;

  @override
  Future<bool> initialize() async {
    if (_disposed) return false;
    if (_initialized) return _available;
    _initialized = true;
    try {
      final video = await getRtpSenderCapabilities('video');
      final audio = await getRtpSenderCapabilities('audio');
      _available =
          _hasCodec(video, 'video/h264') && _hasCodec(audio, 'audio/opus');
      if (_available) {
        await _probeOfferAnswer(video: video, audio: audio);
      }
    } catch (error) {
      _available = false;
      onLog?.call('WebRTC capability probe failed: $error');
    }
    return _available;
  }

  @override
  Future<WebRtcOfferResponse> acceptOffer({
    required String clientId,
    required WebRtcOfferRequest request,
  }) async {
    if (!await initialize()) {
      throw const WebRtcPilotUnavailableException();
    }
    if (!request.video && !request.audio) {
      throw const FormatException('At least one media track is required.');
    }
    await closeClient(clientId);
    if (_peers.length >= maxPeers) {
      throw const WebRtcPilotCapacityException();
    }

    final peerId = _newPeerId();
    RTCPeerConnection? connection;
    MediaStream? localStream;
    try {
      connection = await createPeerConnection(
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
      localStream = await navigator.mediaDevices.getUserMedia({
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
      for (final track in localStream.getTracks()) {
        await connection.addTrack(track, localStream);
      }

      final peer = _ServerPeer(
        id: peerId,
        clientId: clientId,
        connection: connection,
        localStream: localStream,
      );
      _peers[peerId] = peer;
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
          unawaited(_closeEntry(peer));
        }
      };

      await _preferCodecs(connection);
      await connection.setRemoteDescription(
        RTCSessionDescription(request.offer.sdp, request.offer.type),
      );
      final answer = await connection.createAnswer();
      await connection.setLocalDescription(answer);
      final localDescription = await connection.getLocalDescription() ?? answer;
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
      final peer = _peers.remove(peerId);
      if (peer != null) {
        await _disposePeer(peer);
      } else {
        for (final track in localStream?.getTracks() ?? const []) {
          await track.stop();
        }
        await localStream?.dispose();
        await connection?.close();
        await connection?.dispose();
      }
      rethrow;
    }
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
    await _closeEntry(peer);
  }

  @override
  Future<void> closeClient(String clientId) async {
    final owned = _peers.values
        .where((peer) => peer.clientId == clientId)
        .toList(growable: false);
    for (final peer in owned) {
      await _closeEntry(peer);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final peers = _peers.values.toList(growable: false);
    _peers.clear();
    for (final peer in peers) {
      await _disposePeer(peer);
    }
    _available = false;
  }

  _ServerPeer _peerFor(String clientId, String peerId) {
    final peer = _peers[peerId];
    if (peer == null || peer.clientId != clientId || peer.closed) {
      throw const WebRtcPeerNotFoundException();
    }
    return peer;
  }

  Future<void> _closeEntry(_ServerPeer peer) async {
    if (!identical(_peers[peer.id], peer)) return;
    _peers.remove(peer.id);
    await _disposePeer(peer);
  }

  Future<void> _disposePeer(_ServerPeer peer) async {
    if (peer.closed) return;
    peer.closed = true;
    peer.connection.onIceCandidate = null;
    peer.connection.onConnectionState = null;
    for (final track in peer.localStream.getTracks()) {
      await track.stop();
    }
    await peer.localStream.dispose();
    await peer.connection.close();
    await peer.connection.dispose();
  }

  Future<void> _preferCodecs(RTCPeerConnection connection) async {
    final video = await getRtpSenderCapabilities('video');
    final audio = await getRtpSenderCapabilities('audio');
    for (final transceiver in await connection.getTransceivers()) {
      final kind = transceiver.sender.track?.kind;
      if (kind == 'video') {
        await transceiver.setCodecPreferences(
          _preferredFirst(video.codecs ?? const [], 'video/h264'),
        );
      } else if (kind == 'audio') {
        await transceiver.setCodecPreferences(
          _preferredFirst(audio.codecs ?? const [], 'audio/opus'),
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
      offerer = await createPeerConnection(const {
        'iceServers': <Object>[],
        'sdpSemantics': 'unified-plan',
      });
      answerer = await createPeerConnection(const {
        'iceServers': <Object>[],
        'sdpSemantics': 'unified-plan',
      });
      final audioTransceiver = await offerer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      await audioTransceiver.setCodecPreferences(
        _preferredFirst(audio.codecs ?? const [], 'audio/opus'),
      );
      final videoTransceiver = await offerer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      await videoTransceiver.setCodecPreferences(
        _preferredFirst(video.codecs ?? const [], 'video/h264'),
      );
      final offer = await offerer.createOffer();
      await offerer.setLocalDescription(offer);
      await answerer.setRemoteDescription(offer);
      final answer = await answerer.createAnswer();
      await answerer.setLocalDescription(answer);
      await offerer.setRemoteDescription(answer);
    } finally {
      await offerer?.close();
      await offerer?.dispose();
      await answerer?.close();
      await answerer?.dispose();
    }
  }

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
