import 'adaptive_media_profile.dart';

class ClientQualityReport {
  const ClientQualityReport({
    required this.clientId,
    required this.tier,
    required this.reportedAtMs,
    this.rttMs,
  });

  final String clientId;
  final NetworkQualityTier tier;
  final int reportedAtMs;
  final int? rttMs;
}

class ClientQualityTracker {
  ClientQualityTracker({
    this.reportTtl = const Duration(seconds: 15),
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Duration reportTtl;
  final int Function() _nowMs;
  final _reports = <String, ClientQualityReport>{};

  int get reportCount {
    _pruneExpired();
    return _reports.length;
  }

  void update({
    required String clientId,
    required NetworkQualityTier tier,
    int? rttMs,
  }) {
    final normalizedClientId = clientId.trim();
    if (normalizedClientId.isEmpty) return;
    _reports[normalizedClientId] = ClientQualityReport(
      clientId: normalizedClientId,
      tier: tier,
      rttMs: rttMs,
      reportedAtMs: _nowMs(),
    );
  }

  void remove(String clientId) {
    _reports.remove(clientId.trim());
  }

  void clear() {
    _reports.clear();
  }

  NetworkQualityTier effectiveTier({Iterable<String>? clientIds}) {
    _pruneExpired();
    final reports = clientIds == null
        ? _reports.values
        : clientIds
            .map((clientId) => _reports[clientId.trim()])
            .whereType<ClientQualityReport>();
    if (reports.isEmpty) return NetworkQualityTier.unknown;
    return reports
        .map((report) => report.tier)
        .reduce((current, next) => _worseTier(current, next));
  }

  void _pruneExpired() {
    final cutoffMs = _nowMs() - reportTtl.inMilliseconds;
    _reports.removeWhere((_, report) => report.reportedAtMs < cutoffMs);
  }

  NetworkQualityTier _worseTier(
    NetworkQualityTier current,
    NetworkQualityTier next,
  ) =>
      _severity(next) > _severity(current) ? next : current;

  int _severity(NetworkQualityTier tier) => switch (tier) {
        NetworkQualityTier.offline => 5,
        NetworkQualityTier.critical => 4,
        NetworkQualityTier.weak => 3,
        NetworkQualityTier.good => 2,
        NetworkQualityTier.excellent => 1,
        NetworkQualityTier.unknown => 0,
      };
}
