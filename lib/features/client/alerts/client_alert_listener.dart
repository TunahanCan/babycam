import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/mimicam_protocol.dart';
import '../../../core/protocol/alert_event_dto.dart';
import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../media/client_stream_health_state.dart';

class ClientAlertListener {
  ClientAlertListener({
    this.healthState,
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 8),
    this.onAlert,
    HttpClient Function(PairingSession session)? clientFactory,
  }) : _clientFactory = clientFactory;

  final ClientStreamHealthState? healthState;
  final Duration reconnectDelay;
  final Duration maxReconnectDelay;
  final void Function(AlertEventDto alert)? onAlert;
  final HttpClient Function(PairingSession session)? _clientFactory;

  bool isListening = false;
  bool isConnected = false;

  WebSocket? _socket;
  HttpClient? _client;
  Future<void>? _loop;
  Completer<void>? _firstConnection;
  Completer<void>? _retryDelay;
  Timer? _retryTimer;
  var _generation = 0;
  var _intentionalStop = false;

  Future<void> start(PairingSession session) async {
    if (isListening) return _firstConnection?.future ?? Future<void>.value();
    _intentionalStop = false;
    isListening = true;
    _firstConnection = Completer<void>();
    final generation = ++_generation;
    _loop = _listenLoop(generation, session);
    return _firstConnection!.future;
  }

  Future<void> stop() async {
    _intentionalStop = true;
    isListening = false;
    isConnected = false;
    _generation++;
    final socket = _socket;
    _socket = null;
    _cancelRetryDelay();
    await socket?.close();
    _client?.close(force: true);
    _client = null;
    final first = _firstConnection;
    if (first != null && !first.isCompleted) first.complete();
    _firstConnection = null;
    await _loop?.catchError((_) {});
    _loop = null;
  }

  Future<void> _listenLoop(int generation, PairingSession session) async {
    var delay = reconnectDelay;
    while (_isCurrent(generation)) {
      try {
        await _connectAndRead(generation, session);
        delay = reconnectDelay;
      } catch (error) {
        if (!_isCurrent(generation)) return;
        final first = _firstConnection;
        if (first != null && !first.isCompleted) {
          first.completeError(error);
        }
      }
      if (!_isCurrent(generation)) return;
      _markDisconnected();
      healthState?.markReconnectAttempt();
      await _waitBeforeReconnect(delay);
      delay = Duration(
        milliseconds: min(
          maxReconnectDelay.inMilliseconds,
          (delay.inMilliseconds * 1.7).round(),
        ),
      );
    }
  }

  Future<void> _connectAndRead(int generation, PairingSession session) async {
    final client = _clientFactory?.call(session);
    final uri = ServerEndpointBuilder(session).ws(MimiCamProtocolV2.events);
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer ${session.sessionToken}',
      },
      compression: CompressionOptions.compressionOff,
      customClient: client,
    );
    if (!_isCurrent(generation)) {
      await socket.close();
      client?.close(force: true);
      return;
    }
    _client = client;
    _socket = socket;
    isConnected = true;
    healthState?.markWsConnected();
    final first = _firstConnection;
    if (first != null && !first.isCompleted) first.complete();
    try {
      await for (final data in socket) {
        if (!_isCurrent(generation)) return;
        _handleSocketMessage(data);
      }
    } finally {
      if (_socket == socket) _socket = null;
      if (_client == client) _client = null;
      client?.close(force: true);
    }
  }

  void _markDisconnected() {
    if (_intentionalStop) return;
    if (isConnected) healthState?.markWsDisconnected();
    isConnected = false;
  }

  bool _isCurrent(int generation) =>
      generation == _generation && isListening && !_intentionalStop;

  Future<void> _waitBeforeReconnect(Duration delay) {
    final completer = Completer<void>();
    _retryDelay = completer;
    _retryTimer = Timer(delay, () {
      if (!completer.isCompleted) completer.complete();
      if (identical(_retryDelay, completer)) _retryDelay = null;
      _retryTimer = null;
    });
    return completer.future;
  }

  void _cancelRetryDelay() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final delay = _retryDelay;
    _retryDelay = null;
    if (delay != null && !delay.isCompleted) delay.complete();
  }

  void _handleSocketMessage(dynamic data) {
    final alert = _parseAlert(data);
    if (alert != null) onAlert?.call(alert);
  }

  AlertEventDto? _parseAlert(dynamic data) {
    try {
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, Object?>) {
          return AlertEventDto.fromJson(decoded);
        }
        if (decoded is Map) {
          return AlertEventDto.fromJson(Map<String, Object?>.from(decoded));
        }
      }
      if (data is List<int> &&
          data.isNotEmpty &&
          data.first == MimiCamProtocol.packetAlertText) {
        final message = utf8.decode(data.skip(1).toList());
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        return AlertEventDto(
          id: 'legacy-$nowMs',
          type: 'legacyAlert',
          severity: 'info',
          messageKey: 'legacyAlert',
          message: message,
          score: 0,
          timestampMs: nowMs,
          sourceDeviceId: 'server',
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
