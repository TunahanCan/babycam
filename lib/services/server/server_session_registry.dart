import 'active_client_registry.dart';

typedef ServerSessionDemand = ({bool video, bool audio});

/// Exact ownership of the capacity lease held by one physical WebRTC peer.
///
/// The peer id and lease intentionally move together. Cleanup paths compare the
/// peer id before taking this object, so a late close from an older peer cannot
/// release the lease installed for its successor.
class ServerWebRtcPeerOwnership {
  ServerWebRtcPeerOwnership({
    required this.peerId,
    required this.transportLease,
  });

  final String peerId;
  final StreamAttachResult transportLease;

  bool get isReleased => transportLease.isReleased;

  void release() => transportLease.release();
}

class ServerSessionState {
  const ServerSessionState({
    required this.demand,
    required this.mediaTransport,
    required this.runtimeOwned,
    this.streamAttemptId,
    this.webRtcPeer,
    this.standaloneDemand,
  });

  final ServerSessionDemand demand;
  final String mediaTransport;
  final bool runtimeOwned;
  final String? streamAttemptId;
  final ServerWebRtcPeerOwnership? webRtcPeer;
  final ServerSessionDemand? standaloneDemand;

  String? get webRtcPeerId => webRtcPeer?.peerId;
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
    String? streamAttemptId,
  }) {
    final previous = _sessions[clientId];
    final previousPeer = previous?.webRtcPeer;
    if (previousPeer != null && mediaTransport != 'webrtc') {
      throw StateError(
        'Release the current WebRTC peer before changing transports.',
      );
    }
    _sessions[clientId] = ServerSessionState(
      demand: demand,
      mediaTransport: mediaTransport,
      runtimeOwned: previous?.runtimeOwned ?? false,
      streamAttemptId: streamAttemptId,
      // A same-transport reconnect keeps the currently healthy physical peer
      // authoritative until a new offer replaces it or its lifecycle ends.
      webRtcPeer: previousPeer,
      standaloneDemand: previous?.standaloneDemand,
    );
  }

  void markRuntimeOwned(String clientId, {required bool owned}) {
    final session = _requireSession(clientId);
    _sessions[clientId] = ServerSessionState(
      demand: session.demand,
      mediaTransport: session.mediaTransport,
      runtimeOwned: owned,
      streamAttemptId: session.streamAttemptId,
      webRtcPeer: session.webRtcPeer,
      standaloneDemand: session.standaloneDemand,
    );
  }

  ServerWebRtcPeerOwnership? webRtcPeer(String clientId) =>
      _sessions[clientId]?.webRtcPeer;

  /// Installs a peer only into an empty WebRTC ownership slot.
  ///
  /// Callers must first retire and release the exact previous peer. Requiring
  /// an empty slot prevents an accidental overwrite from losing a live lease.
  void bindWebRtcPeer(
    String clientId, {
    required String peerId,
    required StreamAttachResult transportLease,
  }) {
    final session = _requireSession(clientId);
    if (session.mediaTransport != 'webrtc') {
      throw StateError('A WebRTC peer requires a WebRTC stream session.');
    }
    if (session.webRtcPeer != null) {
      throw StateError('The previous WebRTC peer must be retired first.');
    }
    _sessions[clientId] = ServerSessionState(
      demand: session.demand,
      mediaTransport: session.mediaTransport,
      runtimeOwned: session.runtimeOwned,
      streamAttemptId: session.streamAttemptId,
      webRtcPeer: ServerWebRtcPeerOwnership(
        peerId: peerId,
        transportLease: transportLease,
      ),
      standaloneDemand: session.standaloneDemand,
    );
  }

  /// Takes ownership only when [peerId] is still the current physical peer.
  ///
  /// The returned lease is not released automatically; the caller decides
  /// whether native cleanup has been confirmed before releasing capacity.
  ServerWebRtcPeerOwnership? takeWebRtcPeer(
    String clientId, {
    required String peerId,
  }) {
    final session = _sessions[clientId];
    final ownership = session?.webRtcPeer;
    if (session == null || ownership == null || ownership.peerId != peerId) {
      return null;
    }
    _sessions[clientId] = ServerSessionState(
      demand: session.demand,
      mediaTransport: session.mediaTransport,
      runtimeOwned: session.runtimeOwned,
      streamAttemptId: session.streamAttemptId,
      standaloneDemand: session.standaloneDemand,
    );
    return ownership;
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
      streamAttemptId: session.streamAttemptId,
      webRtcPeer: session.webRtcPeer,
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

  ServerSessionState? remove(String clientId) {
    final removed = _sessions.remove(clientId);
    removed?.webRtcPeer?.release();
    return removed;
  }

  void restore(String clientId, ServerSessionState? snapshot) {
    if (snapshot == null) {
      remove(clientId);
    } else {
      final current = _sessions[clientId];
      if (!identical(current?.webRtcPeer, snapshot.webRtcPeer)) {
        current?.webRtcPeer?.release();
      }
      if (snapshot.webRtcPeer?.isReleased ?? false) {
        _sessions[clientId] = ServerSessionState(
          demand: snapshot.demand,
          mediaTransport: snapshot.mediaTransport,
          runtimeOwned: snapshot.runtimeOwned,
          streamAttemptId: snapshot.streamAttemptId,
          standaloneDemand: snapshot.standaloneDemand,
        );
      } else {
        _sessions[clientId] = snapshot;
      }
    }
  }

  void clear() {
    for (final session in _sessions.values) {
      session.webRtcPeer?.release();
    }
    _sessions.clear();
  }

  ServerSessionState _requireSession(String clientId) {
    final session = _sessions[clientId];
    if (session == null) {
      throw StateError(
          'Session must be recorded before runtime state changes.');
    }
    return session;
  }
}
