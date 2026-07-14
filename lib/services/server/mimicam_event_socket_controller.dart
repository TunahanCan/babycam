import 'dart:async';
import 'dart:io';

import 'active_client_registry.dart';

/// Owns event WebSocket leases and lifecycle bookkeeping independently from
/// the HTTP server and media session orchestration.
class MimiCamEventSocketController {
  MimiCamEventSocketController({
    required this.activeClients,
    required this.resolveClientId,
    required this.writeConnectionLimitError,
    required this.onClientConnected,
    required this.onClientDisconnected,
    required this.isDisposed,
    required this.connectedLog,
    required this.onLog,
  });

  final ActiveClientRegistry activeClients;
  final String? Function(HttpRequest request) resolveClientId;
  final Future<void> Function(
    HttpResponse response,
    ConnectionLimitException error,
  ) writeConnectionLimitError;
  final FutureOr<void> Function(String clientId)? onClientConnected;
  final FutureOr<void> Function(String clientId)? onClientDisconnected;
  final bool Function() isDisposed;
  final String Function(String remoteAddress) connectedLog;
  final void Function(String message) onLog;

  final _sockets = <WebSocket>{};
  final _clientIds = <WebSocket, String>{};
  final _connectionLeases = <WebSocket, ClientConnectionLease>{};
  final _clientSocketCounts = <String, int>{};

  int get clientCount => _sockets.length;

  Future<bool> handleUpgrade(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) return false;
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
    } catch (_) {
      connectionLease.release();
      rethrow;
    }
    _sockets.add(socket);
    _clientIds[socket] = clientId;
    _connectionLeases[socket] = connectionLease;
    final previousCount = _clientSocketCounts[clientId] ?? 0;
    _clientSocketCounts[clientId] = previousCount + 1;
    if (previousCount == 0) {
      try {
        await onClientConnected?.call(clientId);
      } catch (error) {
        _sockets.remove(socket);
        _clientIds.remove(socket);
        _connectionLeases.remove(socket)?.release();
        _clientSocketCounts.remove(clientId);
        await socket.close();
        onLog('Alert media demand could not start: $error');
        return true;
      }
    }
    socket.listen(
      (_) {},
      onError: (Object _) => unawaited(release(socket)),
      onDone: () => unawaited(release(socket)),
      cancelOnError: true,
    );
    final remoteAddress =
        request.connectionInfo?.remoteAddress.address ?? 'unknown';
    onLog(connectedLog(remoteAddress));
    return true;
  }

  Future<void> release(WebSocket socket) async {
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
    if (isDisposed()) return;
    try {
      await onClientDisconnected?.call(clientId);
    } catch (error) {
      onLog('Alert media demand could not stop: $error');
    }
  }

  int broadcastBinary(List<int> data) => _broadcast(data);

  int broadcastText(String data) => _broadcast(data);

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
    _sockets.clear();
    _clientIds.clear();
    _connectionLeases.clear();
    _clientSocketCounts.clear();
  }
}
