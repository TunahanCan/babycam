import '../../core/media/adaptive_media_profile.dart';
import '../../core/media/client_quality_tracker.dart';
import '../../features/server/pairing/pairing_token_service.dart';

class ActiveClientLimitException implements Exception {
  const ActiveClientLimitException();

  static const code = 'MAX_ACTIVE_CLIENTS_REACHED';
  static const userMessage =
      'En fazla 5 cihaz aynı anda izleyebilir. Önce bir oturumu kapatın.';

  @override
  String toString() => '$code: $userMessage';
}

enum ConnectionLimitScope { client, server }

class ConnectionLimitException implements Exception {
  const ConnectionLimitException({
    required this.scope,
    required this.channel,
    required this.maxConnections,
  });

  final ConnectionLimitScope scope;
  final String channel;
  final int maxConnections;

  String get code => scope == ConnectionLimitScope.client
      ? 'CLIENT_CONNECTION_LIMIT_REACHED'
      : 'SERVER_CONNECTION_CAPACITY_REACHED';

  String get userMessage => scope == ConnectionLimitScope.client
      ? 'This device already has the maximum number of $channel connections.'
      : 'The room device has reached its $channel connection capacity.';

  @override
  String toString() => '$code: $userMessage';
}

class ClientConnectionLease {
  ClientConnectionLease._({
    required this.clientId,
    required void Function() onRelease,
  }) : _onRelease = onRelease;

  final String clientId;
  final void Function() _onRelease;
  bool _released = false;

  bool get isReleased => _released;

  /// Releases this exact connection once. Calling this method from multiple
  /// lifecycle paths is safe and cannot decrement another live connection.
  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}

class ActiveSessionStartResult {
  const ActiveSessionStartResult({
    required this.clientId,
    required this.streamToken,
    required this.activeClientCount,
    required this.createdActiveSlot,
  });

  final String clientId;
  final StreamAccessToken streamToken;
  final int activeClientCount;
  final bool createdActiveSlot;
}

class StreamAttachResult extends ClientConnectionLease {
  StreamAttachResult({
    required super.clientId,
    required this.createdActiveSlot,
    required super.onRelease,
  }) : super._();

  final bool createdActiveSlot;
}

class ActiveClientRegistry {
  ActiveClientRegistry({
    required this.tokenService,
    required this.maxActiveClients,
    this.maxMediaConnectionsPerClient = 3,
    int? maxTotalMediaConnections,
    this.maxEventSocketsPerClient = 2,
    int? maxTotalEventSockets,
    ClientQualityTracker? qualityTracker,
  })  : assert(maxActiveClients > 0),
        assert(maxMediaConnectionsPerClient > 0),
        assert(maxEventSocketsPerClient > 0),
        maxTotalMediaConnections =
            maxTotalMediaConnections ?? maxActiveClients * 3,
        maxTotalEventSockets = maxTotalEventSockets ?? maxActiveClients * 2,
        _qualityTracker = qualityTracker ?? ClientQualityTracker() {
    if (this.maxTotalMediaConnections <= 0 || this.maxTotalEventSockets <= 0) {
      throw ArgumentError('Connection limits must be positive.');
    }
  }

  final PairingTokenService tokenService;
  final int maxActiveClients;
  final int maxMediaConnectionsPerClient;
  final int maxTotalMediaConnections;
  final int maxEventSocketsPerClient;
  final int maxTotalEventSockets;
  final ClientQualityTracker _qualityTracker;
  final _sessionClients = <String>{};
  final _activeClients = <String>{};
  final _streamConnectionCounts = <String, int>{};
  final _streamConnectionLeases = <int, String>{};
  final _eventSocketCounts = <String, int>{};
  final _eventSocketLeases = <int, String>{};
  int _nextConnectionLeaseId = 0;

  int get activeClientCount {
    pruneExpiredStreamTokens();
    return _activeClients.length;
  }

  int get qualityReportCount => _qualityTracker.reportCount;

  int get mediaConnectionCount => _streamConnectionLeases.length;

  int get eventSocketCount => _eventSocketLeases.length;

  List<String> get activeClientIds {
    pruneExpiredStreamTokens();
    return List.unmodifiable(_activeClients);
  }

  ActiveSessionStartResult startSession(String clientId) {
    final normalizedClientId = _normalizeClientId(clientId);
    pruneExpiredStreamTokens();
    final createdActiveSlot = _activateClient(normalizedClientId);
    _sessionClients.add(normalizedClientId);
    final streamToken =
        tokenService.issueStreamToken(clientId: normalizedClientId);
    return ActiveSessionStartResult(
      clientId: normalizedClientId,
      streamToken: streamToken,
      activeClientCount: _activeClients.length,
      createdActiveSlot: createdActiveSlot,
    );
  }

  void stopSession(String clientId) {
    cleanupClient(clientId);
  }

  void rollbackSessionStart(ActiveSessionStartResult startResult) {
    tokenService.revokeStreamToken(startResult.streamToken.token);
    if (startResult.createdActiveSlot) {
      cleanupClient(startResult.clientId);
    }
  }

