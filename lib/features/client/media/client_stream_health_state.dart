import '../../../core/media/adaptive_media_profile.dart';
import '../../../core/media/media_session_telemetry.dart';

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
    this.skippedVideoFrames = 0,
    this.coalescedVideoFrames = 0,
    this.skippedAudioChunks = 0,
    this.videoJitterMs,
    this.videoQueueDelayMs,
    this.audioPipeline = const {},
    this.mediaTelemetry = const {},
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
  final int skippedVideoFrames;
  final int coalescedVideoFrames;
  final int skippedAudioChunks;
  final double? videoJitterMs;
  final int? videoQueueDelayMs;
  final Map<String, Object?> audioPipeline;
  final Map<String, Object?> mediaTelemetry;

  NetworkQualityTier get healthTier {
    if (streamTimedOut ||
        audioUnderrun ||
        skippedAudioChunks >= 3 ||
        _atLeast(videoQueueDelayMs, 400) ||
        _atLeastDouble(videoJitterMs, 120) ||
        _atLeast(videoFrameGapMs, 5000) ||
        _atLeast(audioGapMs, 1500) ||
        reconnectCount >= 3 ||
        wsDisconnectCount >= 3) {
      return NetworkQualityTier.critical;
    }
    if (_atLeast(videoFrameGapMs, 2000) ||
        _atLeast(audioGapMs, 1000) ||
        skippedVideoFrames >= 3 ||
        skippedAudioChunks > 0 ||
        _atLeast(videoQueueDelayMs, 150) ||
        _atLeastDouble(videoJitterMs, 60) ||
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
        'skippedFrames': skippedVideoFrames,
        'skippedVideoFrames': skippedVideoFrames,
        'coalescedVideoFrames': coalescedVideoFrames,
        'skippedAudioChunks': skippedAudioChunks,
        'videoJitterMs': videoJitterMs,
        'videoQueueDelayMs': videoQueueDelayMs,
        'wsDisconnectCount': wsDisconnectCount,
        'reconnectCount': reconnectCount,
        'streamTimedOut': streamTimedOut,
        'audioUnderrun': audioUnderrun,
        'watchActive': watchActive,
        'recentlyReconnected': recentlyReconnected,
        'audioPipeline': audioPipeline,
        'mediaTelemetry': mediaTelemetry,
        'createdAtMs': createdAtMs,
      };

  static bool _atLeast(int? value, int threshold) =>
      value != null && value >= threshold;

  static bool _atLeastDouble(double? value, double threshold) =>
      value != null && value >= threshold;
}

