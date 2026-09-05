import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/protocol/miucam_protocol.dart';
import 'active_client_registry.dart';

/// Owns event WebSocket leases and lifecycle bookkeeping independently from
/// the HTTP server and media session orchestration.
class MiuCamEventSocketController {
  MiuCamEventSocketController({
    required this.activeClients,
    required this.resolveClientId,
    required this.writeConnectionLimitError,
    required this.onClientConnected,
    required this.onClientDisconnected,
    this.onTransportConnected,
    this.onTransportDisconnected,
    required this.isDisposed,
    required this.connectedLog,
    required this.onLog,
    this.reconnectGracePeriod = const Duration(seconds: 10),
    this.pingInterval = const Duration(seconds: 15),
    this.closeTimeout = const Duration(seconds: 3),
    this.maxReplayAlerts = 128,
    this.maxReplayClientCursors = 64,
    this.maxReplayAge = const Duration(minutes: 2),
    int Function()? replayNowMs,
  })  : assert(!reconnectGracePeriod.isNegative),
        assert(pingInterval > Duration.zero),
        assert(closeTimeout > Duration.zero),
        assert(maxReplayAlerts > 0),
        assert(maxReplayClientCursors > 0),
        assert(maxReplayAge > Duration.zero),
        _replayNowMs = replayNowMs;

  final ActiveClientRegistry activeClients;
  final String? Function(HttpRequest request) resolveClientId;
  final Future<void> Function(
    HttpResponse response,
    ConnectionLimitException error,
  ) writeConnectionLimitError;
  final FutureOr<void> Function(String clientId)? onClientConnected;
  final FutureOr<void> Function(String clientId)? onClientDisconnected;
  final FutureOr<void> Function(String clientId)? onTransportConnected;
  final FutureOr<void> Function(String clientId)? onTransportDisconnected;
  final bool Function() isDisposed;
  final String Function(String remoteAddress) connectedLog;
  final void Function(String message) onLog;
  final Duration reconnectGracePeriod;
  final Duration pingInterval;
  final Duration closeTimeout;
  final int maxReplayAlerts;
  final int maxReplayClientCursors;
  final Duration maxReplayAge;
  final int Function()? _replayNowMs;
  final Stopwatch _replayClock = Stopwatch()..start();

  final _sockets = <WebSocket>{};
  final _clientIds = <WebSocket, String>{};
  final _connectionLeases = <WebSocket, ClientConnectionLease>{};
  final _clientSocketCounts = <String, int>{};
  final _armedClientIds = <String>{};
  final _armOperations = <String, Future<void>>{};
  final _transportStarts = <String, Future<void>>{};
  final _disconnectTimers = <String, Timer>{};
  final _replayAlerts = <_ReplayAlert>[];
  final _deliveryCursors = <String, int>{};
  var _nextReplaySequence = 0;

  int get clientCount => _sockets.length;

  Future<bool> handleUpgrade(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) return false;
    // A new client must not receive alerts that predate its first handshake.
    // Alerts produced while its analysis demand is being armed are replayed.
    final handshakeReplayBoundary = _nextReplaySequence;
    final clientId = resolveClientId(request);
    if (clientId == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return true;
    }

    late final ClientConnectionLease connectionLease;
    try {
      connectionLease = activeClients.attachEventSocket(clientId);
    } on ConnectionLimitException catch (error) {
      await writeConnectionLimitError(request.response, error);
      return true;
    }

