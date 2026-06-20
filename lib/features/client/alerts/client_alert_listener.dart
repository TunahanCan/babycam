import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../core/security/pinned_http_client_factory.dart';

class ClientAlertListener {
  ClientAlertListener({
    PinnedHttpClientFactory? pinnedHttpClientFactory,
    HttpClient Function(PairingSession session)? clientFactory,
  })  : _pinnedHttpClientFactory =
            pinnedHttpClientFactory ?? PinnedHttpClientFactory(),
        _clientFactory = clientFactory;

  final PinnedHttpClientFactory _pinnedHttpClientFactory;
  final HttpClient Function(PairingSession session)? _clientFactory;
  bool isListening = false;
  WebSocket? _socket;
  HttpClient? _client;

  Future<void> start(PairingSession session) async {
    if (isListening) return;
    final client = _createClient(session);
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

  HttpClient _createClient(PairingSession session) {
    final factory = _clientFactory;
    if (factory != null) return factory(session);
    if (session.wsScheme != 'wss') return HttpClient();
    return _pinnedHttpClientFactory.create(
      expectedFingerprintSha256Hex: session.certificateFingerprintSha256,
      expectedHost: session.host,
      expectedPort: session.port,
    );
  }
}