  StreamAttachResult attachStream(String clientId) {
    final normalizedClientId = _normalizeClientId(clientId);
    pruneExpiredStreamTokens();
    _enforceConnectionLimit(
      clientId: normalizedClientId,
      channel: 'media',
      counts: _streamConnectionCounts,
      totalCount: _streamConnectionLeases.length,
      maxPerClient: maxMediaConnectionsPerClient,
      maxTotal: maxTotalMediaConnections,
    );
    final createdActiveSlot = _activateClient(normalizedClientId);
    final leaseId = ++_nextConnectionLeaseId;
    _streamConnectionLeases[leaseId] = normalizedClientId;
    _streamConnectionCounts.update(
      normalizedClientId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return StreamAttachResult(
      clientId: normalizedClientId,
      createdActiveSlot: createdActiveSlot,
      onRelease: () => _releaseStreamLease(leaseId),
    );
  }

  void detachStream(String clientId) {
    final normalizedClientId = _normalizeClientId(clientId);
    final leaseId = _streamConnectionLeases.entries
        .where((entry) => entry.value == normalizedClientId)
        .map((entry) => entry.key)
        .firstOrNull;
    if (leaseId != null) _releaseStreamLease(leaseId);
  }

  ClientConnectionLease attachEventSocket(String clientId) {
    final normalizedClientId = _normalizeClientId(clientId);
    _enforceConnectionLimit(
      clientId: normalizedClientId,
      channel: 'event',
      counts: _eventSocketCounts,
      totalCount: _eventSocketLeases.length,
      maxPerClient: maxEventSocketsPerClient,
      maxTotal: maxTotalEventSockets,
    );
    final leaseId = ++_nextConnectionLeaseId;
    _eventSocketLeases[leaseId] = normalizedClientId;
    _eventSocketCounts.update(
      normalizedClientId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return ClientConnectionLease._(
      clientId: normalizedClientId,
      onRelease: () => _releaseEventSocketLease(leaseId),
    );
  }

  String? clientIdForStreamToken(String token) {
    pruneExpiredStreamTokens();
    final record = tokenService.validateStreamToken(token);
    return record?.clientId;
  }

  void updateQuality({
    required String clientId,
    required NetworkQualityTier tier,
    int? rttMs,
  }) {
    _qualityTracker.update(
      clientId: _normalizeClientId(clientId),
      tier: tier,
      rttMs: rttMs,
    );
  }

  void updateQualityReport(ClientQualityReport report) {
    _qualityTracker.updateReport(
      report.copyWith(clientId: _normalizeClientId(report.clientId)),
    );
  }

  NetworkQualityTier effectiveTier() {
    pruneExpiredStreamTokens();
    return _qualityTracker.effectiveTier(clientIds: _activeClients);
  }

  ClientQualityReport? worstQualityReport() {
    pruneExpiredStreamTokens();
    return _qualityTracker.worstReport(clientIds: _activeClients);
  }

  List<ClientQualityReport> activeQualityReports() {
    pruneExpiredStreamTokens();
    return _activeClients
        .map(_qualityTracker.reportFor)
        .whereType<ClientQualityReport>()
        .toList(growable: false);
  }

  void cleanupClient(String clientId) {
    final normalizedClientId = _normalizeClientId(clientId);
    _sessionClients.remove(normalizedClientId);
    _activeClients.remove(normalizedClientId);
    _streamConnectionCounts.remove(normalizedClientId);
    _streamConnectionLeases.removeWhere(
      (_, leaseClientId) => leaseClientId == normalizedClientId,
    );
    _qualityTracker.remove(normalizedClientId);
    tokenService.revokeStreamTokensForClient(normalizedClientId);
  }

  void clear({bool includeEventSockets = false}) {
    for (final clientId in _activeClients.toList()) {
      cleanupClient(clientId);
    }
    _streamConnectionCounts.clear();
    _streamConnectionLeases.clear();
    if (includeEventSockets) {
      _eventSocketCounts.clear();
      _eventSocketLeases.clear();
    }
    _sessionClients.clear();
    _qualityTracker.clear();
  }

  void pruneExpiredStreamTokens() {
    final expiredClientIds = tokenService.pruneExpiredStreamTokens();
    for (final clientId in expiredClientIds) {
      if (_streamConnectionCounts.containsKey(clientId)) continue;
      if (tokenService.hasValidStreamTokenForClient(clientId)) continue;
      cleanupClient(clientId);
    }
  }

  bool _activateClient(String clientId) {
    if (_activeClients.contains(clientId)) return false;
    if (_activeClients.length >= maxActiveClients) {
      throw const ActiveClientLimitException();
    }
    _activeClients.add(clientId);
    return true;
  }

  void _enforceConnectionLimit({
    required String clientId,
    required String channel,
    required Map<String, int> counts,
    required int totalCount,
    required int maxPerClient,
    required int maxTotal,
  }) {
    if ((counts[clientId] ?? 0) >= maxPerClient) {
      throw ConnectionLimitException(
        scope: ConnectionLimitScope.client,
        channel: channel,
        maxConnections: maxPerClient,
      );
    }
    if (totalCount >= maxTotal) {
      throw ConnectionLimitException(
        scope: ConnectionLimitScope.server,
        channel: channel,
        maxConnections: maxTotal,
      );
    }
  }

  void _releaseStreamLease(int leaseId) {
    final clientId = _streamConnectionLeases.remove(leaseId);
    if (clientId == null) return;
    _decrementConnectionCount(_streamConnectionCounts, clientId);
    if (!_sessionClients.contains(clientId) &&
        !_streamConnectionCounts.containsKey(clientId)) {
      cleanupClient(clientId);
    }
  }

  void _releaseEventSocketLease(int leaseId) {
    final clientId = _eventSocketLeases.remove(leaseId);
    if (clientId == null) return;
    _decrementConnectionCount(_eventSocketCounts, clientId);
  }

  void _decrementConnectionCount(Map<String, int> counts, String clientId) {
    final count = counts[clientId];
    if (count == null) return;
    if (count <= 1) {
      counts.remove(clientId);
    } else {
      counts[clientId] = count - 1;
    }
  }

  String _normalizeClientId(String clientId) {
    final normalized = clientId.trim();
    return normalized.isEmpty ? 'unknown_client' : normalized;
  }
}
