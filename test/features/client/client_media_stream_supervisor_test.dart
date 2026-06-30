import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/media/active_stream_session.dart';
import 'package:mimicam/features/client/media/client_media_stream_supervisor.dart';
import 'package:mimicam/features/client/media/client_stream_health_state.dart';

void main() {
  test('401 media response session refresh ister ve retry loop yapmaz',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var videoRequests = 0;
    server.listen((request) async {
      videoRequests++;
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });
    final refreshed = Completer<ClientMediaStreamFailure>();
    final supervisor = ClientMediaStreamSupervisor(
      session: _session(server.port),
      activeStream: const ActiveStreamSession(streamToken: 'expired'),
      audioEnabled: false,
      retryDelay: const Duration(milliseconds: 20),
      onVideoFrame: (_) {},
      onSessionRefreshRequired: (failure) async {
        if (!refreshed.isCompleted) refreshed.complete(failure);
      },
    );
    addTearDown(supervisor.stop);

    await supervisor.start();
    final failure = await refreshed.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(failure.kind, ClientMediaStreamFailureKind.unauthorized);
    expect(videoRequests, 1);
  });

  test('429 media response fatal error olarak runtime katmanına çıkar',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.tooManyRequests;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'code': 'MAX_ACTIVE_CLIENTS'}));
      await request.response.close();
    });
    final fatal = Completer<ClientMediaStreamFailure>();
    final supervisor = ClientMediaStreamSupervisor(
      session: _session(server.port),
      activeStream: const ActiveStreamSession(streamToken: 'overflow'),
      audioEnabled: false,
      onVideoFrame: (_) {},
      onFatalError: (failure) {
        if (!fatal.isCompleted) fatal.complete(failure);
      },
    );
    addTearDown(supervisor.stop);

    await supervisor.start();
    final failure = await fatal.future.timeout(const Duration(seconds: 2));

    expect(failure.kind, ClientMediaStreamFailureKind.clientLimit);
    expect(failure.statusCode, HttpStatus.tooManyRequests);
  });

  test('video stall read timeout health state ve reconnect status üretir',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    server.listen((request) async {
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/x-mixed-replace; boundary=frame',
      );
      request.response
          .add('--frame\r\nContent-Length: 0\r\n\r\n\r\n'.codeUnits);
      await request.response.flush();
      await release.future;
    });
    final reconnect = Completer<ClientMediaStreamUpdate>();
    final health = ClientStreamHealthState(nowMs: () => 1000);
    final supervisor = ClientMediaStreamSupervisor(
      session: _session(server.port),
      activeStream: const ActiveStreamSession(streamToken: 'stream'),
      audioEnabled: false,
      healthState: health,
      readTimeout: const Duration(milliseconds: 40),
      retryDelay: const Duration(seconds: 30),
      onVideoFrame: (_) {},
      onStatus: (update) {
        if (update.event == 'video_reconnecting' && !reconnect.isCompleted) {
          reconnect.complete(update);
        }
      },
    );
    addTearDown(supervisor.stop);

    await supervisor.start();
    final update = await reconnect.future.timeout(const Duration(seconds: 2));

    expect(update.failure?.kind, ClientMediaStreamFailureKind.timeout);
    expect(health.snapshot().streamTimedOut, isTrue);
    expect(health.snapshot().reconnectCount, 1);
  });
}

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
        capabilities: const {'transport': 'http_ws'},
      ),
      sessionToken: 'trusted',
      clientId: 'client',
    );
