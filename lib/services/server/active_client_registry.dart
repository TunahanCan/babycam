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

class StreamAttachResult {
  const StreamAttachResult({
    required this.clientId,
    required this.createdActiveSlot,
  });

  final String clientId;
  final bool createdActiveSlot;
}

class ActiveClientRegistry {
  ActiveClientRegistry({
    required this.tokenService,
    required this.maxActiveClients,
    ClientQualityTracker? qualityTracker,
  }) : _qualityTracker = qualityTracker ?? ClientQualityTracker();

  final PairingTokenService tokenService;
  final int maxActiveClients;
  final ClientQualityTracker _qualityTracker;
  final _sessionClients = <String>{};
  final _activeClients = <String>{};
  final _streamConnectionCounts = <String, int>{};

  int get activeClientCount {
    pruneExpiredStreamTokens();
    return _activeClients.length;
  }

  int get qualityReportCount => _qualityTracker.reportCount;

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

  StreamAttachResult attachStream(String clientId) {
    final normalizedClientId = _normalizeClientId(clientId);
    pruneExpiredStreamTokens();
    final createdActiveSlot = _activateClient(normalizedClientId);
    _streamConnectionCounts.update(
      normalizedClientId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return StreamAttachResult(
      clientId: normalizedClientId,
      createdActiveSlot: createdActiveSlot,
    );
  }

  void detachStream(String clientId) {
    final normalizedClientId = _normalizeClientId(clientId);
    final count = _streamConnectionCounts[normalizedClientId];
    if (count == null) return;
    if (count <= 1) {
      _streamConnectionCounts.remove(normalizedClientId);
      if (!_sessionClients.contains(normalizedClientId)) {
        cleanupClient(normalizedClientId);
      }
      return;
    }
    _streamConnectionCounts[normalizedClientId] = count - 1;
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
    _qualityTracker.remove(normalizedClientId);
    tokenService.revokeStreamTokensForClient(normalizedClientId);
  }

  void clear() {
    for (final clientId in _activeClients.toList()) {
      cleanupClient(clientId);
    }
    _streamConnectionCounts.clear();
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

  String _normalizeClientId(String clientId) {
    final normalized = clientId.trim();
    return normalized.isEmpty ? 'unknown_client' : normalized;
  }
}
