enum StreamBackpressureKind { generic, video, audio }

StreamBackpressureMetrics combineBackpressureMetrics(
  Iterable<StreamBackpressureMetrics> metrics,
) {
  int? maxInt(int? current, int? next) {
    if (current == null) return next;
    if (next == null) return current;
    return next > current ? next : current;
  }

  double? maxDouble(double? current, double? next) {
    if (current == null) return next;
    if (next == null) return current;
    return next > current ? next : current;
  }

  var skippedWrites = 0;
  var skippedVideoFrames = 0;
  var skippedAudioChunks = 0;
  var consecutiveSkippedVideoFrames = 0;
  var consecutiveSkippedAudioChunks = 0;
  var consecutiveWriteFailures = 0;
  int? lastSkippedVideoFrameAtMs;
  int? lastSkippedAudioChunkAtMs;
  int? lastSuccessfulVideoWriteAtMs;
  int? lastSuccessfulAudioWriteAtMs;
  int? lastWriteDurationMs;
  double? averageWriteDurationMs;
  for (final metric in metrics) {
    skippedWrites += metric.skippedWrites;
    skippedVideoFrames += metric.skippedVideoFrames;
    skippedAudioChunks += metric.skippedAudioChunks;
    consecutiveSkippedVideoFrames = maxInt(
          consecutiveSkippedVideoFrames,
          metric.consecutiveSkippedVideoFrames,
        ) ??
        0;
    consecutiveSkippedAudioChunks = maxInt(
          consecutiveSkippedAudioChunks,
          metric.consecutiveSkippedAudioChunks,
        ) ??
        0;
    consecutiveWriteFailures += metric.consecutiveWriteFailures;
    lastSkippedVideoFrameAtMs = maxInt(
      lastSkippedVideoFrameAtMs,
      metric.lastSkippedVideoFrameAtMs,
    );
    lastSkippedAudioChunkAtMs = maxInt(
      lastSkippedAudioChunkAtMs,
      metric.lastSkippedAudioChunkAtMs,
    );
    lastSuccessfulVideoWriteAtMs = maxInt(
      lastSuccessfulVideoWriteAtMs,
      metric.lastSuccessfulVideoWriteAtMs,
    );
    lastSuccessfulAudioWriteAtMs = maxInt(
      lastSuccessfulAudioWriteAtMs,
      metric.lastSuccessfulAudioWriteAtMs,
    );
    lastWriteDurationMs =
        maxInt(lastWriteDurationMs, metric.lastWriteDurationMs);
    averageWriteDurationMs = maxDouble(
      averageWriteDurationMs,
      metric.averageWriteDurationMs,
    );
  }
  return StreamBackpressureMetrics(
    skippedWrites: skippedWrites,
    skippedVideoFrames: skippedVideoFrames,
    skippedAudioChunks: skippedAudioChunks,
    consecutiveSkippedVideoFrames: consecutiveSkippedVideoFrames,
    consecutiveSkippedAudioChunks: consecutiveSkippedAudioChunks,
    lastSkippedVideoFrameAtMs: lastSkippedVideoFrameAtMs,
    lastSkippedAudioChunkAtMs: lastSkippedAudioChunkAtMs,
    lastSuccessfulVideoWriteAtMs: lastSuccessfulVideoWriteAtMs,
    lastSuccessfulAudioWriteAtMs: lastSuccessfulAudioWriteAtMs,
    consecutiveWriteFailures: consecutiveWriteFailures,
    lastWriteDurationMs: lastWriteDurationMs,
    averageWriteDurationMs: averageWriteDurationMs,
  );
}

class StreamBackpressureMetrics {
  const StreamBackpressureMetrics({
    this.skippedWrites = 0,
    this.skippedVideoFrames = 0,
    this.skippedAudioChunks = 0,
    this.consecutiveSkippedVideoFrames = 0,
    this.consecutiveSkippedAudioChunks = 0,
    this.lastSkippedVideoFrameAtMs,
    this.lastSkippedAudioChunkAtMs,
    this.lastSuccessfulVideoWriteAtMs,
    this.lastSuccessfulAudioWriteAtMs,
    this.consecutiveWriteFailures = 0,
    this.lastWriteDurationMs,
    this.averageWriteDurationMs,
  });

