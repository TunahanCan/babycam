import '../../../../core/protocol/pairing_session.dart';
import 'webrtc_client_connector.dart';

enum ClientMediaTransport { mjpegWav, webRtc }

class WebRtcTransportSelection {
  const WebRtcTransportSelection({
    required this.transport,
    this.webRtc,
    this.fallbackReason,
  });

  final ClientMediaTransport transport;
  final WebRtcClientMediaHandle? webRtc;
  final Object? fallbackReason;
}

class WebRtcTransportSelector {
  const WebRtcTransportSelector({
    required this.connector,
    this.onFallback,
  });

  final WebRtcClientConnector connector;
  final void Function(Object reason)? onFallback;

  Future<WebRtcTransportSelection> select({
    required bool pilotEnabled,
    required PairingSession session,
    required String streamToken,
    required bool video,
    required bool audio,
  }) async {
    if (!pilotEnabled) {
      return const WebRtcTransportSelection(
        transport: ClientMediaTransport.mjpegWav,
      );
    }
    try {
      final handle = await connector.connect(
        session: session,
        streamToken: streamToken,
        video: video,
        audio: audio,
      );
      return WebRtcTransportSelection(
        transport: ClientMediaTransport.webRtc,
        webRtc: handle,
      );
    } catch (error) {
      onFallback?.call(error);
      return WebRtcTransportSelection(
        transport: ClientMediaTransport.mjpegWav,
        fallbackReason: error,
      );
    }
  }
}
