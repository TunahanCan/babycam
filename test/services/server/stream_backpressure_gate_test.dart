import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/server/stream_backpressure_gate.dart';

void main() {
  test('busy client ikinci flush tamamlanana kadar frame almaz', () {
    final gate = StreamBackpressureGate<int>(
      kind: StreamBackpressureKind.video,
    );

    expect(gate.tryMarkBusy(1), isTrue);
    expect(gate.tryMarkBusy(1), isFalse);
    expect(gate.busyCount, 1);
    expect(gate.metricsFor(1).skippedVideoFrames, 1);

    gate.markIdle(1);

    expect(gate.tryMarkBusy(1), isTrue);
    gate.recordSuccess(1, duration: const Duration(milliseconds: 12));
    expect(gate.metricsFor(1).lastSuccessfulVideoWriteAtMs, isNotNull);
    expect(gate.metricsFor(1).averageWriteDurationMs, 12);
    gate.remove(1);
    expect(gate.busyCount, 0);
  });

  test('clear tüm pending clientları temizler', () {
    final gate = StreamBackpressureGate<String>()
      ..tryMarkBusy('video')
      ..tryMarkBusy('audio');

    gate.clear();

    expect(gate.busyCount, 0);
    expect(gate.tryMarkBusy('video'), isTrue);
  });

  test('audio skip ve failure sayaçları tutulur', () {
    var nowMs = 1000;
    final gate = StreamBackpressureGate<String>(
      kind: StreamBackpressureKind.audio,
      nowMs: () => nowMs,
    );

    expect(gate.tryMarkBusy('client'), isTrue);
    expect(gate.tryMarkBusy('client'), isFalse);
    gate.recordFailure('client');

    final metrics = gate.metricsFor('client');
    expect(metrics.skippedAudioChunks, 1);
    expect(metrics.consecutiveSkippedAudioChunks, 1);
    expect(metrics.consecutiveWriteFailures, 1);

    gate.recordSuccess('client', duration: const Duration(milliseconds: 20));
    expect(gate.metricsFor('client').consecutiveSkippedAudioChunks, 1);

    nowMs += 299;
    gate.recordSuccess('client', duration: const Duration(milliseconds: 20));
    expect(gate.metricsFor('client').consecutiveSkippedAudioChunks, 1);

    nowMs += 1;
    gate.recordSuccess('client', duration: const Duration(milliseconds: 20));
    expect(gate.metricsFor('client').consecutiveSkippedAudioChunks, 0);
  });

  test('audio busy iken video skip metriği ayrıca kaydedilir', () {
    final gate = StreamBackpressureGate<String>(
      kind: StreamBackpressureKind.video,
    );

    gate.recordSkippedVideoFrame('client');

    expect(gate.metricsFor('client').skippedVideoFrames, 1);
    expect(gate.metricsFor('client').skippedWrites, 1);
  });

  test('aggregate metrics audio ve video skip toplamını verir', () {
    final video = StreamBackpressureGate<String>(
      kind: StreamBackpressureKind.video,
    )..recordSkippedVideoFrame('client');
    final audio = StreamBackpressureGate<String>(
      kind: StreamBackpressureKind.audio,
    )..recordSkippedAudioChunk('client');

    final aggregate = combineBackpressureMetrics([
      video.aggregateMetrics(),
      audio.aggregateMetrics(),
    ]);

    expect(aggregate.skippedVideoFrames, 1);
    expect(aggregate.skippedAudioChunks, 1);
  });

  test('aggregate write duration en yavas client ortalamasini korur', () {
    final gate = StreamBackpressureGate<String>();
    gate.recordSuccess('fast', duration: const Duration(milliseconds: 8));
    gate.recordSuccess('slow', duration: const Duration(milliseconds: 40));
    gate.recordSuccess('medium', duration: const Duration(milliseconds: 20));

    final clientMetrics = [
      gate.metricsFor('fast'),
      gate.metricsFor('slow'),
      gate.metricsFor('medium'),
    ];

    expect(gate.aggregateMetrics().averageWriteDurationMs, 40);
    expect(
      combineBackpressureMetrics(clientMetrics).averageWriteDurationMs,
      40,
    );
    expect(
      combineBackpressureMetrics(clientMetrics.reversed).averageWriteDurationMs,
      40,
    );
  });
}
