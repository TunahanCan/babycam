enum StreamBackpressureKind { generic, video, audio }

class StreamBackpressureMetrics {
  const StreamBackpressureMetrics({
    this.skippedWrites = 0,
    this.skippedVideoFrames = 0,
    this.skippedAudioChunks = 0,
    this.lastSuccessfulVideoWriteAtMs,
    this.lastSuccessfulAudioWriteAtMs,
    this.consecutiveWriteFailures = 0,
    this.lastWriteDurationMs,
    this.averageWriteDurationMs,
  });

  final int skippedWrites;
  final int skippedVideoFrames;
  final int skippedAudioChunks;
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
  int? lastSuccessfulVideoWriteAtMs;
  int? lastSuccessfulAudioWriteAtMs;
  int consecutiveWriteFailures = 0;
  int? lastWriteDurationMs;
  double? averageWriteDurationMs;

  StreamBackpressureMetrics snapshot() => StreamBackpressureMetrics(
        skippedWrites: skippedWrites,
        skippedVideoFrames: skippedVideoFrames,
        skippedAudioChunks: skippedAudioChunks,
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
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final StreamBackpressureKind kind;
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
      case StreamBackpressureKind.audio:
        metrics.lastSuccessfulAudioWriteAtMs = nowMs;
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
      case StreamBackpressureKind.audio:
        metrics.skippedAudioChunks++;
      case StreamBackpressureKind.generic:
        break;
    }
  }
}
