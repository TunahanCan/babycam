import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/client_runtime.dart';

void main() {
  PairingPayload payload() => PairingPayload(
      schemaVersion: 1,
      host: 'h',
      port: 1,
      deviceId: 's',
      deviceName: 'd',
      pairingNonce: 'n',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {});

  test(
      'WatchScreen/runtime açılınca video audio session başlar, kapanınca durur, clearPairing token siler',
      () async {
    var streamStarted = 0;
    var streamStopped = 0;
    var cleared = 0;
    final runtime = ClientRuntime(
        pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
        startStream: () async => streamStarted++,
        stopStream: () async => streamStopped++,
        clearStore: () async => cleared++);
    await runtime.pairWithServer(payload());
    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    await runtime.startWatching();
    expect(streamStarted, 1);
    expect(runtime.currentState.phase, ClientRuntimePhase.watching);
    await runtime.stopWatching();
    expect(streamStopped, 1);
    await runtime.clearPairing();
    expect(cleared, 1);
    expect(runtime.currentState.phase, ClientRuntimePhase.unpaired);
  });

  test('eşleşme yokken canlı izleme başlatılmaz', () async {
    var streamStarted = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startStream: () async => streamStarted++,
    );

    await runtime.startWatching();

    expect(streamStarted, 0);
    expect(runtime.currentState.phase, ClientRuntimePhase.unpaired);
  });

  test('pair hatası runtime state içinde görünür ve yeniden fırlatılır',
      () async {
    final runtime = ClientRuntime(
      pair: (_) async => throw StateError('pair failed'),
    );

    await expectLater(runtime.pairWithServer(payload()), throwsStateError);

    expect(runtime.currentState.phase, ClientRuntimePhase.error);
    expect(runtime.currentState.error, isA<StateError>());
  });
}
