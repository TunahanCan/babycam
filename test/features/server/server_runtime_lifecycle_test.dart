import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/media/media_runtime_controller.dart';
import 'package:mimicam/features/server/server_runtime.dart';

void main() {
  test('Server startPairingMode sadece pairing açar, medya oturumla başlar',
      () async {
    var startCount = 0;
    var stopCount = 0;
    final media = MediaRuntimeController(
        onStart: () async => startCount++, onStop: () async => stopCount++);
    final runtime = ServerRuntime(
        mediaRuntime: media,
        onStartPairing: () async => 'mimicam://pair?payload=x');

    await runtime.startPairingMode();
    expect(media.isActive, isFalse);
    expect(startCount, 0);
    expect(runtime.currentState.cameraActive, isFalse);
    expect(runtime.currentState.microphoneActive, isFalse);

    await runtime.markClientPaired();
    expect(media.isActive, isFalse);

    await runtime.startMediaRuntimeForSession('s1');
    expect(media.isActive, isTrue);
    expect(startCount, 1);

    await runtime.endSession('s1');
    expect(media.isActive, isFalse);
    expect(stopCount, 1);

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

  test('Media stop devam eden start bittikten sonra kaynakları kapatır',
      () async {
    final startCompleter = Completer<void>();
    var startCount = 0;
    var stopCount = 0;
    final media = MediaRuntimeController(
      onStart: () async {
        startCount++;
        await startCompleter.future;
      },
      onStop: () async => stopCount++,
    );

    final start = media.start();
    final stop = media.stop();
    expect(stopCount, 0);

    startCompleter.complete();
    await start;
    await stop;

    expect(startCount, 1);
    expect(stopCount, 1);
    expect(media.isActive, isFalse);
  });

  test('Media start eşzamanlı çağrılarda tek kez çalışır', () async {
    final startCompleter = Completer<void>();
    var startCount = 0;
    final media = MediaRuntimeController(
      onStart: () async {
        startCount++;
        await startCompleter.future;
      },
    );

    final first = media.start();
    final second = media.start();

    startCompleter.complete();
    await Future.wait([first, second]);

    expect(startCount, 1);
    expect(media.isActive, isTrue);
  });

  test('Media start hata alırsa aktif kalmaz ve stop çağırmaz', () async {
    var stopCount = 0;
    final media = MediaRuntimeController(
      onStart: () async => throw StateError('camera unavailable'),
      onStop: () async => stopCount++,
    );

    await expectLater(media.start(), throwsStateError);
    await media.stop();

    expect(media.isActive, isFalse);
    expect(stopCount, 0);
  });

  test('Server local preview media hatasını state içine yazar', () async {
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStart: () async => throw StateError('camera unavailable'),
      ),
    );

    await expectLater(runtime.startLocalPreview(), throwsStateError);

    expect(runtime.currentState.phase, ServerRuntimePhase.error);
    expect(runtime.currentState.cameraActive, isFalse);
    expect(runtime.currentState.activeClients, 0);
    expect(runtime.currentState.errorMessage, contains('camera unavailable'));
  });

  test('stream session media hatasında aktif client rollback yapar', () async {
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStart: () async => throw StateError('camera unavailable'),
      ),
    );

    await expectLater(
      runtime.startStreamSession('client-1', const StreamSessionOptions()),
      throwsStateError,
    );

    expect(runtime.currentState.phase, ServerRuntimePhase.error);
    expect(runtime.currentState.activeClients, 0);
    expect(runtime.currentState.activeVideoClients, 0);
    expect(runtime.currentState.errorMessage, contains('camera unavailable'));
  });

  test('Server dispose pairing start yarışından sonra medyayı başlatmaz',
      () async {
    final pairingStarted = Completer<void>();
    final pairingResult = Completer<String>();
    var mediaStartCount = 0;
    var serverStopCount = 0;
    final media = MediaRuntimeController(
      onStart: () async => mediaStartCount++,
    );
    final runtime = ServerRuntime(
      mediaRuntime: media,
      onStartPairing: () async {
        pairingStarted.complete();
        return pairingResult.future;
      },
      onStop: () async => serverStopCount++,
    );

    final start = runtime.startPairingMode();
    await pairingStarted.future;
    final dispose = runtime.dispose();

    pairingResult.complete('mimicam://pair?payload=x');
    await start;
    await dispose;

    expect(mediaStartCount, 0);
    expect(media.isActive, isFalse);
    expect(serverStopCount, 1);
    expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
  });
}
