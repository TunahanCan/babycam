import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/broadcast_purchase_coordinator.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/active_stream_session.dart';

void main() {
  test('forget starts before teardown and does not hold the media connection',
      () async {
    final purchases = _Purchases()..holdForget = Completer<void>();
    final calls = <String>[];
    final runtime = _runtime(purchases, calls);
    try {
      await runtime.pairWithServer(_payload('A'));
      await runtime.startWatching();
      await runtime.startAlertListening();
      calls.clear();
      final clearing = runtime.clearPairing();
      expect(purchases.forgotten, ['A']);
      await Future<void>.delayed(Duration.zero);
      expect(calls, containsAll(['stop-stream', 'stop-alerts', 'clear-store']));
      purchases.holdForget!.complete();
      await clearing;
      expect(runtime.currentState.phase, ClientRuntimePhase.unpaired);
      expect(runtime.currentState.session, isNull);
    } finally {
      if (!purchases.holdForget!.isCompleted) purchases.holdForget!.complete();
      await runtime.dispose();
    }
  });

  for (final revoked in [false, true]) {
    test(
        'forget disk failure still tears down ${revoked ? 'revoked' : 'removed'} room',
        () async {
      final failure = StateError('activation destination disk failed');
      final purchases = _Purchases()..forgetFailure = failure;
      final calls = <String>[];
      final runtime = _runtime(purchases, calls);
      try {
        await runtime.pairWithServer(_payload('A'));
        await runtime.startWatching();
        await runtime.startAlertListening();
        calls.clear();
        if (revoked) {
          await runtime.renewTokenIfNeeded(
              now: DateTime.now().add(const Duration(days: 31)));
        } else {
          await runtime.clearPairing();
        }
        expect(purchases.forgotten, ['A']);
        expect(
            calls, containsAll(['stop-stream', 'stop-alerts', 'clear-store']));
        expect(runtime.currentState.phase,
            revoked ? ClientRuntimePhase.revoked : ClientRuntimePhase.unpaired);
        expect(runtime.currentState.activeStream, isNull);
        expect(runtime.currentState.alertsActive, isFalse);
        expect(runtime.currentState.error, same(failure));
      } finally {
        await runtime.dispose();
      }
    });
  }

  test(
      'room selection and runtime teardown retain the app-owned purchase destination',
      () async {
    final purchases = _Purchases();
    final runtime = _runtime(purchases, []);
    await runtime.pairWithServer(_payload('A'));
    await runtime.pairWithServer(_payload('B'));
    await runtime.dispose();
    expect(purchases.attached, ['A', 'B']);
    expect(purchases.forgotten, isEmpty);
  });
}

ClientRuntime _runtime(_Purchases purchases, List<String> calls) =>
    ClientRuntime(
        purchases: purchases,
        pair: (payload) async => PairingSession(
            payload: payload,
            sessionToken: payload.deviceId,
            trustedClientTokenExpiresAtMs: DateTime.now()
                .add(const Duration(days: 30))
                .millisecondsSinceEpoch),
        renew: (_) async => null,
        startStream: (_, {bool audioEnabled = false}) async =>
            const ActiveStreamSession(streamToken: 'stream'),
        stopStream: (_) async {
          calls.add('stop-stream');
        },
        startAlerts: (_) async => true,
        stopAlerts: () async {
          calls.add('stop-alerts');
        },
        clearStore: () async {
          calls.add('clear-store');
        });

class _Purchases implements BroadcastPurchaseCoordinator {
  final forgotten = <String>[];
  final attached = <String>[];
  Completer<void>? holdForget;
  Object? forgetFailure;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  void attachSession(PairingSession session) => attached.add(session.deviceId);
  @override
  Future<void> forgetRoom(String roomId) async {
    forgotten.add(roomId);
    await holdForget?.future;
    if (forgetFailure case final failure?) throw failure;
  }

  @override
  Future<void> retryPending() async {}
  @override
  ParentPurchaseState stateFor(String roomId) =>
      ParentPurchaseState(roomId: roomId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PairingPayload _payload(String room) => PairingPayload(
    schemaVersion: 2,
    host: '127.0.0.1',
    port: 1,
    deviceId: room,
    deviceName: room,
    pairingNonce: 'nonce',
    expiresAtMs:
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    capabilities: const {});
