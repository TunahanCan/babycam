import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';

class ClientAlertListener {
  ClientAlertListener({
    HttpClient Function(PairingSession session)? clientFactory,
  }) : _clientFactory = clientFactory;

  final HttpClient Function(PairingSession session)? _clientFactory;
  bool isListening = false;
  WebSocket? _socket;
  HttpClient? _client;

  Future<void> start(PairingSession session) async {
    if (isListening) return;
    final client = _clientFactory?.call(session);
    final uri = ServerEndpointBuilder(session).ws(MimiCamProtocolV2.events);
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer ${session.sessionToken}'
      },
      compression: CompressionOptions.compressionOff,
      customClient: client,
    );
    _client = client;
    _socket = socket;
    isListening = true;
    socket.done.whenComplete(() {
      isListening = false;
      if (_socket == socket) {
        _socket = null;
        _client?.close(force: true);
        _client = null;
      }
    });
  }

  Future<void> stop() async {
    isListening = false;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    _client?.close(force: true);
    _client = null;
  }
}
