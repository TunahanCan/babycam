import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/protocol/pairing_session.dart';

abstract class WebRtcClientConnector {
  bool get isAvailable;

  Future<bool> initialize();

  Future<WebRtcClientMediaHandle> connect({
    required PairingSession session,
    required String streamToken,
    required bool video,
    required bool audio,
  });

  Future<void> dispose();
}

abstract class WebRtcClientMediaHandle {
  String get peerId;
  RTCVideoRenderer get videoRenderer;
  RTCPeerConnectionState get connectionState;
  Stream<RTCPeerConnectionState> get connectionStates;

  Future<void> close();
}

class WebRtcNegotiationException implements Exception {
  const WebRtcNegotiationException(this.message);

  final String message;

  @override
  String toString() => message;
}
