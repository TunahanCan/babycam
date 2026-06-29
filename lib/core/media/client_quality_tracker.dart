import 'adaptive_media_profile.dart';

class ClientQualityReport {
  const ClientQualityReport({
    required this.clientId,
    required this.networkTier,
    required this.createdAtMs,
    this.rttMs,
    this.consecutiveFailures = 0,
    this.videoFrameGapMs,
    this.audioGapMs,
    this.skippedVideoFrames = 0,
    this.skippedAudioChunks = 0,
    this.wsDisconnectCount = 0,
    this.reconnectCount = 0,
    this.streamTimedOut = false,
    this.audioUnderrun = false,
    this.watchActive = false,
    this.recentlyReconnected = false,
  });

  final String clientId;
  final NetworkQualityTier networkTier;
  final int createdAtMs;
  final int? rttMs;
  final int consecutiveFailures;
  final int? videoFrameGapMs;
  final int? audioGapMs;
  final int skippedVideoFrames;
  final int skippedAudioChunks;
  final int wsDisconnectCount;
  final int reconnectCount;
  final bool streamTimedOut;
  final bool audioUnderrun;
  final bool watchActive;
  final bool recentlyReconnected;

  NetworkQualityTier get tier => networkTier;
  int get reportedAtMs => createdAtMs;

  NetworkQualityTier get effectiveTier {
    final healthTier = _healthTier();
    return networkTier.worse(healthTier);
  }

  Map<String, Object?> toJson() => {
        'clientId': clientId,
        'tier': networkTier.name,
        'networkTier': networkTier.name,
        'rttMs': rttMs,
        'consecutiveFailures': consecutiveFailures,
        'videoFrameGapMs': videoFrameGapMs,
        'audioGapMs': audioGapMs,
        'skippedFrames': skippedVideoFrames,
        'skippedVideoFrames': skippedVideoFrames,
        'skippedAudioChunks': skippedAudioChunks,
        'wsDisconnectCount': wsDisconnectCount,
        'reconnectCount': reconnectCount,
        'streamTimedOut': streamTimedOut,
        'audioUnderrun': audioUnderrun,
        'watchActive': watchActive,
        'recentlyReconnected': recentlyReconnected,
        'createdAtMs': createdAtMs,
      };

  static ClientQualityReport fromJson(
    Map<Object?, Object?> json, {
    required String clientId,
    required int nowMs,
  }) {
    final tierName =
        json['networkTier']?.toString() ?? json['tier']?.toString();
    return ClientQualityReport(
      clientId: clientId,
      networkTier: NetworkQualityTier.fromName(tierName),
      rttMs: _intValue(json['rttMs']),
      consecutiveFailures: _intValue(json['consecutiveFailures']) ?? 0,
      videoFrameGapMs: _intValue(json['videoFrameGapMs']),
      audioGapMs: _intValue(json['audioGapMs']),
      skippedVideoFrames: _intValue(json['skippedVideoFrames']) ??
          _intValue(json['skippedFrames']) ??
          0,
      skippedAudioChunks: _intValue(json['skippedAudioChunks']) ?? 0,
      wsDisconnectCount: _intValue(json['wsDisconnectCount']) ?? 0,
      reconnectCount: _intValue(json['reconnectCount']) ?? 0,
      streamTimedOut: _boolValue(json['streamTimedOut']),
      audioUnderrun: _boolValue(json['audioUnderrun']),
      watchActive: _boolValue(json['watchActive']),
      recentlyReconnected: _boolValue(json['recentlyReconnected']),
      createdAtMs: _intValue(json['createdAtMs']) ??
          _intValue(json['reportedAtMs']) ??
          nowMs,
    );
  }

