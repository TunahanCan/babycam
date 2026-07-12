typedef ServerSessionDemand = ({bool video, bool audio});

class ServerSessionState {
  const ServerSessionState({
    required this.demand,
    required this.mediaTransport,
    required this.runtimeOwned,
    this.standaloneDemand,
  });

  final ServerSessionDemand demand;
  final String mediaTransport;
  final bool runtimeOwned;
  final ServerSessionDemand? standaloneDemand;
}

/// Owns the runtime-facing state for every active client session.
///
/// Keeping these values together prevents reconnect and rollback paths from
/// updating only part of a session's state.
class ServerSessionRegistry {
  final _sessions = <String, ServerSessionState>{};

  ServerSessionState? snapshot(String clientId) => _sessions[clientId];

  bool requestMatches(
    String clientId, {
    required ServerSessionDemand demand,
    required String mediaTransport,
  }) {
    final session = _sessions[clientId];
    return session != null &&
        session.demand == demand &&
        session.mediaTransport == mediaTransport;
  }

  void recordRequest(
    String clientId, {
    required ServerSessionDemand demand,
    required String mediaTransport,
  }) {
    final previous = _sessions[clientId];
    _sessions[clientId] = ServerSessionState(
      demand: demand,
      mediaTransport: mediaTransport,
      runtimeOwned: previous?.runtimeOwned ?? false,
      standaloneDemand: previous?.standaloneDemand,
    );
  }

  void markRuntimeOwned(String clientId, {required bool owned}) {
    final session = _requireSession(clientId);
    _sessions[clientId] = ServerSessionState(
      demand: session.demand,
      mediaTransport: session.mediaTransport,
      runtimeOwned: owned,
      standaloneDemand: session.standaloneDemand,
    );
  }

  void setStandaloneDemand(
    String clientId,
    ServerSessionDemand? demand,
  ) {
    final session = _requireSession(clientId);
    _sessions[clientId] = ServerSessionState(
      demand: session.demand,
      mediaTransport: session.mediaTransport,
      runtimeOwned: session.runtimeOwned,
      standaloneDemand: demand,
    );
  }

  bool ownsRuntime(String clientId) =>
      _sessions[clientId]?.runtimeOwned ?? false;

  Iterable<ServerSessionDemand> get requestedDemands =>
      _sessions.values.map((session) => session.demand);

  Iterable<ServerSessionDemand> get standaloneDemands => _sessions.values
      .map((session) => session.standaloneDemand)
      .whereType<ServerSessionDemand>();

  ServerSessionState? remove(String clientId) => _sessions.remove(clientId);

  void restore(String clientId, ServerSessionState? snapshot) {
    if (snapshot == null) {
      _sessions.remove(clientId);
    } else {
      _sessions[clientId] = snapshot;
    }
  }

  void clear() => _sessions.clear();

  ServerSessionState _requireSession(String clientId) {
    final session = _sessions[clientId];
    if (session == null) {
      throw StateError(
          'Session must be recorded before runtime state changes.');
    }
    return session;
  }
}
