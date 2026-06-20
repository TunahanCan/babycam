import '../../../core/media/adaptive_media_profile.dart';

class ClientQualitySnapshot {
  const ClientQualitySnapshot({
    required this.createdAtMs,
    this.lastVideoFrameAtMs,
    this.lastAudioChunkAtMs,
    this.videoFrameGapMs,
    this.audioGapMs,
    this.wsDisconnectCount = 0,
    this.reconnectCount = 0,
    this.streamTimedOut = false,
    this.audioUnderrun = false,
    this.watchActive = false,
    this.recentlyReconnected = false,
  });

  final int createdAtMs;
  final int? lastVideoFrameAtMs;
  final int? lastAudioChunkAtMs;
  final int? videoFrameGapMs;
  final int? audioGapMs;
  final int wsDisconnectCount;
  final int reconnectCount;
  final bool streamTimedOut;
  final bool audioUnderrun;
  final bool watchActive;
  final bool recentlyReconnected;

  NetworkQualityTier get healthTier {
    if (streamTimedOut ||
        audioUnderrun ||
        _atLeast(videoFrameGapMs, 5000) ||
        _atLeast(audioGapMs, 1500) ||
        reconnectCount >= 3 ||
        wsDisconnectCount >= 3) {
      return NetworkQualityTier.critical;
    }
    if (_atLeast(videoFrameGapMs, 2000) ||
        _atLeast(audioGapMs, 1000) ||
        wsDisconnectCount > 0 ||
        reconnectCount > 0 ||
        recentlyReconnected) {
      return NetworkQualityTier.weak;
    }
    if (lastVideoFrameAtMs != null || lastAudioChunkAtMs != null) {
      return NetworkQualityTier.excellent;
    }
    return NetworkQualityTier.unknown;
  }

  Map<String, Object?> toQualityReportJson({
    required String clientId,
    required NetworkQualityTier networkTier,
    int? rttMs,
    int consecutiveFailures = 0,
  }) =>
      {
        'clientId': clientId,
        'tier': networkTier.name,
        'networkTier': networkTier.name,
        'rttMs': rttMs,
        'consecutiveFailures': consecutiveFailures,
        'videoFrameGapMs': videoFrameGapMs,
        'audioGapMs': audioGapMs,
        'wsDisconnectCount': wsDisconnectCount,
        'reconnectCount': reconnectCount,
        'streamTimedOut': streamTimedOut,
        'audioUnderrun': audioUnderrun,
        'watchActive': watchActive,
        'recentlyReconnected': recentlyReconnected,
        'createdAtMs': createdAtMs,
      };

  static bool _atLeast(int? value, int threshold) =>
      value != null && value >= threshold;
}

class ClientStreamHealthMonitor {
  ClientStreamHealthMonitor({
    int Function()? nowMs,
    this.videoWeakGap = const Duration(seconds: 2),
    this.videoCriticalGap = const Duration(seconds: 5),
    this.audioWeakGap = const Duration(seconds: 1),
    this.audioCriticalGap = const Duration(milliseconds: 1500),
    this.recentReconnectWindow = const Duration(seconds: 10),
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _nowMs;
  final Duration videoWeakGap;
  final Duration videoCriticalGap;
  final Duration audioWeakGap;
  final Duration audioCriticalGap;
  final Duration recentReconnectWindow;

  int? _watchStartedAtMs;
  int? _lastVideoFrameAtMs;
  int? _lastAudioChunkAtMs;
  int? _lastReconnectAtMs;
  var _wsDisconnectCount = 0;
  var _reconnectCount = 0;
  var _streamTimedOut = false;
  var _audioUnderrun = false;
  var _watchActive = false;

  bool get watchActive => _watchActive;

  void setWatchActive(bool active) {
    _watchActive = active;
    if (active) {
      _watchStartedAtMs ??= _nowMs();
    } else {
      _watchStartedAtMs = null;
      _streamTimedOut = false;
      _audioUnderrun = false;
    }
  }

  void markVideoFrameReceived() {
    _lastVideoFrameAtMs = _nowMs();
    _streamTimedOut = false;
  }

  void markAudioChunkReceived() {
    _lastAudioChunkAtMs = _nowMs();
    _audioUnderrun = false;
  }

  void markWsConnected() {}

  void markWsDisconnected() {
    _wsDisconnectCount++;
  }

  void markReconnectAttempt() {
    _reconnectCount++;
    _lastReconnectAtMs = _nowMs();
  }

  void markStreamTimeout() {
    _streamTimedOut = true;
  }

  void markAudioUnderrun() {
    _audioUnderrun = true;
  }

  ClientQualitySnapshot snapshot() {
    final nowMs = _nowMs();
    final videoGapMs = _gapMs(
      nowMs: nowMs,
      lastEventAtMs: _lastVideoFrameAtMs,
      fallbackStartedAtMs: _watchStartedAtMs,
    );
    final audioGapMs =
        _lastAudioChunkAtMs == null ? null : nowMs - _lastAudioChunkAtMs!;
    final streamTimedOut =
        _streamTimedOut || _atLeast(videoGapMs, videoCriticalGap);
    final audioUnderrun =
        _audioUnderrun || _atLeast(audioGapMs, audioCriticalGap);
    return ClientQualitySnapshot(
      createdAtMs: nowMs,
      lastVideoFrameAtMs: _lastVideoFrameAtMs,
      lastAudioChunkAtMs: _lastAudioChunkAtMs,
      videoFrameGapMs: videoGapMs,
      audioGapMs: audioGapMs,
      wsDisconnectCount: _wsDisconnectCount,
      reconnectCount: _reconnectCount,
      streamTimedOut: streamTimedOut,
      audioUnderrun: audioUnderrun,
      watchActive: _watchActive,
      recentlyReconnected: _recentlyReconnected(nowMs),
    );
  }

  void resetForNewWatchSession() {
    _watchStartedAtMs = _nowMs();
    _lastVideoFrameAtMs = null;
    _lastAudioChunkAtMs = null;
    _lastReconnectAtMs = null;
    _wsDisconnectCount = 0;
    _reconnectCount = 0;
    _streamTimedOut = false;
    _audioUnderrun = false;
    _watchActive = true;
  }

  int? _gapMs({
    required int nowMs,
    required int? lastEventAtMs,
    required int? fallbackStartedAtMs,
  }) {
    final from = lastEventAtMs ?? (_watchActive ? fallbackStartedAtMs : null);
    return from == null ? null : nowMs - from;
  }

  bool _recentlyReconnected(int nowMs) =>
      _lastReconnectAtMs != null &&
      nowMs - _lastReconnectAtMs! <= recentReconnectWindow.inMilliseconds;

  bool _atLeast(int? value, Duration threshold) =>
      value != null && value >= threshold.inMilliseconds;
}
