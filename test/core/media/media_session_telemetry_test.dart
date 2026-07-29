import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/media_session_telemetry.dart';

void main() {
  test('bounded telemetry reports p50 p95 p99 and lifetime count', () {
    final telemetry = MediaSessionTelemetry(maxSamplesPerMetric: 5);
    for (var milliseconds = 1; milliseconds <= 10; milliseconds++) {
      telemetry.recordDurationUs('latency', milliseconds * 1000);
    }

    final metric = telemetry.snapshot().distribution('latency')!;
    expect(metric.count, 10);
    expect(metric.sampleCount, 5);
    expect(metric.p50Ms, 8);
    expect(metric.p95Ms, 10);
    expect(metric.p99Ms, 10);
    expect(metric.averageUs, 5500);
  });

  test('reset starts a new generation and clears counters', () {
    final telemetry = MediaSessionTelemetry();
    telemetry.increment(MediaMetricName.reconnectCount, 3);
    final generation = telemetry.generation;

    telemetry.reset();

    expect(telemetry.generation, generation + 1);
    expect(telemetry.counter(MediaMetricName.reconnectCount), 0);
    expect(telemetry.snapshot().distributions, isEmpty);
  });
}