    late final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
      // Release dead event leases even when the OS never reports a TCP close.
      socket.pingInterval = pingInterval;
    } catch (_) {
      connectionLease.release();
      rethrow;
    }
    if (isDisposed() || resolveClientId(request) != clientId) {
      connectionLease.release();
      await _closeRevokedSocket(socket);
      return true;
    }
    _clientIds[socket] = clientId;
    _connectionLeases[socket] = connectionLease;
    final previousCount = _clientSocketCounts[clientId] ?? 0;
    _clientSocketCounts[clientId] = previousCount + 1;

    _cancelDisconnectTimer(clientId);
    try {
      if (previousCount == 0) {
        late final Future<void> transportStart;
        transportStart = Future<void>.sync(
          () => onTransportConnected?.call(clientId),
        ).whenComplete(() {
          if (identical(_transportStarts[clientId], transportStart)) {
            _transportStarts.remove(clientId);
          }
        });
        _transportStarts[clientId] = transportStart;
      }
      await _transportStarts[clientId];
      await _ensureClientArmed(clientId);
    } catch (error) {
      await _detachSocket(socket, scheduleDisconnect: false);
      await socket.close();
      onLog('Alert media demand could not start: $error');
      return true;
    }

    // Removal may happen while capture/analysis is being armed. A detached or
    // no-longer-authorized handshake must never join the broadcast set later.
    if (isDisposed() ||
        _clientIds[socket] != clientId ||
        resolveClientId(request) != clientId) {
      await _detachSocket(socket, scheduleDisconnect: false);
      await Future.wait<void>([
        _disconnectClientNow(clientId),
        _closeRevokedSocket(socket),
      ]);
      return true;
    }

    final replayEnabled =
        request.uri.queryParameters[MiuCamProtocolV2.alertReplayVersionQuery] ==
            MiuCamProtocolV2.alertReplayVersion;
    final replay = replayEnabled
        ? _replayForClient(
            clientId,
            queryCursor: _validAlertId(
              request.uri.queryParameters[MiuCamProtocolV2.alertCursorQuery],
            ),
            firstConnectionBoundary: handshakeReplayBoundary,
          )
        : const <_ReplayAlert>[];
    _sockets.add(socket);
    try {
      for (final alert in replay) {
        socket.add(alert.data);
      }
    } catch (_) {
      await release(socket);
      await socket.close();
      return true;
    }
    socket.listen(
      (data) => _handleClientMessage(socket, data),
      onError: (Object _) => unawaited(release(socket)),
      onDone: () => unawaited(release(socket)),
      cancelOnError: true,
    );
    final remoteAddress =
        request.connectionInfo?.remoteAddress.address ?? 'unknown';
    onLog(connectedLog(remoteAddress));
    return true;
  }

  Future<void> release(WebSocket socket) =>
      _detachSocket(socket, scheduleDisconnect: true);

  Future<void> _detachSocket(
    WebSocket socket, {
    required bool scheduleDisconnect,
  }) async {
    _sockets.remove(socket);
    _connectionLeases.remove(socket)?.release();
    final clientId = _clientIds.remove(socket);
    if (clientId == null) return;
    final count = _clientSocketCounts[clientId] ?? 0;
    if (count > 1) {
      _clientSocketCounts[clientId] = count - 1;
      return;
    }
    _clientSocketCounts.remove(clientId);
    try {
      await onTransportDisconnected?.call(clientId);
    } catch (error) {
      onLog('Alert transport cleanup failed: $error');
    }
    if (isDisposed()) return;
    if (scheduleDisconnect) _scheduleDisconnect(clientId);
  }

  int broadcastBinary(List<int> data) => _broadcast(data);

  int broadcastText(String data) {
    final alertId = _alertIdFromServerMessage(data);
    if (alertId != null) {
      _rememberReplayAlert(alertId, data);
    }
    return _broadcast(data);
  }

  Future<void> closeClient(String clientId) async {
    final sockets = _clientIds.entries
        .where((entry) => entry.value == clientId)
        .map((entry) => entry.key)
        .toList(growable: false);
    // Remove every delivery target and lease before waiting for peer close
    // handshakes. One unresponsive phone cannot delay access removal.
    await Future.wait<void>([
      for (final socket in sockets)
        _detachSocket(socket, scheduleDisconnect: false),
    ]);
    _deliveryCursors.remove(clientId);
    await Future.wait<void>([
      _disconnectClientNow(clientId),
      for (final socket in sockets) _closeRevokedSocket(socket),
    ]);
  }

  Future<void> _closeRevokedSocket(WebSocket socket) async {
    try {
      await socket.close(WebSocketStatus.policyViolation).timeout(closeTimeout);
    } catch (_) {
      // Delivery ownership has already been removed, including when the peer
      // never acknowledges closure. The WebSocket finishes its own teardown.
    }
  }

  int _broadcast(Object data) {
    var delivered = 0;
    for (final socket in _sockets.toList()) {
      try {
        socket.add(data);
        delivered++;
      } catch (_) {
        unawaited(release(socket));
      }
    }
    return delivered;
  }

  Future<void> closeAll({
    Future<void> Function(Future<void> Function() operation)? closeSafely,
  }) async {
    final armedClientIds = _armedClientIds.toList(growable: false);
    for (final socket in _sockets.toList()) {
      if (closeSafely == null) {
        try {
          await socket.close();
        } catch (_) {}
      } else {
        await closeSafely(socket.close);
      }
      // The socket callback and this explicit path may race; [release] and the
      // lease are both idempotent, so capacity is returned exactly once.
      await release(socket);
    }
    for (final timer in _disconnectTimers.values) {
      timer.cancel();
    }
    _disconnectTimers.clear();
    if (!isDisposed()) {
      for (final clientId in armedClientIds) {
        await _disconnectClientNow(clientId);
      }
    }
    _sockets.clear();
    _clientIds.clear();
    _connectionLeases.clear();
    _clientSocketCounts.clear();
    _armedClientIds.clear();
    _armOperations.clear();
    _transportStarts.clear();
    _deliveryCursors.clear();
    _replayAlerts.clear();
  }

  Future<void> _ensureClientArmed(String clientId) {
    if (_armedClientIds.contains(clientId)) return Future<void>.value();
    final inFlight = _armOperations[clientId];
    if (inFlight != null) return inFlight;

    late final Future<void> operation;
    operation = Future<void>.sync(() async {
      if (_armedClientIds.contains(clientId)) return;
      await onClientConnected?.call(clientId);
      _armedClientIds.add(clientId);
    }).whenComplete(() {
      if (identical(_armOperations[clientId], operation)) {
        _armOperations.remove(clientId);
      }
    });
    _armOperations[clientId] = operation;
    return operation;
  }

  void _scheduleDisconnect(String clientId) {
    if (!_armedClientIds.contains(clientId) ||
        _disconnectTimers.containsKey(clientId)) {
      return;
    }
    if (reconnectGracePeriod == Duration.zero) {
      unawaited(_disconnectClientNow(clientId));
      return;
    }
    late final Timer timer;
    timer = Timer(reconnectGracePeriod, () {
      if (!identical(_disconnectTimers[clientId], timer)) return;
      _disconnectTimers.remove(clientId);
      if ((_clientSocketCounts[clientId] ?? 0) > 0) return;
      unawaited(_disconnectClientNow(clientId));
    });
    _disconnectTimers[clientId] = timer;
  }

  void _cancelDisconnectTimer(String clientId) {
    _disconnectTimers.remove(clientId)?.cancel();
  }

  Future<void> _disconnectClientNow(String clientId) async {
    _cancelDisconnectTimer(clientId);
    if ((_clientSocketCounts[clientId] ?? 0) > 0 ||
        !_armedClientIds.remove(clientId) ||
        isDisposed()) {
      return;
    }
    try {
      await onClientDisconnected?.call(clientId);
    } catch (error) {
      onLog('Alert media demand could not stop: $error');
    }
  }

  void _rememberReplayAlert(String alertId, String data) {
    _pruneExpiredReplayAlerts();
    final alert = _ReplayAlert(
      sequence: ++_nextReplaySequence,
      id: alertId,
      data: data,
      recordedAtMs: _currentReplayTimeMs,
    );
    _replayAlerts.add(alert);
    while (_replayAlerts.length > maxReplayAlerts) {
      _replayAlerts.removeAt(0);
    }
  }

  List<_ReplayAlert> _replayForClient(
    String clientId, {
    required String? queryCursor,
    required int firstConnectionBoundary,
  }) {
    _pruneExpiredReplayAlerts();
    var cursor = _deliveryCursors[clientId];
    final querySequence = _sequenceForAlertId(queryCursor);
    if (querySequence != null && (cursor == null || querySequence > cursor)) {
      cursor = querySequence;
    }
    cursor ??= queryCursor == null
        ? firstConnectionBoundary
        : (_replayAlerts.isEmpty ? _nextReplaySequence : 0);
    _rememberDeliveryCursor(clientId, cursor);
    return _replayAlerts
        .where((alert) => alert.sequence > cursor!)
        .toList(growable: false);
  }

  int get _currentReplayTimeMs =>
      _replayNowMs?.call() ?? _replayClock.elapsedMilliseconds;

  void _pruneExpiredReplayAlerts() {
    final oldestAllowedMs = _currentReplayTimeMs - maxReplayAge.inMilliseconds;
    while (_replayAlerts.isNotEmpty &&
        _replayAlerts.first.recordedAtMs < oldestAllowedMs) {
      _replayAlerts.removeAt(0);
    }
  }

  void _handleClientMessage(WebSocket socket, dynamic data) {
    if (data is! String || data.length > 512) return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      if (decoded['type'] == MiuCamProtocolV2.alertDetachType) {
        final clientId = _clientIds[socket];
        if (clientId == null) return;
        // A deliberate stop is not a network dropout: do not burn camera and
        // microphone for the grace window or replay alerts raised while the
        // parent explicitly left alert mode.
        // Only the final socket can opt the logical client out. Advancing a
        // client-wide cursor while an overlapping lifecycle socket is still
        // consuming events could skip an alert it has not delivered yet.
        if ((_clientSocketCounts[clientId] ?? 0) <= 1) {
          _rememberDeliveryCursor(clientId, _nextReplaySequence);
        }
        unawaited(_handleClientDetach(socket, clientId));
        return;
      }
      if (decoded['type'] != MiuCamProtocolV2.alertAckType) return;
      final alertId = _validAlertId(decoded[MiuCamProtocolV2.alertAckId]);
      final sequence = _sequenceForAlertId(alertId);
      final clientId = _clientIds[socket];
      if (sequence == null || clientId == null) return;
      final current = _deliveryCursors[clientId] ?? 0;
      if (sequence > current) _rememberDeliveryCursor(clientId, sequence);
    } catch (_) {
      // Client messages are untrusted transport input.
    }
  }

  Future<void> _handleClientDetach(
    WebSocket socket,
    String clientId,
  ) async {
    await release(socket);
    await _disconnectClientNow(clientId);
  }

  int? _sequenceForAlertId(String? alertId) {
    if (alertId == null) return null;
    for (final alert in _replayAlerts.reversed) {
      if (alert.id == alertId) return alert.sequence;
    }
    return null;
  }

  void _rememberDeliveryCursor(String clientId, int sequence) {
    _deliveryCursors.remove(clientId);
    _deliveryCursors[clientId] = sequence;
    while (_deliveryCursors.length > maxReplayClientCursors) {
      _deliveryCursors.remove(_deliveryCursors.keys.first);
    }
  }

  String? _alertIdFromServerMessage(String data) {
    if (data.length > 64 * 1024) return null;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map || decoded['schemaVersion'] != 1) return null;
      return _validAlertId(decoded['id']);
    } catch (_) {
      return null;
    }
  }
}

String? _validAlertId(Object? value) {
  if (value is! String || value.isEmpty || value.length > 256) return null;
  return value;
}

class _ReplayAlert {
  const _ReplayAlert({
    required this.sequence,
    required this.id,
    required this.data,
    required this.recordedAtMs,
  });

  final int sequence;
  final String id;
  final String data;
  final int recordedAtMs;
}
