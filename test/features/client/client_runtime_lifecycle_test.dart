import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/adaptive_media_profile.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/active_stream_session.dart';
import 'package:miucam/features/client/pairing/pairing_failure.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  PairingPayload payload({String deviceId = 's'}) => PairingPayload(
      schemaVersion: 1,
      host: 'h',
      port: 1,
      deviceId: deviceId,
      deviceName: 'd',
      pairingNonce: 'n',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {});

  test('yeni oda eşleşmesi eski yayın ve uyarıları kapatır', () async {
    var streamsStopped = 0;
    var alertsStopped = 0;
    final runtime = ClientRuntime(
      pair: (value) async => PairingSession(
        payload: value,
        sessionToken: 'token_${value.deviceId}',
      ),
      startStream: (_, {bool audioEnabled = false}) async =>
          const ActiveStreamSession(streamToken: 'stream'),
      stopStream: (_) async => streamsStopped++,
      startAlerts: (_) async => true,
      stopAlerts: () async => alertsStopped++,
    );
    final first = payload(deviceId: 'first-room');
    final second = payload(deviceId: 'second-room');

    await runtime.pairWithServer(first);
    await runtime.startAlertListening();
    await runtime.startWatching();
    await runtime.pairWithServer(second);

    expect(streamsStopped, 1);
    expect(alertsStopped, 1);
    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    expect(runtime.currentState.session?.deviceId, 'second-room');
    expect(runtime.currentState.activeStream, isNull);
    expect(runtime.currentState.alertsActive, isFalse);
  });

  test('başarısız yeni QR denemesi mevcut izlemeyi korur', () async {
    var shouldFail = false;
    final runtime = ClientRuntime(
      pair: (value) async {
        if (shouldFail) {
          throw const PairingFailure(PairingFailureCode.nonceInvalidOrExpired);
        }
        return PairingSession(payload: value, sessionToken: 'token');
      },
      startStream: (_, {bool audioEnabled = false}) async =>
          const ActiveStreamSession(streamToken: 'stream'),
      startAlerts: (_) async => true,
    );
    final first = payload(deviceId: 'first-room');

    await runtime.pairWithServer(first);
    await runtime.startAlertListening();
    await runtime.startWatching();
    shouldFail = true;

    await expectLater(
      runtime.pairWithServer(payload(deviceId: 'second-room')),
      throwsA(isA<PairingFailure>()),
    );

    expect(runtime.currentState.phase, ClientRuntimePhase.watching);
    expect(runtime.currentState.session?.deviceId, 'first-room');
    expect(runtime.currentState.activeStream, isNotNull);
    expect(runtime.currentState.alertsActive, isTrue);
  });

  test('eşzamanlı ikinci eşleşme dokunuşu güvenli biçimde reddedilir',
      () async {
    final pending = Completer<PairingSession>();
    final runtime = ClientRuntime(pair: (_) => pending.future);

    final first = runtime.pairWithServer(payload());
    await expectLater(
      runtime.pairWithServer(payload()),
      throwsA(
        isA<PairingFailure>().having(
          (failure) => failure.code,
          'code',
          PairingFailureCode.pairingInProgress,
        ),
      ),
    );
    pending.complete(PairingSession(payload: payload(), sessionToken: 'token'));
    await first;

    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
  });

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

  test('ücretsiz süre dolduysa canlı izleme stream başlatmadan kilitlenir',
      () async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms': const Duration(hours: 2).inMilliseconds,
    });
    final preferences = await SharedPreferences.getInstance();
    var streamStarted = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async {
        streamStarted++;
        return const ActiveStreamSession(streamToken: 'stream');
      },
      broadcastAccess: BroadcastAccessService(
        preferences,
        purchaseGateway: _FakePurchaseGateway(),
      ),
    );

    await runtime.pairWithServer(payload());

    await expectLater(
      runtime.startWatching(audioEnabled: true),
      throwsA(isA<BroadcastAccessLockedException>()),
    );

    expect(streamStarted, 0);
    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    expect(runtime.currentState.broadcastAccess?.isLocked, isTrue);
  });

  test('room server paywall remains the client runtime authority', () async {
    const remoteSnapshot = BroadcastAccessSnapshot(
      unlocked: false,
      active: false,
      freeLimitMs: 100,
      usedMs: 100,
      remainingMs: 0,
      priceLabel: r'$9.99',
      productId: BroadcastAccessConfig.productId,
    );
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async =>
          throw const BroadcastAccessLockedException(remoteSnapshot),
    );

    await runtime.pairWithServer(payload());
    await expectLater(
      runtime.startWatching(),
      throwsA(isA<BroadcastAccessLockedException>()),
    );

    expect(runtime.canManageBroadcastPurchase, isFalse);
    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    expect(runtime.currentState.broadcastAccess, same(remoteSnapshot));
  });

  test('remote trial timer stops watch and locks from server snapshot',
      () async {
    var stops = 0;
    var authorityReads = 0;
    const lockedSnapshot = BroadcastAccessSnapshot(
      unlocked: false,
      active: false,
      freeLimitMs: 100,
      usedMs: 100,
      remainingMs: 0,
      priceLabel: r'$9.99',
      productId: BroadcastAccessConfig.productId,
    );
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async =>
          const ActiveStreamSession(
        streamToken: 'stream',
        broadcastAccess: BroadcastAccessSnapshot(
          unlocked: false,
          active: true,
          freeLimitMs: 100,
          usedMs: 90,
          remainingMs: 10,
          priceLabel: r'$9.99',
          productId: BroadcastAccessConfig.productId,
        ),
      ),
      stopStream: (_) async => stops++,
      refreshRemoteBroadcastAccess: (_) async {
        authorityReads++;
        return lockedSnapshot;
      },
    );
    await runtime.pairWithServer(payload());
    await runtime.startWatching();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await pumpEventQueue();

    expect(stops, 1);
    expect(runtime.currentState.activeStream, isNull);
    expect(runtime.currentState.broadcastAccess?.isLocked, isTrue);
    expect(runtime.currentState.error, isA<BroadcastAccessLockedException>());
    expect(authorityReads, 1);
    await runtime.dispose();
  });

  test(
      'stale remote trial deadline cannot stop an authoritatively unlocked watch',
      () async {
    var stops = 0;
    var reads = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async =>
          const ActiveStreamSession(
        streamToken: 'stream',
        broadcastAccess: BroadcastAccessSnapshot(
          unlocked: false,
          active: true,
          freeLimitMs: 100,
          usedMs: 95,
          remainingMs: 5,
          priceLabel: r'$9.99',
          productId: BroadcastAccessConfig.productId,
        ),
      ),
      stopStream: (_) async => stops++,
      refreshRemoteBroadcastAccess: (_) async {
        reads++;
        return const BroadcastAccessSnapshot(
          unlocked: true,
          active: true,
          freeLimitMs: 100,
          usedMs: 95,
          remainingMs: 5,
          priceLabel: r'$9.99',
          productId: BroadcastAccessConfig.productId,
        );
      },
    );
    addTearDown(runtime.dispose);

    await runtime.pairWithServer(payload());
    await runtime.startWatching();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await pumpEventQueue();

    expect(reads, 1);
    expect(stops, 0);
    expect(runtime.currentState.activeStream, isNotNull);
    expect(runtime.currentState.broadcastAccess?.unlocked, isTrue);
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

  test('watch geçişi LAN alert demandini kesmeden izlemeyi başlatır', () async {
    var alertStarted = 0;
    var alertStopped = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startAlerts: (_) async {
        alertStarted++;
        return true;
      },
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
    expect(alertStopped, 0);

    await runtime.stopWatching();
    expect(runtime.currentState.phase, ClientRuntimePhase.alertOnly);
    expect(runtime.currentState.alertsActive, isTrue);

    await runtime.stopAlertListening();
    expect(alertStopped, 1);
    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    expect(runtime.currentState.alertsActive, isFalse);
  });

  test('alert transport bağlantısı armed tercihinden ayrı izlenir', () async {
    final connections = StreamController<bool>();
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startAlerts: (_) async => true,
      stopAlerts: () async {},
      alertConnectionStates: connections.stream,
    );
    addTearDown(runtime.dispose);
    addTearDown(connections.close);
    await runtime.pairWithServer(payload());
    await runtime.startAlertListening();

    expect(runtime.currentState.alertsActive, isTrue);
    expect(runtime.alertTransportConnected, isFalse);

    final connectedUpdate = runtime.states.firstWhere(
      (_) => runtime.alertTransportConnected,
    );
    connections.add(true);
    await connectedUpdate;

    expect(runtime.currentState.alertsActive, isTrue);
    expect(runtime.alertTransportConnected, isTrue);
  });

  test('watch ekranından çıkmak kapalı bildirimleri kendiliğinden açmaz',
      () async {
    var alertStarts = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async =>
          const ActiveStreamSession(streamToken: 'stream'),
      stopStream: (_) async {},
      startAlerts: (_) async {
        alertStarts++;
        return true;
      },
    );
    addTearDown(runtime.dispose);
    await runtime.pairWithServer(payload());

    final presentation = runtime.claimWatchPresentation();
    await runtime.startWatching();
    await runtime.releaseWatchPresentation(presentation);

    expect(alertStarts, 0);
    expect(runtime.currentState.alertsActive, isFalse);
    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
  });

  test('restart eski streami kapatıp yeni audio demand ile tekil başlatır',
      () async {
    final calls = <String>[];
    var sequence = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async {
        calls.add('start:$audioEnabled');
        return ActiveStreamSession(
          streamToken: 'stream-${++sequence}',
          audioEnabled: audioEnabled,
        );
      },
      stopStream: (_) async => calls.add('stop'),
    );
    await runtime.pairWithServer(payload());
    await runtime.startWatching();

    await runtime.restartWatching(audioEnabled: true);

    expect(calls, ['start:false', 'stop', 'start:true']);
    expect(runtime.currentState.activeStream?.streamToken, 'stream-2');
    expect(runtime.currentState.activeStream?.audioEnabled, isTrue);
    expect(runtime.currentState.phase, ClientRuntimePhase.watching);
  });

  test('stale screen release cannot stop or arm alerts over a newer watch',
      () async {
    var starts = 0;
    var stops = 0;
    var alertStarts = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startStream: (_, {bool audioEnabled = false}) async =>
          ActiveStreamSession(streamToken: 'stream-${++starts}'),
      stopStream: (_) async => stops++,
      startAlerts: (_) async {
        alertStarts++;
        return true;
      },
    );
    addTearDown(runtime.dispose);
    await runtime.pairWithServer(payload());

    final oldPresentation = runtime.claimWatchPresentation();
    await runtime.startWatching();
    final oldRelease = runtime.releaseWatchPresentation(oldPresentation);
    runtime.claimWatchPresentation();
    await runtime.startWatching();
    await oldRelease;

    expect(starts, 2);
    expect(stops, 1, reason: 'yalnız replacement eski streami kapatır');
    expect(alertStarts, 0);
    expect(runtime.currentState.activeStream?.streamToken, 'stream-2');
  });

  test('alert transport başlatılamazsa listener kapalı kalır', () async {
    var alertStarted = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      startAlerts: (_) async {
        alertStarted++;
        return false;
      },
    );

    await runtime.pairWithServer(payload());
    final started = await runtime.startAlertListening();

    expect(started, isFalse);
    expect(alertStarted, 1);
    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    expect(runtime.currentState.alertsActive, isFalse);
  });

  test('sistem izni kapalıyken uygulama içi alertler çalışmayı sürdürür',
      () async {
    var permissionEnabled = false;
    var permissionChecks = 0;
    var alertStarts = 0;
    final runtime = ClientRuntime(
      pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
      initializeSystemNotifications: () async {
        permissionChecks++;
        return permissionEnabled;
      },
      startAlerts: (_) async {
        alertStarts++;
        return true;
      },
    );
    addTearDown(runtime.dispose);
    await runtime.pairWithServer(payload());

    expect(await runtime.startAlertListening(), isTrue);
    expect(runtime.systemNotificationsEnabled, isFalse);
    expect(runtime.currentState.alertsActive, isTrue);
    expect(alertStarts, 1);

    permissionEnabled = true;
    expect(await runtime.startAlertListening(), isTrue);
    expect(runtime.systemNotificationsEnabled, isTrue);
    expect(runtime.currentState.alertsActive, isTrue);
    expect(permissionChecks, 2);
    expect(alertStarts, 1, reason: 'izin yenileme socketi çoğaltmamalı');
  });

  test('geçerli token yenileme hatası alert başlangıcını bloke etmez',
      () async {
    var alertStarts = 0;
    final expiring = PairingSession(
      payload: payload(),
      sessionToken: 'still-valid-token',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    final runtime = ClientRuntime(
      pair: (_) async => expiring,
      renew: (_) async => throw StateError('temporary network outage'),
      startAlerts: (_) async {
        alertStarts++;
        return true;
      },
    );
    addTearDown(runtime.dispose);

    await runtime.restoreSession(expiring);
    expect(await runtime.startAlertListening(), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(alertStarts, 1);
    expect(runtime.currentState.alertsActive, isTrue);
    expect(runtime.currentState.phase, ClientRuntimePhase.alertOnly);
    expect(runtime.currentState.error, isNull);
  });

  test('arka plan token yenilemesi alert socketini yeni tokena taşır',
      () async {
    final renewal = Completer<PairingSession?>();
    final oldAlertStartEntered = Completer<void>();
    final finishOldAlertStart = Completer<void>();
    final renewedAlertStarted = Completer<void>();
    final alertTokens = <String>[];
    var alertStops = 0;
    final expiring = PairingSession(
      payload: payload(),
      sessionToken: 'old-token',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    final renewed = expiring.copyWith(
      sessionToken: 'new-token',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
    );
    final runtime = ClientRuntime(
      pair: (_) async => expiring,
      renew: (_) => renewal.future,
      startAlerts: (session) async {
        alertTokens.add(session.sessionToken);
        if (session.sessionToken == 'old-token') {
          if (!oldAlertStartEntered.isCompleted) {
            oldAlertStartEntered.complete();
          }
          await finishOldAlertStart.future;
        } else if (!renewedAlertStarted.isCompleted) {
          renewedAlertStarted.complete();
        }
        return true;
      },
      stopAlerts: () async => alertStops++,
    );
    addTearDown(runtime.dispose);

    await runtime.restoreSession(expiring);
    final alertStart = runtime.startAlertListening();
    await oldAlertStartEntered.future;
    renewal.complete(renewed);
    await Future<void>.delayed(Duration.zero);
    finishOldAlertStart.complete();
    await alertStart;
    await renewedAlertStarted.future.timeout(const Duration(seconds: 2));

    expect(alertTokens, ['old-token', 'new-token']);
    expect(alertStops, 1);
    expect(runtime.currentState.session, same(renewed));
    expect(runtime.currentState.alertsActive, isTrue);
  });

  test('token yenilenince aktif yayının stop isteği yeni bearer kullanır',
      () async {
    final renewal = Completer<PairingSession?>();
    final stoppedWithTokens = <String>[];
    final expiring = PairingSession(
      payload: payload(),
      sessionToken: 'old-token',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    final renewed = expiring.copyWith(
      sessionToken: 'new-token',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
    );
    final runtime = ClientRuntime(
      pair: (_) async => expiring,
      renew: (_) => renewal.future,
      startStream: (_, {bool audioEnabled = false}) async =>
          const ActiveStreamSession(streamToken: 'stream-token'),
      stopStream: (session) async {
        stoppedWithTokens.add(session.sessionToken);
      },
    );
    addTearDown(runtime.dispose);

    await runtime.restoreSession(expiring);
    await runtime.startWatching();
    renewal.complete(renewed);
    await runtime.states
        .firstWhere((state) => identical(state.session, renewed))
        .timeout(const Duration(seconds: 2));
    await runtime.stopWatching();

    expect(stoppedWithTokens, ['new-token']);
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

  test('renew null donerse runtime revoked olur ve store temizlenir', () async {
    var cleared = 0;
    var stopped = 0;
    final expiring = PairingSession(
      payload: payload(),
      sessionToken: 'expired-token',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    );
    final runtime = ClientRuntime(
      pair: (_) async => expiring,
      renew: (_) async => null,
      stopStream: (_) async => stopped++,
      clearStore: () async => cleared++,
    );

    await runtime.restoreSession(expiring);
    await runtime.states.firstWhere(
      (state) => state.phase == ClientRuntimePhase.revoked,
    );

    expect(runtime.currentState.phase, ClientRuntimePhase.revoked);
    expect(runtime.currentState.session?.sessionToken, 'expired-token');
    expect(cleared, 1);
    expect(stopped, 0);
  });

  test('trusted DNS-SD endpoint change is persisted and active alerts rebind',
      () async {
    final endpointUpdates = StreamController<PairingSession>();
    final persisted = <PairingSession>[];
    final alertHosts = <String>[];
    final alertRebound = Completer<void>();
    var alertStops = 0;
    var qualityWatches = 0;
    final original = PairingSession(
      payload: payload(),
      sessionToken: 'trusted-token',
      clientId: 'trusted-client',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      pairedAtMs: 42,
    );
    final rebound = PairingSession(
      payload: PairingPayload(
        schemaVersion: original.payload.schemaVersion,
        host: 'fd00::77',
        port: 9090,
        deviceId: original.deviceId,
        deviceName: original.deviceName,
        pairingNonce: original.payload.pairingNonce,
        expiresAtMs: original.payload.expiresAtMs,
        capabilities: original.payload.capabilities,
      ),
      sessionToken: 'untrusted-replacement-token',
      clientId: 'untrusted-client',
    );
    final runtime = ClientRuntime(
      pair: (_) async => original,
      watchSessionEndpoints: (_) => endpointUpdates.stream,
      persistReboundSession: (session) async => persisted.add(session),
      watchNetworkQuality: (_) {
        qualityWatches++;
        return const Stream.empty();
      },
      startAlerts: (session) async {
        alertHosts.add(session.host);
        if (session.host == rebound.host && !alertRebound.isCompleted) {
          alertRebound.complete();
        }
        return true;
      },
      stopAlerts: () async => alertStops++,
    );

    await runtime.restoreSession(original);
    await runtime.startAlertListening();
    final reboundState = runtime.states.firstWhere(
      (state) => state.session?.host == rebound.host,
    );
    endpointUpdates.add(rebound);
    await reboundState.timeout(const Duration(seconds: 2));
    await alertRebound.future.timeout(const Duration(seconds: 2));

    expect(runtime.currentState.session?.host, 'fd00::77');
    expect(runtime.currentState.session?.port, 9090);
    expect(runtime.currentState.session?.sessionToken, 'trusted-token');
    expect(runtime.currentState.session?.clientId, 'trusted-client');
    expect(persisted.single.sessionToken, 'trusted-token');
    expect(alertHosts, ['h', 'fd00::77']);
    expect(alertStops, 1);
    expect(qualityWatches, 2);

    await runtime.dispose();
    await endpointUpdates.close();
  });

  test('endpoint rebind cannot be overwritten by an in-flight stream start',
      () async {
    final endpointUpdates = StreamController<PairingSession>();
    final streamStartEntered = Completer<void>();
    final finishStreamStart = Completer<void>();
    final startHosts = <String>[];
    final stopHosts = <String>[];
    final original = PairingSession(
      payload: payload(),
      sessionToken: 'trusted-token',
      clientId: 'trusted-client',
    );
    final rebound = PairingSession(
      payload: PairingPayload(
        schemaVersion: original.payload.schemaVersion,
        host: 'fd00::99',
        port: 9091,
        deviceId: original.deviceId,
        deviceName: original.deviceName,
        pairingNonce: original.payload.pairingNonce,
        expiresAtMs: original.payload.expiresAtMs,
        capabilities: original.payload.capabilities,
      ),
      sessionToken: 'ignored-replacement-token',
    );
    final runtime = ClientRuntime(
      pair: (_) async => original,
      watchSessionEndpoints: (_) => endpointUpdates.stream,
      startStream: (session, {bool audioEnabled = false}) async {
        startHosts.add(session.host);
        if (!streamStartEntered.isCompleted) streamStartEntered.complete();
        await finishStreamStart.future;
        return const ActiveStreamSession(streamToken: 'stream');
      },
      stopStream: (session) async => stopHosts.add(session.host),
    );
    addTearDown(runtime.dispose);
    addTearDown(endpointUpdates.close);

    await runtime.restoreSession(original);
    final watching = runtime.startWatching();
    await streamStartEntered.future;
    endpointUpdates.add(rebound);
    finishStreamStart.complete();
    await watching;
    await runtime.states
        .firstWhere((state) => state.session?.host == rebound.host)
        .timeout(const Duration(seconds: 2));

    expect(runtime.currentState.session?.host, rebound.host);
    expect(startHosts, ['h']);

    await runtime.stopWatching();
    expect(stopHosts, ['h']);
  });

  test('endpoint watcher failure does not undo a trusted session', () async {
    final session = PairingSession(
      payload: payload(),
      sessionToken: 'trusted-token',
    );
    final runtime = ClientRuntime(
      pair: (_) async => session,
      watchSessionEndpoints: (_) => throw StateError('DNS-SD unavailable'),
    );

    await runtime.restoreSession(session);

    expect(runtime.currentState.phase, ClientRuntimePhase.pairedIdle);
    expect(runtime.currentState.session, same(session));
    await runtime.dispose();
  });
}

class _FakePurchaseGateway implements BroadcastPurchaseGateway {
  @override
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  }) async =>
      const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.purchased,
        verified: true,
        verificationSource: 'test_store',
        verificationFingerprint: 'test-fingerprint',
      );

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async =>
      const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.restored,
        verified: true,
        verificationSource: 'test_store',
        verificationFingerprint: 'test-fingerprint',
      );

  @override
  Future<void> dispose() async {}
}