  final int skippedWrites;
  final int skippedVideoFrames;
  final int skippedAudioChunks;
  final int consecutiveSkippedVideoFrames;
  final int consecutiveSkippedAudioChunks;
  final int? lastSkippedVideoFrameAtMs;
  final int? lastSkippedAudioChunkAtMs;
  final int? lastSuccessfulVideoWriteAtMs;
  final int? lastSuccessfulAudioWriteAtMs;
  final int consecutiveWriteFailures;
  final int? lastWriteDurationMs;
  final double? averageWriteDurationMs;
}

class _MutableStreamBackpressureMetrics {
  int skippedWrites = 0;
  int skippedVideoFrames = 0;
  int skippedAudioChunks = 0;
  int consecutiveSkippedVideoFrames = 0;
  int consecutiveSkippedAudioChunks = 0;
  int? lastSkippedVideoFrameAtMs;
  int? lastSkippedAudioChunkAtMs;
  int? lastSuccessfulVideoWriteAtMs;
  int? lastSuccessfulAudioWriteAtMs;
  int consecutiveWriteFailures = 0;
  int? lastWriteDurationMs;
  double? averageWriteDurationMs;

  StreamBackpressureMetrics snapshot() => StreamBackpressureMetrics(
        skippedWrites: skippedWrites,
        skippedVideoFrames: skippedVideoFrames,
        skippedAudioChunks: skippedAudioChunks,
        consecutiveSkippedVideoFrames: consecutiveSkippedVideoFrames,
        consecutiveSkippedAudioChunks: consecutiveSkippedAudioChunks,
        lastSkippedVideoFrameAtMs: lastSkippedVideoFrameAtMs,
        lastSkippedAudioChunkAtMs: lastSkippedAudioChunkAtMs,
        lastSuccessfulVideoWriteAtMs: lastSuccessfulVideoWriteAtMs,
        lastSuccessfulAudioWriteAtMs: lastSuccessfulAudioWriteAtMs,
        consecutiveWriteFailures: consecutiveWriteFailures,
        lastWriteDurationMs: lastWriteDurationMs,
        averageWriteDurationMs: averageWriteDurationMs,
      );
}

class StreamBackpressureGate<T extends Object> {
  StreamBackpressureGate({
    this.kind = StreamBackpressureKind.generic,
    this.audioSkipRecoveryCooldown = const Duration(milliseconds: 300),
    int Function()? nowMs,
  })  : assert(!audioSkipRecoveryCooldown.isNegative),
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final StreamBackpressureKind kind;
  final Duration audioSkipRecoveryCooldown;
  final int Function() _nowMs;
  final _busyClients = <T>{};
  final _metrics = <T, _MutableStreamBackpressureMetrics>{};

  bool tryMarkBusy(T client) {
    final added = _busyClients.add(client);
    if (!added) _recordSkip(client);
    return added;
  }

  void markIdle(T client) {
    _busyClients.remove(client);
  }

  bool isBusy(T client) => _busyClients.contains(client);

  void remove(T client) {
    _busyClients.remove(client);
    _metrics.remove(client);
  }

  void clear() {
    _busyClients.clear();
    _metrics.clear();
  }

  int get busyCount => _busyClients.length;

  StreamBackpressureMetrics metricsFor(T client) =>
      (_metrics[client] ?? _MutableStreamBackpressureMetrics()).snapshot();

