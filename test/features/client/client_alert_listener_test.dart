import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/alerts/client_alert_listener.dart';
import 'package:mimicam/features/client/media/client_stream_health_state.dart';

void main() {
  test(
      'websocket kapaninca otomatik reconnect edip bildirimi almaya devam eder',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var connections = 0;
    final secondAlert = Completer<void>();
    server.listen((request) async {
      if (request.uri.path != MimiCamProtocolV2.events ||
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
        schemaVersion: MimiCamProtocolV2.schemaVersion,
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
