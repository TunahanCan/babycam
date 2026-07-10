import 'webrtc/webrtc_client_connector.dart';
import 'webrtc/webrtc_transport_selector.dart';

class ActiveStreamSession {
  const ActiveStreamSession({
    required this.streamToken,
    this.expiresAtMs,
    this.audioEnabled = false,
    this.transport = ClientMediaTransport.mjpegWav,
    this.webRtc,
    this.transportFallbackReason,
  });

  final String streamToken;
  final int? expiresAtMs;
  final bool audioEnabled;
  final ClientMediaTransport transport;
  final WebRtcClientMediaHandle? webRtc;
  final Object? transportFallbackReason;

  bool get usesWebRtc =>
      transport == ClientMediaTransport.webRtc && webRtc != null;

  ActiveStreamSession copyWith({
    String? streamToken,
    int? expiresAtMs,
    bool? audioEnabled,
    ClientMediaTransport? transport,
    WebRtcClientMediaHandle? webRtc,
    Object? transportFallbackReason,
  }) =>
      ActiveStreamSession(
        streamToken: streamToken ?? this.streamToken,
        expiresAtMs: expiresAtMs ?? this.expiresAtMs,
        audioEnabled: audioEnabled ?? this.audioEnabled,
        transport: transport ?? this.transport,
        webRtc: webRtc ?? this.webRtc,
        transportFallbackReason:
            transportFallbackReason ?? this.transportFallbackReason,
      );
}
