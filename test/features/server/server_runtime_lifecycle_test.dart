import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/media/media_runtime_controller.dart';
import 'package:mimicam/features/server/server_runtime.dart';

void main() {
  test('Server startPairingMode çağrılınca kamera önizlemesi aktif başlar',
      () async {
    var startCount = 0;
    var stopCount = 0;
    final media = MediaRuntimeController(
        onStart: () async => startCount++, onStop: () async => stopCount++);
    final runtime = ServerRuntime(
        mediaRuntime: media,
        onStartPairing: () async => 'mimicam://pair?payload=x');

    await runtime.startPairingMode();
    expect(media.isActive, isTrue);
    expect(startCount, 1);
    expect(runtime.currentState.cameraActive, isTrue);

    await runtime.markClientPaired();
    expect(media.isActive, isTrue);

    await runtime.startMediaRuntimeForSession('s1');
    expect(media.isActive, isTrue);
    expect(startCount, 1);

    await runtime.endSession('s1');
    expect(media.isActive, isTrue);
    expect(stopCount, 0);

    await runtime.stop();
    expect(media.isActive, isFalse);
    expect(stopCount, 1);
  });

  test('Server stop idempotent şekilde kaynakları dispose eder', () async {
    final media = MediaRuntimeController();
    final runtime = ServerRuntime(mediaRuntime: media);
    await runtime.stop();
    await runtime.stop();
    expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
  });
}