class ClientStreamHealthState {
  ClientStreamHealthState({
    int Function()? nowMs,
    this.videoWeakGap = const Duration(seconds: 2),
    this.videoCriticalGap = const Duration(seconds: 5),
    this.audioWeakGap = const Duration(seconds: 1),
    this.audioCriticalGap = const Duration(milliseconds: 1500),
    this.recentReconnectWindow = const Duration(seconds: 10),
    this.qualityEventWindow = const Duration(seconds: 8),
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _nowMs;
  final Duration videoWeakGap;
  final Duration videoCriticalGap;
  final Duration audioWeakGap;
  final Duration audioCriticalGap;
  final Duration recentReconnectWindow;
  final Duration qualityEventWindow;

  int? _watchStartedAtMs;
  int? _lastVideoFrameAtMs;
  int? _lastAudioChunkAtMs;
  int? _lastReconnectAtMs;
  final _wsDisconnectEventsMs = <int>[];
  final _reconnectEventsMs = <int>[];
  final _videoSkipEvents = <({int atMs, int count})>[];
  final _videoCoalesceEvents = <({int atMs, int count})>[];
  final _audioSkipEvents = <({int atMs, int count})>[];
  var _streamTimedOut = false;
  var _audioUnderrun = false;
  var _watchActive = false;
  Map<String, Object?> _audioPipeline = const {};
  int _lastAudioDropTotal = 0;
  int? _lastNativeWritesDropped;
  int _nativeWritesDroppedSinceReset = 0;
  int? _lastNativeUnderrunCount;
  int? _lastNativeAudioStarts;
  int _nativeUnderrunsSinceReset = 0;
  bool _nativeUnderrunAwaitingReset = false;
  double? _videoJitterMs;
  int? _videoQueueDelayMs;

  bool get watchActive => _watchActive;

  void setWatchActive(bool active) {
    _watchActive = active;
    if (active) {
      _watchStartedAtMs ??= _nowMs();
    } else {
      _watchStartedAtMs = null;
      _streamTimedOut = false;
      _audioUnderrun = false;
      _audioPipeline = const {};
      _resetAudioDropTracking();
    }
  }

  void markVideoFrameReceived() {
    _lastVideoFrameAtMs = _nowMs();
    _streamTimedOut = false;
  }

  void markVideoFramesSkipped(int count) {
    if (count <= 0) return;
    _videoSkipEvents.add((atMs: _nowMs(), count: count));
  }

  /// Records frames intentionally collapsed by the client's latest-frame
  /// mailbox. This is diagnostic only and must not lower the network tier.
  void markVideoFramesCoalesced(int count) {
    if (count <= 0) return;
    _videoCoalesceEvents.add((atMs: _nowMs(), count: count));
  }

  void updateVideoTransport({
    required double jitterMs,
    required int queueDelayMs,
  }) {
    _videoJitterMs = jitterMs;
    _videoQueueDelayMs = queueDelayMs;
  }

  void markAudioChunkReceived() {
    _lastAudioChunkAtMs = _nowMs();
    _audioUnderrun = false;
  }

  void markWsConnected() {}

  void markWsDisconnected() {
    _wsDisconnectEventsMs.add(_nowMs());
  }

  void markReconnectAttempt() {
    final nowMs = _nowMs();
    _reconnectEventsMs.add(nowMs);
    _lastReconnectAtMs = nowMs;
  }

  void markStreamTimeout() {
    _streamTimedOut = true;
  }

  void markAudioUnderrun() {
    _audioUnderrun = true;
  }

  void updateAudioPipelineStatus(Map<String, Object?> status) {
    _audioPipeline = Map<String, Object?>.unmodifiable(status);
    final nativeStatus = _mapValue(status['native']);
    _observeNativeWritesDropped(
      _nullableIntValue(nativeStatus?['writesDropped']),
    );
    _observeNativeUnderruns(
      count: _nullableIntValue(nativeStatus?['underrunCount']),
      starts: _nullableIntValue(nativeStatus?['starts']),
    );

    final effectiveNativeDrops = _maxInt(
      _intValue(status['droppedNativeWrites']),
      _nativeWritesDroppedSinceReset,
    );
    final effectiveUnderruns = _maxInt(
      _intValue(status['playoutUnderruns']),
      _nativeUnderrunsSinceReset,
    );
    final dropTotal = _intValue(status['droppedBufferFrames']) +
        effectiveNativeDrops +
        effectiveUnderruns;
    if (dropTotal <= _lastAudioDropTotal) return;
    final delta = dropTotal - _lastAudioDropTotal;
    _lastAudioDropTotal = dropTotal;
    _audioSkipEvents.add((atMs: _nowMs(), count: delta));
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
    final wsDisconnectCount = _recentTimesCount(
      _wsDisconnectEventsMs,
      nowMs,
      recentReconnectWindow,
    );
    final reconnectCount = _recentTimesCount(
      _reconnectEventsMs,
      nowMs,
      recentReconnectWindow,
    );
    final skippedVideoFrames = _recentEventCount(_videoSkipEvents, nowMs);
    final coalescedVideoFrames = _recentEventCount(_videoCoalesceEvents, nowMs);
    final skippedAudioChunks = _recentEventCount(_audioSkipEvents, nowMs);
    return ClientQualitySnapshot(
      createdAtMs: nowMs,
      lastVideoFrameAtMs: _lastVideoFrameAtMs,
      lastAudioChunkAtMs: _lastAudioChunkAtMs,
      videoFrameGapMs: videoGapMs,
      audioGapMs: audioGapMs,
      wsDisconnectCount: wsDisconnectCount,
      reconnectCount: reconnectCount,
      streamTimedOut: streamTimedOut,
      audioUnderrun: audioUnderrun,
      watchActive: _watchActive,
      recentlyReconnected: _recentlyReconnected(nowMs),
      skippedVideoFrames: skippedVideoFrames,
      coalescedVideoFrames: coalescedVideoFrames,
      skippedAudioChunks: skippedAudioChunks,
      videoJitterMs: _videoJitterMs,
      videoQueueDelayMs: _videoQueueDelayMs,
      audioPipeline: _audioPipeline,
      mediaTelemetry: MediaSessionTelemetry.shared.snapshot().toJson(),
    );
  }

  void resetForNewWatchSession() {
    MediaSessionTelemetry.shared.reset();
    _watchStartedAtMs = _nowMs();
    _lastVideoFrameAtMs = null;
    _lastAudioChunkAtMs = null;
    _lastReconnectAtMs = null;
    _wsDisconnectEventsMs.clear();
    _reconnectEventsMs.clear();
    _videoSkipEvents.clear();
    _videoCoalesceEvents.clear();
    _audioSkipEvents.clear();
    _streamTimedOut = false;
    _audioUnderrun = false;
    _audioPipeline = const {};
    _resetAudioDropTracking();
    _videoJitterMs = null;
    _videoQueueDelayMs = null;
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

  int _recentTimesCount(List<int> events, int nowMs, Duration window) {
    final cutoff = nowMs - window.inMilliseconds;
    events.removeWhere((eventMs) => eventMs < cutoff);
    return events.length;
  }

  int _recentEventCount(
    List<({int atMs, int count})> events,
    int nowMs,
  ) {
    final cutoff = nowMs - qualityEventWindow.inMilliseconds;
    events.removeWhere((event) => event.atMs < cutoff);
    return events.fold(0, (total, event) => total + event.count);
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  int? _nullableIntValue(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<Object?, Object?>? _mapValue(Object? value) =>
      value is Map ? value : null;

  void _observeNativeWritesDropped(int? value) {
    if (value == null || value < 0) return;
    final previous = _lastNativeWritesDropped;
    if (previous == null) {
      _lastNativeWritesDropped = value;
      return;
    }
    if (value <= previous) return;
    _nativeWritesDroppedSinceReset += value - previous;
    _lastNativeWritesDropped = value;
  }

  void _observeNativeUnderruns({required int? count, required int? starts}) {
    if (count == null || count < 0) return;
    final previous = _lastNativeUnderrunCount;
    if (previous == null) {
      _lastNativeUnderrunCount = count;
      _lastNativeAudioStarts = starts;
      return;
    }

    final previousStarts = _lastNativeAudioStarts;
    if (starts != null && previousStarts != null) {
      if (starts < previousStarts) return;
      if (starts > previousStarts) {
        _lastNativeAudioStarts = starts;
        _lastNativeUnderrunCount = count;
        _nativeUnderrunAwaitingReset = count > 0;
        return;
      }
    } else if (starts != null) {
      _lastNativeAudioStarts = starts;
    }

    if (_nativeUnderrunAwaitingReset) {
      if (count < previous) {
        _lastNativeUnderrunCount = count;
        _nativeUnderrunAwaitingReset = false;
        return;
      }
      if (count == previous) return;
      _nativeUnderrunAwaitingReset = false;
    }

    if (count <= previous) return;
    _nativeUnderrunsSinceReset += count - previous;
    _lastNativeUnderrunCount = count;
  }

  void _resetAudioDropTracking() {
    _lastAudioDropTotal = 0;
    _lastNativeWritesDropped = null;
    _nativeWritesDroppedSinceReset = 0;
    _lastNativeUnderrunCount = null;
    _lastNativeAudioStarts = null;
    _nativeUnderrunsSinceReset = 0;
    _nativeUnderrunAwaitingReset = false;
  }

  int _maxInt(int left, int right) => left >= right ? left : right;
}
