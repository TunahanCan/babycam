import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/services/server/active_client_registry.dart';
import 'package:miucam/services/server/miucam_event_socket_controller.dart';

void main() {
  test('short reconnect keeps analysis armed and replays only alerts after ACK',
      () async {
    var connectedCalls = 0;
    var disconnectedCalls = 0;
    final controller = MiuCamEventSocketController(
      activeClients: ActiveClientRegistry(
        tokenService: PairingTokenService(),
        maxActiveClients: 5,
      ),
      resolveClientId: (_) => 'parent-1',
      writeConnectionLimitError: (response, _) async {
        response.statusCode = HttpStatus.tooManyRequests;
        await response.close();
      },
      onClientConnected: (_) async => connectedCalls++,
      onClientDisconnected: (_) async => disconnectedCalls++,
      isDisposed: () => false,
      connectedLog: (_) => 'connected',
      onLog: (_) {},
      reconnectGracePeriod: const Duration(milliseconds: 250),
      maxReplayAlerts: 4,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (!await controller.handleUpgrade(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    addTearDown(() async {
      await controller.closeAll();
      await server.close(force: true);
    });

    final first = await _connect(server.port);
    addTearDown(first.close);
    final firstMessages = <String>[];
    first.listen((data) => firstMessages.add(data as String));
    await _waitUntil(() => connectedCalls == 1);

    controller.broadcastText(_alertJson('alert-1'));
    await _waitUntil(() => firstMessages.length == 1);
    first.add(jsonEncode({
      'type': MiuCamProtocolV2.alertAckType,
      MiuCamProtocolV2.alertAckId: 'alert-1',
    }));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await first.close();
    await _waitUntil(() => controller.clientCount == 0);

    controller.broadcastText(_alertJson('alert-during-gap'));
    final second = await _connect(server.port);
    addTearDown(second.close);
    final replayed = <String>[];
    second.listen((data) => replayed.add(data as String));
    await _waitUntil(() => replayed.isNotEmpty);

    expect(
      replayed.map(_alertIdFromJson),
      ['alert-during-gap'],
      reason: 'ACK edilen alert reconnectte ebeveyni tekrar uyarmamali.',
    );
    expect(connectedCalls, 1);
    expect(disconnectedCalls, 0);

    await second.close();
    await _waitUntil(() => disconnectedCalls == 1);
  });

  test('legacy client without replay capability never receives old alerts',
      () async {
    final harness = await _ControllerHarness.start(
      reconnectGracePeriod: Duration.zero,
    );
    addTearDown(harness.close);

    final first = await _connect(harness.port, replay: false);
    final firstMessages = <String>[];
    first.listen((data) => firstMessages.add(data as String));
    harness.controller.broadcastText(_alertJson('legacy-live'));
    await _waitUntil(() => firstMessages.isNotEmpty);
    await first.close();
    await _waitUntil(() => harness.controller.clientCount == 0);

    final second = await _connect(harness.port, replay: false);
    final secondMessages = <String>[];
    second.listen((data) => secondMessages.add(data as String));
    harness.controller.broadcastText(_alertJson('legacy-after-reconnect'));
    await _waitUntil(() => secondMessages.isNotEmpty);

    expect(
      secondMessages.map(_alertIdFromJson),
      ['legacy-after-reconnect'],
    );
    await second.close();
  });

  test('expired replay is dropped while a recent gap alert is delivered',
      () async {
    var replayNowMs = 0;
    final harness = await _ControllerHarness.start(
      reconnectGracePeriod: const Duration(seconds: 1),
      replayNowMs: () => replayNowMs,
      maxReplayAge: const Duration(minutes: 2),
    );
    addTearDown(harness.close);

    final first = await _connect(harness.port);
    first.listen((_) {});
    harness.controller.broadcastText(_alertJson('too-old'));
    await first.close();
    await _waitUntil(() => harness.controller.clientCount == 0);

    replayNowMs = const Duration(minutes: 2, milliseconds: 1).inMilliseconds;
    harness.controller.broadcastText(_alertJson('recent'));
    final second = await _connect(harness.port);
    final messages = <String>[];
    second.listen((data) => messages.add(data as String));
    await _waitUntil(() => messages.isNotEmpty);

    expect(messages.map(_alertIdFromJson), ['recent']);
    await second.close();
  });

  test('one overlapping socket detach cannot advance the client cursor',
      () async {
    final harness = await _ControllerHarness.start(
      reconnectGracePeriod: const Duration(seconds: 1),
    );
    addTearDown(harness.close);

    final first = await _connect(harness.port);
    final second = await _connect(harness.port);
    first.listen((_) {});
    second.listen((_) {});
    harness.controller.broadcastText(_alertJson('not-acked'));
    first.add(jsonEncode({'type': MiuCamProtocolV2.alertDetachType}));
    await first.close();
    await _waitUntil(() => harness.controller.clientCount == 1);
    await second.close();
    await _waitUntil(() => harness.controller.clientCount == 0);

    final reconnected = await _connect(harness.port);
    final replayed = <String>[];
    reconnected.listen((data) => replayed.add(data as String));
    await _waitUntil(() => replayed.isNotEmpty);

    expect(replayed.map(_alertIdFromJson), ['not-acked']);
    await reconnected.close();
  });
}

class _ControllerHarness {
  _ControllerHarness(this.controller, this.server);

  final MiuCamEventSocketController controller;
  final HttpServer server;

  int get port => server.port;

  static Future<_ControllerHarness> start({
    required Duration reconnectGracePeriod,
    Duration maxReplayAge = const Duration(minutes: 2),
    int Function()? replayNowMs,
  }) async {
    final controller = MiuCamEventSocketController(
      activeClients: ActiveClientRegistry(
        tokenService: PairingTokenService(),
        maxActiveClients: 5,
      ),
      resolveClientId: (_) => 'parent-1',
      writeConnectionLimitError: (response, _) async {
        response.statusCode = HttpStatus.tooManyRequests;
        await response.close();
      },
      onClientConnected: (_) {},
      onClientDisconnected: (_) {},
      isDisposed: () => false,
      connectedLog: (_) => 'connected',
      onLog: (_) {},
      reconnectGracePeriod: reconnectGracePeriod,
      maxReplayAge: maxReplayAge,
      replayNowMs: replayNowMs,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (!await controller.handleUpgrade(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    return _ControllerHarness(controller, server);
  }

  Future<void> close() async {
    await controller.closeAll();
    await server.close(force: true);
  }
}

Future<WebSocket> _connect(int port, {bool replay = true}) => WebSocket.connect(
      Uri(
        scheme: 'ws',
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        path: MiuCamProtocolV2.events,
        queryParameters: replay
            ? const {
                MiuCamProtocolV2.alertReplayVersionQuery:
                    MiuCamProtocolV2.alertReplayVersion,
              }
            : null,
      ).toString(),
    );

String _alertJson(String id) => jsonEncode({
      'schemaVersion': 1,
      'id': id,
      'type': 'cryDetected',
      'severity': 'warning',
      'messageKey': 'parentEpisodeCryAlert',
      'message': 'Ağlama benzeri ses olabilir.',
      'score': .82,
      'timestampMs': 42,
      'sourceDeviceId': 'server',
      'metadata': <String, Object?>{},
    });

String _alertIdFromJson(String data) =>
    (jsonDecode(data) as Map<String, Object?>)['id']! as String;

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}
