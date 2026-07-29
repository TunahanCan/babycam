import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/miucam_protocol.dart';
import '../../../core/network/retry_policy.dart';
import '../../../core/protocol/alert_event_dto.dart';
import '../../../core/protocol/miucam_protocol.dart';
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
    RetryPolicy? retryPolicy,
  })  : _clientFactory = clientFactory,
        _retryPolicy = retryPolicy ??
            ExponentialBackoffPolicy(
              initialDelay: reconnectDelay,
              maxDelay: maxReconnectDelay,
            );

  final ClientStreamHealthState? healthState;
  final Duration reconnectDelay;
  final Duration maxReconnectDelay;
  final FutureOr<void> Function(AlertEventDto alert)? onAlert;
  final HttpClient Function(PairingSession session)? _clientFactory;
  final RetryPolicy _retryPolicy;

  bool isListening = false;
  bool isConnected = false;

  final _connectionStates = StreamController<bool>.broadcast();

  Stream<bool> get connectionStates => Stream<bool>.multi((controller) {
        controller.add(isConnected);
        final subscription = _connectionStates.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
      });

  WebSocket? _socket;
  HttpClient? _client;
  Future<void>? _loop;
  Completer<void>? _firstConnection;
  Completer<void>? _retryDelay;
  Timer? _retryTimer;
  var _generation = 0;
  var _intentionalStop = false;
  String? _sessionKey;
  String? _cursorSessionKey;
  String? _lastDeliveredAlertId;

  Future<void> start(
    PairingSession session, {
    bool waitForFirstConnection = true,
  }) async {
    final sessionKey = _keyForSession(session);
    if (_cursorSessionKey != sessionKey) {
      _cursorSessionKey = sessionKey;
      _lastDeliveredAlertId = null;
    }
    if (isListening) {
      if (_sessionKey == sessionKey) {
        if (!waitForFirstConnection) return;
        return _firstConnection?.future ?? Future<void>.value();
      }
      await stop();
    }
    _intentionalStop = false;
    isListening = true;
    _sessionKey = sessionKey;
    _firstConnection = Completer<void>();
    final generation = ++_generation;
    _loop = _listenLoop(generation, session);
    if (!waitForFirstConnection) {
      unawaited(_firstConnection!.future.catchError((_) {}));
      return;
    }
    return _firstConnection!.future;
  }

  Future<void> stop() async {
    _intentionalStop = true;
    isListening = false;
    _setConnected(false);
    _sessionKey = null;
    _generation++;
    final socket = _socket;
    _socket = null;
    _cancelRetryDelay();
    if (socket != null) {
      try {
        socket.add(jsonEncode({'type': MiuCamProtocolV2.alertDetachType}));
      } catch (_) {}
      await socket.close();
    }
    _client?.close(force: true);
    _client = null;
    final first = _firstConnection;
    if (first != null && !first.isCompleted) first.complete();
    _firstConnection = null;
    await _loop?.catchError((_) {});
    _loop = null;
  }

  Future<void> _listenLoop(int generation, PairingSession session) async {
    var retryAttempt = 0;
    while (_isCurrent(generation)) {
      try {
        await _connectAndRead(generation, session);
        retryAttempt = 0;
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
      await _waitBeforeReconnect(_retryPolicy.delayForAttempt(retryAttempt));
      retryAttempt++;
    }
  }

  Future<void> _connectAndRead(int generation, PairingSession session) async {
    final client = _clientFactory?.call(session) ?? HttpClient();
    client.connectionTimeout = maxReconnectDelay;
    final cursor = _lastDeliveredAlertId;
    final uri = ServerEndpointBuilder(session).ws(
      MiuCamProtocolV2.events,
      query: {
        MiuCamProtocolV2.alertReplayVersionQuery:
            MiuCamProtocolV2.alertReplayVersion,
        if (cursor != null) MiuCamProtocolV2.alertCursorQuery: cursor,
      },
    );
    _client = client;
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        uri.toString(),
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer ${session.sessionToken}',
        },
        compression: CompressionOptions.compressionOff,
        customClient: client,
      );
      if (!_isCurrent(generation)) {
        await socket.close();
        return;
      }
      _socket = socket;
      _setConnected(true);
      healthState?.markWsConnected();
      final first = _firstConnection;
      if (first != null && !first.isCompleted) first.complete();
      await for (final data in socket) {
        if (!_isCurrent(generation)) return;
        try {
          await _handleSocketMessage(socket, data);
        } catch (_) {
          // ACKs are cumulative cursors. Continuing to a later event after one
          // failed delivery would let that later ACK permanently skip the
          // failed event. Close and replay from the last contiguous ACK.
          await socket.close();
          break;
        }
      }
    } finally {
      if (socket != null && _socket == socket) _socket = null;
      if (_client == client) _client = null;
      client.close(force: true);
    }
  }

  void _markDisconnected() {
    if (_intentionalStop) return;
    if (isConnected) healthState?.markWsDisconnected();
    _setConnected(false);
  }

  void _setConnected(bool connected) {
    if (isConnected == connected) return;
    isConnected = connected;
    if (!_connectionStates.isClosed) _connectionStates.add(connected);
  }

  bool _isCurrent(int generation) =>
      generation == _generation && isListening && !_intentionalStop;

  String _keyForSession(PairingSession session) =>
      '${session.payload.transport}|${session.payload.host}|'
      '${session.payload.port}|${session.clientId}|${session.sessionToken}';

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

  Future<void> _handleSocketMessage(WebSocket socket, dynamic data) async {
    final alert = _parseAlert(data);
    if (alert == null) return;
    await onAlert?.call(alert);
    _lastDeliveredAlertId = alert.id;
    if (socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode({
      'type': MiuCamProtocolV2.alertAckType,
      MiuCamProtocolV2.alertAckId: alert.id,
    }));
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
          data.first == MiuCamProtocol.packetAlertText) {
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
