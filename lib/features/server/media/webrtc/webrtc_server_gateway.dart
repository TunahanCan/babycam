import 'dart:async';

import '../../../../core/protocol/webrtc_signaling.dart';

enum WebRtcPeerCloseReason {
  requested,
  failed,
  connectionClosed,
  platformPause,
  disposed,
}

class WebRtcPeerLifecycleEvent {
  const WebRtcPeerLifecycleEvent({
    required this.clientId,
    required this.peerId,
    required this.reason,
  });

  final String clientId;
  final String peerId;
  final WebRtcPeerCloseReason reason;
}

class WebRtcMediaPolicy {
  const WebRtcMediaPolicy({
    required this.maxVideoBitrateBps,
    required this.maxVideoFrameRate,
    required this.scaleResolutionDownBy,
    this.videoEnabled = true,
  });

  final int maxVideoBitrateBps;
  final int maxVideoFrameRate;
  final double scaleResolutionDownBy;
  final bool videoEnabled;
}

abstract class WebRtcServerGateway {
  bool get isAvailable;
  int get activePeerCount;

  Future<bool> initialize();

  Future<WebRtcOfferResponse> acceptOffer({
    required String clientId,
    required WebRtcOfferRequest request,
  });

  Future<void> addRemoteCandidate({
    required String clientId,
    required String peerId,
    required WebRtcIceCandidateSignal candidate,
  });

  List<WebRtcIceCandidateSignal> drainLocalCandidates({
    required String clientId,
    required String peerId,
  });

  Future<void> closePeer({
    required String clientId,
    required String peerId,
  });

  Future<void> closeClient(String clientId);
  Future<void> dispose();
}

abstract interface class WebRtcPeerLifecycleSource {
  Stream<WebRtcPeerLifecycleEvent> get peerEvents;
}

abstract interface class WebRtcMediaPolicyController {
  Future<void> applyMediaPolicy(WebRtcMediaPolicy policy);
}

abstract interface class WebRtcBackgroundMediaController {
  Future<void> suspendVideoForBackground();
  Future<void> reconnectPeersForForeground();
}

class WebRtcPilotUnavailableException implements Exception {
  const WebRtcPilotUnavailableException([
    this.message = 'WebRTC H.264/Opus pilot is unavailable.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class WebRtcPilotCapacityException implements Exception {
  const WebRtcPilotCapacityException();

  @override
  String toString() =>
      'The WebRTC pilot currently supports one active peer; use MJPEG/WAV fallback.';
}

class WebRtcPeerNotFoundException implements Exception {
  const WebRtcPeerNotFoundException();

  @override
  String toString() => 'WebRTC peer not found.';
}