  StreamBackpressureMetrics aggregateMetrics() {
    final total = _MutableStreamBackpressureMetrics();
    for (final metrics in _metrics.values) {
      total.skippedWrites += metrics.skippedWrites;
      total.skippedVideoFrames += metrics.skippedVideoFrames;
      total.skippedAudioChunks += metrics.skippedAudioChunks;
      total.consecutiveSkippedVideoFrames = _maxInt(
        total.consecutiveSkippedVideoFrames,
        metrics.consecutiveSkippedVideoFrames,
      );
      total.consecutiveSkippedAudioChunks = _maxInt(
        total.consecutiveSkippedAudioChunks,
        metrics.consecutiveSkippedAudioChunks,
      );
      total.lastSkippedVideoFrameAtMs = _maxNullable(
        total.lastSkippedVideoFrameAtMs,
        metrics.lastSkippedVideoFrameAtMs,
      );
      total.lastSkippedAudioChunkAtMs = _maxNullable(
        total.lastSkippedAudioChunkAtMs,
        metrics.lastSkippedAudioChunkAtMs,
      );
      total.consecutiveWriteFailures += metrics.consecutiveWriteFailures;
      total.lastSuccessfulVideoWriteAtMs = _maxNullable(
        total.lastSuccessfulVideoWriteAtMs,
        metrics.lastSuccessfulVideoWriteAtMs,
      );
      total.lastSuccessfulAudioWriteAtMs = _maxNullable(
        total.lastSuccessfulAudioWriteAtMs,
        metrics.lastSuccessfulAudioWriteAtMs,
      );
      total.lastWriteDurationMs = _maxNullable(
        total.lastWriteDurationMs,
        metrics.lastWriteDurationMs,
      );
      total.averageWriteDurationMs = _maxNullableDouble(
        total.averageWriteDurationMs,
        metrics.averageWriteDurationMs,
      );
    }
    return total.snapshot();
  }

  void recordSkippedVideoFrame(T client) {
    final metrics = _metricsFor(client);
    metrics.skippedWrites++;
    metrics.skippedVideoFrames++;
    metrics.consecutiveSkippedVideoFrames++;
    metrics.lastSkippedVideoFrameAtMs = _nowMs();
  }

  void recordSkippedAudioChunk(T client) {
    final metrics = _metricsFor(client);
    metrics.skippedWrites++;
    metrics.skippedAudioChunks++;
    metrics.consecutiveSkippedAudioChunks++;
    metrics.lastSkippedAudioChunkAtMs = _nowMs();
  }

  void recordSuccess(T client, {required Duration duration}) {
    final metrics = _metricsFor(client);
    metrics.consecutiveWriteFailures = 0;
    metrics.lastWriteDurationMs = duration.inMilliseconds;
    metrics.averageWriteDurationMs = metrics.averageWriteDurationMs == null
        ? duration.inMilliseconds.toDouble()
        : (metrics.averageWriteDurationMs! * 0.8) +
            (duration.inMilliseconds * 0.2);
    final nowMs = _nowMs();
    switch (kind) {
      case StreamBackpressureKind.video:
        metrics.lastSuccessfulVideoWriteAtMs = nowMs;
        metrics.consecutiveSkippedVideoFrames = 0;
      case StreamBackpressureKind.audio:
        metrics.lastSuccessfulAudioWriteAtMs = nowMs;
        final lastSkipAtMs = metrics.lastSkippedAudioChunkAtMs;
        if (lastSkipAtMs == null ||
            nowMs - lastSkipAtMs >= audioSkipRecoveryCooldown.inMilliseconds) {
          metrics.consecutiveSkippedAudioChunks = 0;
        }
      case StreamBackpressureKind.generic:
        break;
    }
  }

  void recordFailure(T client) {
    _metricsFor(client).consecutiveWriteFailures++;
  }

  _MutableStreamBackpressureMetrics _metricsFor(T client) =>
      _metrics.putIfAbsent(client, _MutableStreamBackpressureMetrics.new);

  void _recordSkip(T client) {
    final metrics = _metricsFor(client);
    metrics.skippedWrites++;
    switch (kind) {
      case StreamBackpressureKind.video:
        metrics.skippedVideoFrames++;
        metrics.consecutiveSkippedVideoFrames++;
        metrics.lastSkippedVideoFrameAtMs = _nowMs();
      case StreamBackpressureKind.audio:
        metrics.skippedAudioChunks++;
        metrics.consecutiveSkippedAudioChunks++;
        metrics.lastSkippedAudioChunkAtMs = _nowMs();
      case StreamBackpressureKind.generic:
        break;
    }
  }

  int? _maxNullable(int? current, int? next) {
    if (current == null) return next;
    if (next == null) return current;
    return next > current ? next : current;
  }

  double? _maxNullableDouble(double? current, double? next) {
    if (current == null) return next;
    if (next == null) return current;
    return next > current ? next : current;
  }

  int _maxInt(int current, int next) => next > current ? next : current;
}
