import 'dart:collection';

import 'active_client_registry.dart';
import 'server_session_operation_queue.dart';
import 'server_session_registry.dart';

/// Single lifecycle owner for session mutations and their runtime snapshots.
///
/// HTTP, WebRTC and broadcast-expiry callers all enter through [run], so no
/// later feature can accidentally mutate a session outside the serialized
/// transaction boundary.
class ServerSessionController {
  ServerSessionController({
    required this.activeClients,
    DateTime Function()? now,
    this.streamAttemptTombstoneTtl = const Duration(minutes: 2),
    this.maxStreamAttemptTombstones = 256,
  })  : assert(streamAttemptTombstoneTtl > Duration.zero),
        assert(maxStreamAttemptTombstones > 0),
        _now = now ?? DateTime.now;

  final ActiveClientRegistry activeClients;
  final Duration streamAttemptTombstoneTtl;
  final int maxStreamAttemptTombstones;
  final DateTime Function() _now;
  final ServerSessionRegistry registry = ServerSessionRegistry();
  final ServerSessionOperationQueue _operations = ServerSessionOperationQueue();
  final LinkedHashMap<_StreamAttemptKey, int> _cancelledStreamAttempts =
      LinkedHashMap<_StreamAttemptKey, int>();

  Future<T> run<T>(Future<T> Function() operation) =>
      _operations.run(operation);

  ActiveSessionStartResult startActiveSession(String clientId) =>
      activeClients.startSession(clientId);

  void rollbackActiveSession(ActiveSessionStartResult result) =>
      activeClients.rollbackSessionStart(result);

  void stopActiveSession(String clientId) =>
      activeClients.stopSession(clientId);

  void cancelStreamAttempt(String clientId, String attemptId) {
    _pruneStreamAttemptTombstones();
    final key = _StreamAttemptKey(clientId, attemptId);
    _cancelledStreamAttempts.remove(key);
    _cancelledStreamAttempts[key] =
        _now().add(streamAttemptTombstoneTtl).millisecondsSinceEpoch;
    while (_cancelledStreamAttempts.length > maxStreamAttemptTombstones) {
      _cancelledStreamAttempts.remove(_cancelledStreamAttempts.keys.first);
    }
  }

  bool isStreamAttemptCancelled(String clientId, String attemptId) {
    _pruneStreamAttemptTombstones();
    return _cancelledStreamAttempts.containsKey(
      _StreamAttemptKey(clientId, attemptId),
    );
  }

  int get streamAttemptTombstoneCount {
    _pruneStreamAttemptTombstones();
    return _cancelledStreamAttempts.length;
  }

  Future<void> close() => _operations.close();

  void clear() {
    registry.clear();
    _cancelledStreamAttempts.clear();
  }

  void _pruneStreamAttemptTombstones() {
    final nowMs = _now().millisecondsSinceEpoch;
    _cancelledStreamAttempts.removeWhere(
      (_, expiresAtMs) => expiresAtMs <= nowMs,
    );
  }
}

class _StreamAttemptKey {
  const _StreamAttemptKey(this.clientId, this.attemptId);

  final String clientId;
  final String attemptId;

  @override
  bool operator ==(Object other) =>
      other is _StreamAttemptKey &&
      other.clientId == clientId &&
      other.attemptId == attemptId;

  @override
  int get hashCode => Object.hash(clientId, attemptId);
}
