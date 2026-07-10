import 'dart:collection';
import 'dart:math';

/// Process-local monotonic clock shared by capture, codec and presentation
/// instrumentation. Monotonic timestamps are safe across wall-clock changes;
/// wall-clock timestamps remain part of the wire format for cross-device
/// transit estimates.
class MediaMonotonicClock {
  MediaMonotonicClock._() : _stopwatch = Stopwatch()..start();

  static final MediaMonotonicClock shared = MediaMonotonicClock._();

  final Stopwatch _stopwatch;

  int get nowUs => _stopwatch.elapsedMicroseconds;
}

abstract final class MediaMetricName {
  static const videoEncode = 'video.encode';
  static const videoCaptureToEncode = 'video.capture_to_encode';
  static const videoCaptureToReceive = 'video.capture_to_receive';
  static const videoNetworkTransit = 'video.network_transit';
  static const videoSend = 'video.send';
  static const videoDecode = 'video.decode';
  static const videoPresent = 'video.present';
  static const audioSend = 'audio.send';
  static const audioOutputWrite = 'audio.output_write';
  static const audioStartupToPlayout = 'audio.startup_to_playout';

  static const videoCapturedCount = 'video.captured.count';
  static const videoEncodedCount = 'video.encoded.count';
  static const videoDroppedBeforeEncodeCount =
      'video.dropped_before_encode.count';
  static const videoSkippedTransportCount = 'video.skipped_transport.count';
  static const videoCoalescedPresentationCount =
      'video.coalesced_presentation.count';
  static const audioUnderrunCount = 'audio.underrun.count';
  static const audioCapturedCount = 'audio.captured.count';
  static const audioDroppedCount = 'audio.dropped.count';
  static const reconnectCount = 'transport.reconnect.count';
}

/// Bounded, session-scoped latency and reliability telemetry.
///
/// A bounded sample window prevents a long-running baby monitor session from
/// accumulating memory. Percentiles are calculated only when a snapshot is
/// requested, keeping the hot frame/audio paths O(1).
class MediaSessionTelemetry {
  MediaSessionTelemetry({
    this.maxSamplesPerMetric = 1024,
    MediaMonotonicClock? clock,
  })  : assert(maxSamplesPerMetric > 0),
        _clock = clock ?? MediaMonotonicClock.shared;

  static final MediaSessionTelemetry shared = MediaSessionTelemetry();

  final int maxSamplesPerMetric;
  final MediaMonotonicClock _clock;
  final Map<String, _BoundedMetricSamples> _durations = {};
  final Map<String, int> _counters = {};
  int _generation = 0;
  int _startedAtEpochMs = DateTime.now().millisecondsSinceEpoch;

  int get nowUs => _clock.nowUs;
  int get generation => _generation;

  void recordDurationUs(String metric, int durationUs) {
    if (durationUs < 0) return;
    (_durations[metric] ??= _BoundedMetricSamples(maxSamplesPerMetric))
        .add(durationUs);
  }

  void recordDuration(String metric, Duration duration) =>
      recordDurationUs(metric, duration.inMicroseconds);

  T measureSync<T>(String metric, T Function() operation) {
    final startedAtUs = nowUs;
    try {
      return operation();
    } finally {
      recordDurationUs(metric, nowUs - startedAtUs);
    }
  }

  Future<T> measure<T>(String metric, Future<T> Function() operation) async {
    final startedAtUs = nowUs;
    try {
      return await operation();
    } finally {
      recordDurationUs(metric, nowUs - startedAtUs);
    }
  }

  void increment(String counter, [int delta = 1]) {
    if (delta <= 0) return;
    _counters[counter] = (_counters[counter] ?? 0) + delta;
  }

  int counter(String name) => _counters[name] ?? 0;

  MediaSessionTelemetrySnapshot snapshot() => MediaSessionTelemetrySnapshot(
        generation: _generation,
        startedAtEpochMs: _startedAtEpochMs,
        capturedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        distributions: Map.unmodifiable({
          for (final entry in _durations.entries)
            entry.key: entry.value.snapshot(),
        }),
        counters: Map.unmodifiable(Map<String, int>.from(_counters)),
      );

  void reset() {
    _durations.clear();
    _counters.clear();
    _generation++;
    _startedAtEpochMs = DateTime.now().millisecondsSinceEpoch;
  }
}

class MediaSessionTelemetrySnapshot {
  const MediaSessionTelemetrySnapshot({
    required this.generation,
    required this.startedAtEpochMs,
    required this.capturedAtEpochMs,
    required this.distributions,
    required this.counters,
  });

  final int generation;
  final int startedAtEpochMs;
  final int capturedAtEpochMs;
  final Map<String, MediaPercentileSnapshot> distributions;
  final Map<String, int> counters;

  MediaPercentileSnapshot? distribution(String name) => distributions[name];

  Map<String, Object?> toJson() => {
        'generation': generation,
        'startedAtEpochMs': startedAtEpochMs,
        'capturedAtEpochMs': capturedAtEpochMs,
        'durations': {
          for (final entry in distributions.entries)
            entry.key: entry.value.toJson(),
        },
        'counters': counters,
      };
}

class MediaPercentileSnapshot {
  const MediaPercentileSnapshot({
    required this.count,
    required this.sampleCount,
    required this.minUs,
    required this.maxUs,
    required this.averageUs,
    required this.p50Us,
    required this.p95Us,
    required this.p99Us,
  });

  final int count;
  final int sampleCount;
  final int minUs;
  final int maxUs;
  final double averageUs;
  final int p50Us;
  final int p95Us;
  final int p99Us;

  double get p50Ms => p50Us / 1000;
  double get p95Ms => p95Us / 1000;
  double get p99Ms => p99Us / 1000;

  Map<String, Object?> toJson() => {
        'count': count,
        'sampleCount': sampleCount,
        'minMs': minUs / 1000,
        'maxMs': maxUs / 1000,
        'averageMs': averageUs / 1000,
        'p50Ms': p50Ms,
        'p95Ms': p95Ms,
        'p99Ms': p99Ms,
      };
}

class _BoundedMetricSamples {
  _BoundedMetricSamples(this.capacity);

  final int capacity;
  final Queue<int> _samples = Queue<int>();
  int _count = 0;
  int _sumUs = 0;
  int? _minUs;
  int? _maxUs;

  void add(int valueUs) {
    _count++;
    _sumUs += valueUs;
    _minUs = _minUs == null ? valueUs : min(_minUs!, valueUs);
    _maxUs = _maxUs == null ? valueUs : max(_maxUs!, valueUs);
    if (_samples.length == capacity) _samples.removeFirst();
    _samples.addLast(valueUs);
  }

  MediaPercentileSnapshot snapshot() {
    final sorted = _samples.toList(growable: false)..sort();
    if (sorted.isEmpty) {
      return const MediaPercentileSnapshot(
        count: 0,
        sampleCount: 0,
        minUs: 0,
        maxUs: 0,
        averageUs: 0,
        p50Us: 0,
        p95Us: 0,
        p99Us: 0,
      );
    }
    return MediaPercentileSnapshot(
      count: _count,
      sampleCount: sorted.length,
      minUs: _minUs!,
      maxUs: _maxUs!,
      averageUs: _sumUs / _count,
      p50Us: _percentile(sorted, .50),
      p95Us: _percentile(sorted, .95),
      p99Us: _percentile(sorted, .99),
    );
  }

  static int _percentile(List<int> sorted, double percentile) {
    final index = ((sorted.length - 1) * percentile).ceil();
    return sorted[index.clamp(0, sorted.length - 1)];
  }
}
