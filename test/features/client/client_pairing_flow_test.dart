import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/client_runtime.dart';
import 'package:mimicam/features/client/pairing/client_pairing_flow.dart';

void main() {
  test('eşleşme başarılı olunca bildirim dinlemeyi otomatik başlatır',
      () async {
    var pairCount = 0;
    var alertStartCount = 0;
    final payload = _payload();
    final runtime = ClientRuntime(
      pair: (payload) async {
        pairCount++;
        return PairingSession(payload: payload, sessionToken: 'token');
      },
      startAlerts: () async => alertStartCount++,
    );

    await ClientPairingFlow(runtime).pairAndArmAlerts(payload);

    expect(pairCount, 1);
    expect(alertStartCount, 1);
    expect(runtime.currentState.phase, ClientRuntimePhase.alertOnly);
    expect(runtime.currentState.session?.payload, payload);
  });

  test('eşleşme hata verirse bildirim dinlemeyi başlatmaz', () async {
    var alertStartCount = 0;
    final runtime = ClientRuntime(
      pair: (_) async => throw StateError('pair failed'),
      startAlerts: () async => alertStartCount++,
    );

    await expectLater(
      ClientPairingFlow(runtime).pairAndArmAlerts(_payload()),
      throwsStateError,
    );

    expect(alertStartCount, 0);
    expect(runtime.currentState.phase, ClientRuntimePhase.error);
    expect(runtime.currentState.error, isA<StateError>());
  });
}

PairingPayload _payload() => PairingPayload(
      schemaVersion: 1,
      host: '192.168.1.20',
      port: 8080,
      deviceId: 'server',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {'transport': 'http'},
    );
