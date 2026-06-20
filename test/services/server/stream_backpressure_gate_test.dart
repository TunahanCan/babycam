import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/server/stream_backpressure_gate.dart';

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
    final gate = StreamBackpressureGate<String>(
      kind: StreamBackpressureKind.audio,
    );

    expect(gate.tryMarkBusy('client'), isTrue);
    expect(gate.tryMarkBusy('client'), isFalse);
    gate.recordFailure('client');

    final metrics = gate.metricsFor('client');
    expect(metrics.skippedAudioChunks, 1);
    expect(metrics.consecutiveWriteFailures, 1);
  });
}
