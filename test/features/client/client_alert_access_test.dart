import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/alerts/client_alert_listener.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/remote_broadcast_access_client.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';

void main() {
  for (final initiallyLocked in [true, false]) {
    test(
        'alert-only ${initiallyLocked ? 'initial 402' : 'expiry'} stops retrying and surfaces room access',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final session = _session(server.port);
      var locked = initiallyLocked;
      var upgrades = 0;
      var statusReads = 0;
      final sockets = <WebSocket>[];
      final connected = Completer<void>();
      server.listen((request) async {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer trusted-token');
        if (request.uri.path == MiuCamProtocolV2.status) {
          statusReads++;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'broadcastAccess': (locked ? _locked : _unlocked).toJson(),
          }));
          await request.response.close();
          return;
        }
        expect(request.uri.path, MiuCamProtocolV2.events);
        upgrades++;
        if (locked) {
          request.response.statusCode = HttpStatus.paymentRequired;
          request.response.write(jsonEncode({
            'code': 'BROADCAST_ACCESS_LOCKED',
            'broadcastAccess': _locked.toJson(),
          }));
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((_) {});
        sockets.add(socket);
        if (!connected.isCompleted) connected.complete();
      });
      final remote = RemoteBroadcastAccessClient();
      final listener = ClientAlertListener(
        reconnectDelay: const Duration(milliseconds: 10),
        maxReconnectDelay: const Duration(milliseconds: 20),
        readBroadcastAccess: remote.snapshot,
      );
      var alertStops = 0;
      final runtime = ClientRuntime(
        pair: (_) async => session,
        startAlerts: (session) async {
          await listener.start(session, waitForFirstConnection: false);
          return listener.isListening;
        },
        stopAlerts: () async {
          alertStops++;
          await listener.stop();
        },
        alertConnectionStates: listener.connectionStates,
        refreshRemoteBroadcastAccess: remote.snapshot,
      );
      addTearDown(() async {
        await runtime.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      });
      await runtime.pairWithServer(session.payload);
      final denied = runtime.states
          .firstWhere((state) => state.error is BroadcastAccessLockedException);
      await runtime.startAlertListening();
      if (!initiallyLocked) {
        await connected.future.timeout(const Duration(seconds: 2));
        locked = true;
        await sockets.single.close();
      }
      final state = await denied.timeout(const Duration(seconds: 2));
      expect(state.phase, ClientRuntimePhase.pairedIdle);
      expect(state.alertsActive, isFalse);
      expect(state.activeStream, isNull);
      expect(state.broadcastAccess?.isLocked, isTrue);
      expect(runtime.alertTransportConnected, isFalse);
      expect(runtime.canManageBroadcastPurchase, isFalse);
      expect(listener.isListening, isFalse);
      expect(alertStops, 1);
      expect(statusReads, 1);
      expect(upgrades, 1);
      await Future<void>.delayed(const Duration(milliseconds: 75));
      expect(upgrades, 1);

      // After the room owner purchases, the parent can re-arm notifications
      // without pairing again. Its previous locked banner must clear as well.
      locked = false;
      final restored = runtime.states.firstWhere((state) =>
          state.broadcastAccess?.unlocked == true && state.alertsActive);
      await runtime.startAlertListening();
      final recovered = await restored.timeout(const Duration(seconds: 2));
      expect(recovered.error, isNull);
      expect(runtime.alertTransportConnected, isTrue);
      expect(listener.isListening, isTrue);
    });
  }

  test(
      'ordinary connection loss preserves backoff when room status is unavailable',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    var connections = 0;
    final reconnected = Completer<void>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((_) {});
      connections++;
      if (connections == 1) {
        await socket.close();
      } else if (!reconnected.isCompleted) {
        reconnected.complete();
      }
    });
    var checks = 0;
    final listener = ClientAlertListener(
      reconnectDelay: const Duration(milliseconds: 10),
      readBroadcastAccess: (_) async {
        checks++;
        throw const SocketException('Wi-Fi unavailable');
      },
    );
    addTearDown(() async {
      await listener.stop();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    await listener.start(_session(server.port));
    await reconnected.future.timeout(const Duration(seconds: 2));
    expect(checks, greaterThan(0));
    expect(listener.isListening, isTrue);
  });

  test(
      'an old room access failure cannot stop notifications for the current room',
      () async {
    final connections = StreamController<bool>.broadcast();
    final first = _session(1001);
    final second = _session(1002);
    var stops = 0;
    final runtime = ClientRuntime(
      pair: (payload) async =>
          payload.port == first.payload.port ? first : second,
      startAlerts: (_) async => true,
      stopAlerts: () async => stops++,
      alertConnectionStates: connections.stream,
    );
    addTearDown(runtime.dispose);
    addTearDown(connections.close);
    await runtime.pairWithServer(first.payload);
    await runtime.startAlertListening();
    await runtime.pairWithServer(second.payload);
    await runtime.startAlertListening();
    final before = stops;
    connections.addError(
        ClientAlertAccessLockedException(session: first, snapshot: _locked));
    await Future<void>.delayed(Duration.zero);
    expect(stops, before);
    expect(runtime.currentState.alertsActive, isTrue);
    expect(runtime.currentState.broadcastAccess, isNull);
  });
}

const _locked = BroadcastAccessSnapshot(
  unlocked: false,
  active: false,
  freeLimitMs: 7200000,
  usedMs: 7200000,
  remainingMs: 0,
  priceLabel: '350 TL',
  productId: BroadcastAccessConfig.productId,
);

const _unlocked = BroadcastAccessSnapshot(
  unlocked: true,
  active: true,
  freeLimitMs: 7200000,
  usedMs: 7200000,
  remainingMs: 7200000,
  priceLabel: '350 TL',
  productId: BroadcastAccessConfig.productId,
);

PairingSession _session(int port) => PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        deviceId: 'room-$port',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        capabilities: const {'transport': 'http'},
      ),
      sessionToken: 'trusted-token',
      clientId: 'parent',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 60)).millisecondsSinceEpoch,
    );
