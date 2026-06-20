import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/server/stream_backpressure_gate.dart';

void main() {
  test('busy client ikinci flush tamamlanana kadar frame almaz', () {
    final gate = StreamBackpressureGate<int>();

    expect(gate.tryMarkBusy(1), isTrue);
    expect(gate.tryMarkBusy(1), isFalse);
    expect(gate.busyCount, 1);

    gate.markIdle(1);

    expect(gate.tryMarkBusy(1), isTrue);
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
}
