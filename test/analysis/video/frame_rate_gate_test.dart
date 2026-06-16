import 'package:mimicam/analysis/video/frame_rate_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first timestamp returns true', () {
    expect(FrameRateGate(fps: 3).shouldRun(1000), isTrue);
  });

  test('3 FPS skips frame after 100 ms', () {
    final gate = FrameRateGate(fps: 3)..shouldRun(1000);
    expect(gate.shouldRun(1100), isFalse);
  });

  test('3 FPS allows frame after 334 ms', () {
    final gate = FrameRateGate(fps: 3)..shouldRun(1000);
    expect(gate.shouldRun(1334), isTrue);
  });

  test('reset makes next frame first again', () {
    final gate = FrameRateGate(fps: 3)..shouldRun(1000);
    gate.reset();
    expect(gate.shouldRun(1100), isTrue);
  });

  test('timestamp going backwards is safe', () {
    final gate = FrameRateGate(fps: 3)..shouldRun(1000);
    expect(() => gate.shouldRun(900), returnsNormally);
    final backwardsResult = gate.shouldRun(800);
    expect(backwardsResult, isTrue);
  });
}
