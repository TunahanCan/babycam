import 'active_client_registry.dart';
import 'server_session_operation_queue.dart';
import 'server_session_registry.dart';

/// Single lifecycle owner for session mutations and their runtime snapshots.
///
/// HTTP, WebRTC and broadcast-expiry callers all enter through [run], so no
/// later feature can accidentally mutate a session outside the serialized
/// transaction boundary.
class ServerSessionController {
  ServerSessionController({required this.activeClients});

  final ActiveClientRegistry activeClients;
  final ServerSessionRegistry registry = ServerSessionRegistry();
  final ServerSessionOperationQueue _operations = ServerSessionOperationQueue();

  Future<T> run<T>(Future<T> Function() operation) =>
      _operations.run(operation);

  ActiveSessionStartResult startActiveSession(String clientId) =>
      activeClients.startSession(clientId);

  void rollbackActiveSession(ActiveSessionStartResult result) =>
      activeClients.rollbackSessionStart(result);

  void stopActiveSession(String clientId) =>
      activeClients.stopSession(clientId);

  Future<void> close() => _operations.close();

  void clear() => registry.clear();
}
