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

class WebRtcClientStatsSnapshot {
  const WebRtcClientStatsSnapshot({
    this.videoBytesReceived = 0,
    this.audioBytesReceived = 0,
    this.videoFramesDecoded = 0,
    this.videoFramesDropped = 0,
    this.packetsReceived = 0,
    this.packetsLost = 0,
    this.jitterMs,
    this.jitterBufferDelayMs,
    this.videoCodec,
    this.audioCodec,
    this.measuredAtMs = 0,
  });

  final int videoBytesReceived;
  final int audioBytesReceived;
  final int videoFramesDecoded;
  final int videoFramesDropped;
  final int packetsReceived;
  final int packetsLost;
  final double? jitterMs;
  final double? jitterBufferDelayMs;
  final String? videoCodec;
  final String? audioCodec;
  final int measuredAtMs;
}

abstract interface class WebRtcClientStatsSource {
  Future<WebRtcClientStatsSnapshot> collectStats();
}

abstract interface class WebRtcClientAudioController {
  Future<void> setAudioEnabled(bool enabled);
}

class WebRtcNegotiationException implements Exception {
  const WebRtcNegotiationException(this.message);

  final String message;

  @override
  String toString() => message;
}
