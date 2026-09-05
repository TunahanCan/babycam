import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/alerts/client_alert_listener.dart';
import 'package:miucam/features/client/media/client_stream_health_state.dart';

import '../../support/blackhole_tcp_proxy.dart';

void main() {
  test('silent network loss reconnects with the last delivered alert cursor',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSockets = <WebSocket>[];
    final cursors = <String?>[];
    server.listen((request) async {
      cursors.add(
        request.uri.queryParameters[MiuCamProtocolV2.alertCursorQuery],
      );
      final socket = await WebSocketTransformer.upgrade(request);
      upstreamSockets.add(socket);
      socket.listen((_) {});
      socket.add(_alertJson('alert-${cursors.length}'));
    });
    final proxy = await BlackholeTcpProxy.start(server.port);
    final received = <String>[];
    final listener = ClientAlertListener(
      pingInterval: const Duration(milliseconds: 100),
      reconnectDelay: const Duration(milliseconds: 20),
      onAlert: (alert) => received.add(alert.id),
    );
    addTearDown(() async {
      await proxy.close();
      await listener.stop();
      for (final socket in upstreamSockets) {
        await socket.close();
      }
      await server.close(force: true);
    });

    await listener.start(_session(proxy.port));
    await _waitUntil(() => received.contains('alert-1'));
    proxy.blackholeExistingConnections();

    await _waitUntil(() => received.contains('alert-2'));
    expect(cursors.take(2), [null, 'alert-1']);
    expect(listener.isConnected, isTrue);
  });

  test(
      'websocket kapaninca otomatik reconnect edip bildirimi almaya devam eder',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var connections = 0;
    final secondAlert = Completer<void>();
    server.listen((request) async {
      if (request.uri.path != MiuCamProtocolV2.events ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer trusted-token',
      );
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {});
      connections++;
      socket.add(_alertJson('alert-$connections'));
      if (connections == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await socket.close();
      } else if (!secondAlert.isCompleted) {
        secondAlert.complete();
      }
    });
    final health = ClientStreamHealthState(nowMs: () => 1000)
      ..resetForNewWatchSession();
    final received = <String>[];
    final listener = ClientAlertListener(
      healthState: health,
      reconnectDelay: const Duration(milliseconds: 20),
      maxReconnectDelay: const Duration(milliseconds: 40),
      onAlert: (alert) => received.add(alert.id),
    );
    addTearDown(listener.stop);

    await listener.start(_session(server.port));
    await secondAlert.future.timeout(const Duration(seconds: 2));
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!received.contains('alert-2') && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(connections, greaterThanOrEqualTo(2));
    expect(received, containsAll(['alert-1', 'alert-2']));
    expect(health.snapshot().wsDisconnectCount, 1);
    expect(health.snapshot().reconnectCount, greaterThanOrEqualTo(1));
  });

  test('teslimat bitmeden ACK atmaz ve reconnect cursorunu son ACKe tasir',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final deliveryStarted = Completer<void>();
    final releaseDelivery = Completer<void>();
    final firstAck = Completer<void>();
    final reconnectCursor = Completer<String?>();
    var connections = 0;

    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      connections++;
      if (connections == 1) {
        socket.listen((data) async {
          final decoded = jsonDecode(data as String) as Map;
          if (decoded['type'] != MiuCamProtocolV2.alertAckType ||
              decoded[MiuCamProtocolV2.alertAckId] != 'alert-1') {
            return;
          }
          if (!firstAck.isCompleted) firstAck.complete();
          await socket.close();
        });
        socket.add(_alertJson('alert-1'));
        return;
      }

      reconnectCursor.complete(
        request.uri.queryParameters[MiuCamProtocolV2.alertCursorQuery],
      );
      socket.listen((_) {});
      socket.add(_alertJson('alert-2'));
    });

    final received = <String>[];
    final listener = ClientAlertListener(
      reconnectDelay: const Duration(milliseconds: 20),
      maxReconnectDelay: const Duration(milliseconds: 40),
      onAlert: (alert) async {
        received.add(alert.id);
        if (alert.id == 'alert-1') {
          deliveryStarted.complete();
          await releaseDelivery.future;
        }
      },
    );
    addTearDown(listener.stop);

    await listener.start(_session(server.port));
    await deliveryStarted.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(firstAck.isCompleted, isFalse);

    releaseDelivery.complete();
    await firstAck.future.timeout(const Duration(seconds: 2));

    expect(
      await reconnectCursor.future.timeout(const Duration(seconds: 2)),
      'alert-1',
    );
    await _waitUntil(() => received.contains('alert-2'));
    expect(received, ['alert-1', 'alert-2']);
  });

  test('failed alert closes socket before a later cumulative ACK can skip it',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final deliveredSecond = Completer<void>();
    var connections = 0;

    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {});
      connections++;
      socket.add(_alertJson('alert-1'));
      socket.add(_alertJson('alert-2'));
    });

    final attempts = <String>[];
    var firstAlertFailures = 1;
    final listener = ClientAlertListener(
      reconnectDelay: const Duration(milliseconds: 20),
      maxReconnectDelay: const Duration(milliseconds: 40),
      onAlert: (alert) async {
        attempts.add(alert.id);
        if (alert.id == 'alert-1' && firstAlertFailures > 0) {
          firstAlertFailures--;
          throw StateError('local delivery failed');
        }
        if (alert.id == 'alert-2' && !deliveredSecond.isCompleted) {
          deliveredSecond.complete();
        }
      },
    );
    addTearDown(listener.stop);

    await listener.start(_session(server.port));
    await deliveredSecond.future.timeout(const Duration(seconds: 2));

    expect(connections, greaterThanOrEqualTo(2));
    expect(attempts.take(3), ['alert-1', 'alert-1', 'alert-2']);
  });

  test('stop reconnect gecikmesini beklemeden tamamlanir', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path != MiuCamProtocolV2.events ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      await socket.close();
    });
    final health = ClientStreamHealthState(nowMs: () => 1000)
      ..resetForNewWatchSession();
    final listener = ClientAlertListener(
      healthState: health,
      reconnectDelay: const Duration(seconds: 5),
      maxReconnectDelay: const Duration(seconds: 5),
    );
    addTearDown(listener.stop);

    await listener.start(_session(server.port));
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (health.snapshot().reconnectCount == 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final stopwatch = Stopwatch()..start();
    await listener.stop().timeout(const Duration(milliseconds: 250));
    stopwatch.stop();

    expect(health.snapshot().reconnectCount, greaterThanOrEqualTo(1));
    expect(stopwatch.elapsedMilliseconds, lessThan(250));
  });

  test('ilk websocket baglantisini beklemeden alert dinleme armlanir',
      () async {
    final listener = ClientAlertListener(
      reconnectDelay: const Duration(seconds: 5),
      maxReconnectDelay: const Duration(seconds: 5),
    );
    addTearDown(listener.stop);

    final stopwatch = Stopwatch()..start();
    await listener
        .start(_session(9), waitForFirstConnection: false)
        .timeout(const Duration(milliseconds: 100));
    stopwatch.stop();

    expect(listener.isListening, isTrue);
    expect(stopwatch.elapsedMilliseconds, lessThan(100));
    await listener.stop().timeout(const Duration(milliseconds: 250));
  });

  test('yeni pairing oturumu eski websocket yerine yeni servera baglanir',
      () async {
    final firstServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final secondServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => firstServer.close(force: true));
    addTearDown(() => secondServer.close(force: true));
    final firstConnected = Completer<void>();
    final secondConnected = Completer<void>();
    firstServer.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {});
      if (!firstConnected.isCompleted) firstConnected.complete();
    });
    secondServer.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {});
      if (!secondConnected.isCompleted) secondConnected.complete();
      socket.add(_alertJson('new-session-alert'));
    });
    final received = <String>[];
    final listener = ClientAlertListener(
      reconnectDelay: const Duration(milliseconds: 20),
      maxReconnectDelay: const Duration(milliseconds: 40),
      onAlert: (alert) => received.add(alert.id),
    );
    addTearDown(listener.stop);

    await listener.start(_session(firstServer.port));
    await firstConnected.future.timeout(const Duration(seconds: 2));
    await listener.start(_session(secondServer.port));
    await secondConnected.future.timeout(const Duration(seconds: 2));
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!received.contains('new-session-alert') &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(received, contains('new-session-alert'));
    expect(listener.isListening, isTrue);
    expect(listener.isConnected, isTrue);
  });
}

String _alertJson(String id) => jsonEncode({
      'schemaVersion': 1,
      'id': id,
      'type': 'legacyAlert',
      'severity': 'info',
      'messageKey': 'legacyAlert',
      'message': 'Test bildirimi',
      'score': 0,
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
      'sourceDeviceId': 'server',
      'metadata': <String, Object?>{},
    });

PairingSession _session(int port) => PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        deviceId: 'server',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {'transport': 'http'},
      ),
      sessionToken: 'trusted-token',
      clientId: 'client-1',
      trustedClientTokenExpiresAtMs: 9999,
    );

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}
