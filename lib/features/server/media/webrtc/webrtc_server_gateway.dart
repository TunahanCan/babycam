import '../../../../core/protocol/webrtc_signaling.dart';

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
