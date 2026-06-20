import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../media/client_stream_health_monitor.dart';

class ClientAlertListener {
  ClientAlertListener({
    this.healthMonitor,
    this.reconnectDelay = const Duration(seconds: 1),
    HttpClient Function(PairingSession session)? clientFactory,
  }) : _clientFactory = clientFactory;

  final ClientStreamHealthMonitor? healthMonitor;
  final Duration reconnectDelay;
  final HttpClient Function(PairingSession session)? _clientFactory;
  bool isListening = false;
  WebSocket? _socket;
  HttpClient? _client;
  bool _hadUnexpectedDisconnect = false;
  bool _intentionalStop = false;

  Future<void> start(PairingSession session) async {
    if (isListening) return;
    _intentionalStop = false;
    if (_hadUnexpectedDisconnect) {
      healthMonitor?.markReconnectAttempt();
      await Future<void>.delayed(reconnectDelay);
    }
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
    _hadUnexpectedDisconnect = false;
    healthMonitor?.markWsConnected();
    socket.done.whenComplete(() {
      final unexpected = !_intentionalStop;
      isListening = false;
      if (_socket == socket) {
        _socket = null;
        _client?.close(force: true);
        _client = null;
      }
      if (unexpected) {
        _hadUnexpectedDisconnect = true;
        healthMonitor?.markWsDisconnected();
      }
    });
  }

  Future<void> stop() async {
    _intentionalStop = true;
    isListening = false;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    _client?.close(force: true);
    _client = null;
  }
}
