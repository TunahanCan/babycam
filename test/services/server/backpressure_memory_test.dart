import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/server/stream_backpressure_gate.dart';

void main() {
  test('slow client skip sayaçları büyür ama busy set tek client tutar', () {
    final gate = StreamBackpressureGate<Object>(
      kind: StreamBackpressureKind.video,
    );
    final client = Object();

    expect(gate.tryMarkBusy(client), isTrue);
    for (var index = 0; index < 1000; index++) {
      expect(gate.tryMarkBusy(client), isFalse);
    }

    final metrics = gate.metricsFor(client);
    expect(gate.busyCount, 1);
    expect(metrics.skippedVideoFrames, 1000);
    expect(metrics.skippedWrites, 1000);
  });
}