  ClientQualityReport copyWith({
    String? clientId,
    NetworkQualityTier? networkTier,
    int? createdAtMs,
    int? rttMs,
    int? consecutiveFailures,
    int? videoFrameGapMs,
    int? audioGapMs,
    int? skippedVideoFrames,
    int? skippedAudioChunks,
    int? wsDisconnectCount,
    int? reconnectCount,
    bool? streamTimedOut,
    bool? audioUnderrun,
    bool? watchActive,
    bool? recentlyReconnected,
  }) =>
      ClientQualityReport(
        clientId: clientId ?? this.clientId,
        networkTier: networkTier ?? this.networkTier,
        createdAtMs: createdAtMs ?? this.createdAtMs,
        rttMs: rttMs ?? this.rttMs,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        videoFrameGapMs: videoFrameGapMs ?? this.videoFrameGapMs,
        audioGapMs: audioGapMs ?? this.audioGapMs,
        skippedVideoFrames: skippedVideoFrames ?? this.skippedVideoFrames,
        skippedAudioChunks: skippedAudioChunks ?? this.skippedAudioChunks,
        wsDisconnectCount: wsDisconnectCount ?? this.wsDisconnectCount,
        reconnectCount: reconnectCount ?? this.reconnectCount,
        streamTimedOut: streamTimedOut ?? this.streamTimedOut,
        audioUnderrun: audioUnderrun ?? this.audioUnderrun,
        watchActive: watchActive ?? this.watchActive,
        recentlyReconnected: recentlyReconnected ?? this.recentlyReconnected,
      );

  NetworkQualityTier _healthTier() {
    if (streamTimedOut ||
        audioUnderrun ||
        skippedAudioChunks > 0 ||
        _atLeast(videoFrameGapMs, 5000) ||
        _atLeast(audioGapMs, 1500) ||
        consecutiveFailures >= 2 ||
        reconnectCount >= 3 ||
        wsDisconnectCount >= 3) {
      return NetworkQualityTier.critical;
    }
    if (_atLeast(videoFrameGapMs, 2000) ||
        _atLeast(audioGapMs, 1000) ||
        skippedVideoFrames >= 3 ||
        consecutiveFailures >= 1 ||
        wsDisconnectCount > 0 ||
        reconnectCount > 0 ||
        recentlyReconnected) {
      return NetworkQualityTier.weak;
    }
    return NetworkQualityTier.unknown;
  }

  static bool _atLeast(int? value, int threshold) =>
      value != null && value >= threshold;

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _boolValue(Object? value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }
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
    updateReport(ClientQualityReport(
      clientId: normalizedClientId,
      networkTier: tier,
      rttMs: rttMs,
      createdAtMs: _nowMs(),
    ));
  }

  void updateReport(ClientQualityReport report) {
    final normalizedClientId = report.clientId.trim();
    if (normalizedClientId.isEmpty) return;
    _reports[normalizedClientId] =
        report.copyWith(clientId: normalizedClientId, createdAtMs: _nowMs());
  }

  ClientQualityReport? reportFor(String clientId) {
    _pruneExpired();
    return _reports[clientId.trim()];
  }

  ClientQualityReport? worstReport({Iterable<String>? clientIds}) {
    _pruneExpired();
    final reports = _reportsFor(clientIds);
    if (reports.isEmpty) return null;
    return reports.reduce((current, next) =>
        next.effectiveTier.severity > current.effectiveTier.severity
            ? next
            : current);
  }

  void remove(String clientId) {
    _reports.remove(clientId.trim());
  }

  void clear() {
    _reports.clear();
  }

  NetworkQualityTier effectiveTier({Iterable<String>? clientIds}) {
    _pruneExpired();
    final reports = _reportsFor(clientIds);
    if (reports.isEmpty) return NetworkQualityTier.unknown;
    return reports
        .map((report) => report.effectiveTier)
        .reduce((current, next) => current.worse(next));
  }

  void _pruneExpired() {
    final cutoffMs = _nowMs() - reportTtl.inMilliseconds;
    _reports.removeWhere((_, report) => report.reportedAtMs < cutoffMs);
  }

  Iterable<ClientQualityReport> _reportsFor(Iterable<String>? clientIds) =>
      clientIds == null
          ? _reports.values
          : clientIds
              .map((clientId) => _reports[clientId.trim()])
              .whereType<ClientQualityReport>();
}
