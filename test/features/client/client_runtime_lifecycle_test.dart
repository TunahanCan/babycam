import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/client_runtime.dart';
import 'package:mimicam/features/client/media/active_stream_session.dart';

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
    bool? audioRequested;
    var streamStarted = 0;
    var streamStopped = 0;
    var cleared = 0;
    final runtime = ClientRuntime(
        pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
        startStream: (_, {bool audioEnabled = false}) async {
          streamStarted++;
          audioRequested = audioEnabled;
          return ActiveStreamSession(
            streamToken: 'stream',
            audioEnabled: audioEnabled,
          );
        },
        stopStream: (_) async => streamStopped++,
        clearStore: () async => cleared++);
    await runtime.pairWithServer(payload());
    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    await runtime.startWatching(audioEnabled: true);
    expect(streamStarted, 1);
    expect(audioRequested, isTrue);
    expect(runtime.currentState.phase, ClientRuntimePhase.watching);
    expect(runtime.currentState.activeStream?.audioEnabled, isTrue);
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
      startStream: (_, {bool audioEnabled = false}) async {
        streamStarted++;
        return const ActiveStreamSession(streamToken: 'stream');
      },
    );

    await runtime.startWatching();

    expect(streamStarted, 0);
    expect(runtime.currentState.phase, ClientRuntimePhase.unpaired);
  });

  test('canlı izleme başlatma hatası runtime state içinde görünür', () async {
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async =>
          throw StateError('MEDIA_START_FAILED'),
    );

    await runtime.pairWithServer(payload());
    await expectLater(runtime.startWatching(), throwsStateError);

    expect(runtime.currentState.phase, ClientRuntimePhase.error);
    expect(runtime.currentState.session, isNotNull);
    expect(runtime.currentState.error, isA<StateError>());
    expect(
        runtime.currentState.error.toString(), contains('MEDIA_START_FAILED'));
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

  test('canlı izleme sırasında ağ kalite update state içine yazılır', () async {
    final updates = StreamController<NetworkQualityUpdate>();
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      watchNetworkQuality: (_) => updates.stream,
    );
    addTearDown(updates.close);

    await runtime.pairWithServer(payload());
    await runtime.startWatching();
    updates.add(NetworkQualityUpdate(
      snapshot: NetworkQualitySnapshot(
        tier: NetworkQualityTier.weak,
        rttMs: 550,
        measuredAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      serverProfile: MediaQualityProfile.forDeviceTier(
        DeviceCapabilityTier.modern,
      ).adaptForNetwork(NetworkQualityTier.weak),
    ));
    await Future<void>.delayed(Duration.zero);

    expect(runtime.currentState.networkQuality?.tier, NetworkQualityTier.weak);
    expect(runtime.currentState.mediaProfile?.audioFirst, isTrue);
  });

  test('canlı izleme sırasında bildirim dinleme state içinde korunur',
      () async {
    var alertStarted = 0;
    var alertStopped = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startAlerts: (_) async => alertStarted++,
      stopAlerts: () async => alertStopped++,
      startStream: (_, {bool audioEnabled = false}) async =>
          const ActiveStreamSession(streamToken: 'stream'),
      stopStream: (_) async {},
    );

    await runtime.pairWithServer(payload());
    await runtime.startAlertListening();
    await runtime.startWatching(audioEnabled: true);

    expect(alertStarted, 1);
    expect(runtime.currentState.phase, ClientRuntimePhase.watching);
    expect(runtime.currentState.alertsActive, isTrue);

    await runtime.stopWatching();
    expect(runtime.currentState.phase, ClientRuntimePhase.alertOnly);
    expect(runtime.currentState.alertsActive, isTrue);

    await runtime.stopAlertListening();
    expect(alertStopped, 1);
    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    expect(runtime.currentState.alertsActive, isFalse);
  });

  test('eşleşme sonrası kalite ölçümü canlı ekran açılmadan başlar', () async {
    final updates = StreamController<NetworkQualityUpdate>();
    var watchStarted = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      watchNetworkQuality: (_) {
        watchStarted++;
        return updates.stream;
      },
    );
    addTearDown(updates.close);

    await runtime.pairWithServer(payload());

    expect(watchStarted, 1);

    updates.add(NetworkQualityUpdate(
      snapshot: NetworkQualitySnapshot(
        tier: NetworkQualityTier.excellent,
        rttMs: 60,
        measuredAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      serverProfile: MediaQualityProfile.forDeviceTier(
        DeviceCapabilityTier.legacy,
      ).adaptForNetwork(NetworkQualityTier.excellent),
    ));
    await Future<void>.delayed(Duration.zero);

    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    expect(runtime.currentState.networkQuality?.tier,
        NetworkQualityTier.excellent);
    expect(runtime.currentState.mediaProfile?.height, 480);
  });
}
