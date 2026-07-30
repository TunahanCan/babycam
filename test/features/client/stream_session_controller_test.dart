import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/media/client_stream_health_state.dart';
import 'package:miucam/features/client/media/stream_session_controller.dart';
import 'package:miucam/features/client/media/webrtc/webrtc_client_connector.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';

void main() {
  test('health state session start sonrası ayrı video/audio request açmaz',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var videoRequests = 0;
    var audioRequests = 0;
    Map<String, Object?>? sessionStartBody;
    server.listen((request) async {
      if (request.uri.path == MiuCamProtocolV2.sessionStart) {
        final body = await utf8.decoder.bind(request).join();
        sessionStartBody = Map<String, Object?>.from(jsonDecode(body) as Map);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'ok': true,
          'streamToken': 'stream_token',
          MiuCamProtocolV2.streamAttemptId:
              sessionStartBody![MiuCamProtocolV2.streamAttemptId],
          'streamTokenExpiresAtMs': DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          'broadcastAccess': {
            'unlocked': false,
            'active': true,
            'freeLimitMs': 7200000,
            'usedMs': 1000,
            'remainingMs': 7199000,
            'priceLabel': r'$9.99',
            'productId': BroadcastAccessConfig.productId,
          },
        }));
        await request.response.close();
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.video) {
        videoRequests++;
        request.response.add([1, 2, 3]);
        await request.response.close();
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.audio) {
        audioRequests++;
        request.response.add([4, 5, 6]);
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    final health = ClientStreamHealthState();
    final controller = StreamSessionController(
      healthState: health,
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    final active = await controller.start(
      _session(server.port),
      audioEnabled: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final snapshot = health.snapshot();

    expect(snapshot.watchActive, isTrue);
    expect(sessionStartBody?['audio'], isTrue);
    expect(sessionStartBody?['video'], isTrue);
    expect(controller.lastStreamToken, 'stream_token');
    expect(active?.audioEnabled, isTrue);
    expect(active?.broadcastAccess?.remainingMs, 7199000);
    expect(snapshot.lastVideoFrameAtMs, isNull);
    expect(snapshot.lastAudioChunkAtMs, isNull);
    expect(videoRequests, 0);
    expect(audioRequests, 0);
  });

  test('session start hatası server mesajını taşır', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'ok': false,
          'code': 'MEDIA_START_FAILED',
          'message': 'Kamera izni verilmedi',
        }));
      await request.response.close();
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.start(_session(server.port)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Kamera izni verilmedi'),
        ),
      ),
    );
  });

  test('server paywall response preserves authoritative access snapshot',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.paymentRequired
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'ok': false,
          'code': 'BROADCAST_ACCESS_LOCKED',
          'broadcastAccess': {
            'unlocked': false,
            'active': false,
            'freeLimitMs': 7200000,
            'usedMs': 7200000,
            'remainingMs': 0,
            'priceLabel': r'$9.99',
            'productId': BroadcastAccessConfig.productId,
          },
        }));
      await request.response.close();
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.start(_session(server.port)),
      throwsA(
        isA<BroadcastAccessLockedException>()
            .having((error) => error.snapshot.isLocked, 'locked', isTrue)
            .having(
              (error) => error.snapshot.priceLabel,
              'localized price',
              r'$9.99',
            ),
      ),
    );
  });

  test('session start streamToken donmezse aktif state acilmaz', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var stops = 0;
    server.listen((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      if (request.uri.path == MiuCamProtocolV2.sessionStop) {
        stops++;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ok': true,
        if (request.uri.path == MiuCamProtocolV2.sessionStart)
          MiuCamProtocolV2.streamAttemptId:
              body[MiuCamProtocolV2.streamAttemptId],
      }));
      await request.response.close();
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.start(_session(server.port)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('stream token'),
        ),
      ),
    );

    expect(controller.isActive, isFalse);
    expect(controller.lastStreamToken, isNull);
    expect(stops, 1);
  });

  test('protocol v2 attempt onayi olmayan start guvenle geri alinir', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var stops = 0;
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      if (request.uri.path == MiuCamProtocolV2.sessionStop) {
        stops++;
        await _json(request.response, {'ok': true});
        return;
      }
      await _json(request.response, {
        'ok': true,
        'streamToken': 'unconfirmed-stream',
      });
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.start(_session(server.port)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('confirm'),
        ),
      ),
    );

    expect(stops, 1);
    expect(controller.isActive, isFalse);
  });

  test('WebRTC negotiation failure stops pilot session and starts fallback',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final transports = <String>[];
    final startAttempts = <String>[];
    final stopAttempts = <String>[];
    var stops = 0;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final json = Map<String, Object?>.from(jsonDecode(body) as Map);
      if (request.uri.path == MiuCamProtocolV2.sessionStop) {
        stops++;
        stopAttempts.add(
          json[MiuCamProtocolV2.streamAttemptId]!.toString(),
        );
        await _json(request.response, {'ok': true});
        return;
      }
      transports.add(json['mediaTransport']!.toString());
      startAttempts.add(
        json[MiuCamProtocolV2.streamAttemptId]!.toString(),
      );
      await _json(request.response, {
        'ok': true,
        'streamToken': 'stream-${transports.length}',
        MiuCamProtocolV2.streamAttemptId:
            json[MiuCamProtocolV2.streamAttemptId],
      });
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
      webRtcConnector: _FakeWebRtcConnector(failConnect: true),
    );
    addTearDown(controller.dispose);

    final active = await controller.start(
      _session(server.port, webRtc: true),
      audioEnabled: true,
    );

    expect(transports, ['webrtc', 'mjpeg_wav']);
    expect(stops, 1);
    expect(startAttempts, hasLength(2));
    expect(startAttempts[0], isNot(startAttempts[1]));
    expect(stopAttempts, [startAttempts[0]]);
    expect(active?.usesWebRtc, isFalse);
    expect(active?.streamToken, 'stream-2');
    expect(active?.transportFallbackReason, isA<WebRtcNegotiationException>());
  });

  test('successful WebRTC selection is retained and closed with session',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      if (request.uri.path == MiuCamProtocolV2.sessionStop) {
        await _json(request.response, {'ok': true});
        return;
      }
      await _json(request.response, {
        'ok': true,
        'streamToken': 'webrtc-stream',
        MiuCamProtocolV2.streamAttemptId:
            body[MiuCamProtocolV2.streamAttemptId],
      });
    });
    final connector = _FakeWebRtcConnector();
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
      webRtcConnector: connector,
    );
    addTearDown(controller.dispose);
    final session = _session(server.port, webRtc: true);

    final active = await controller.start(session);
    await controller.stop(session);

    expect(active?.usesWebRtc, isTrue);
    expect(connector.handle.closed, isTrue);
  });

  test('start ve stop attempt kimligini esler, yeni start taze kimlik kullanir',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final starts = <String>[];
    final stops = <String>[];
    server.listen((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      final attemptId = body[MiuCamProtocolV2.streamAttemptId]!.toString();
      if (request.uri.path == MiuCamProtocolV2.sessionStart) {
        starts.add(attemptId);
        await _json(request.response, {
          'ok': true,
          'streamToken': 'stream-${starts.length}',
          MiuCamProtocolV2.streamAttemptId: attemptId,
        });
        return;
      }
      stops.add(attemptId);
      await _json(request.response, {'ok': true});
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    final session = _session(server.port);

    await controller.start(session);
    await controller.stop(session);
    await controller.start(session);
    await controller.stop(session);

    expect(starts, hasLength(2));
    expect(starts[0], isNot(starts[1]));
    expect(stops, starts);
  });

  test('stop pending WebRTC negotiationi iptal edip fallbacki engeller',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var starts = 0;
    var stops = 0;
    server.listen((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      if (request.uri.path == MiuCamProtocolV2.sessionStart) {
        starts++;
        await _json(request.response, {
          'ok': true,
          'streamToken': 'stream-$starts',
          MiuCamProtocolV2.streamAttemptId:
              body[MiuCamProtocolV2.streamAttemptId],
        });
        return;
      }
      stops++;
      await _json(request.response, {'ok': true});
    });
    final connector = _PendingWebRtcConnector();
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
      webRtcConnector: connector,
    );
    addTearDown(controller.dispose);
    final session = _session(server.port, webRtc: true);

    final starting = controller.start(session);
    await connector.connectEntered.future.timeout(const Duration(seconds: 1));
    final stopping = controller.stop(session);

    await expectLater(starting, throwsA(isA<Exception>()));
    await stopping.timeout(const Duration(seconds: 1));
    expect(connector.cancelCalls, 1);
    expect(starts, 1);
    expect(stops, greaterThanOrEqualTo(1));
    expect(controller.isActive, isFalse);
  });

  test('basarisiz fallback sonrasi tum belirsiz attemptler yeniden durdurulur',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final startAttempts = <String>[];
    final stopAttempts = <String>[];
    var failFallback = true;
    server.listen((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      final attemptId = body[MiuCamProtocolV2.streamAttemptId]!.toString();
      if (request.uri.path == MiuCamProtocolV2.sessionStop) {
        stopAttempts.add(attemptId);
        request.response.statusCode =
            failFallback ? HttpStatus.internalServerError : HttpStatus.ok;
        await _json(request.response, {'ok': !failFallback});
        return;
      }
      startAttempts.add(attemptId);
      if (startAttempts.length == 1) {
        await _json(request.response, {
          'ok': true,
          'streamToken': 'pilot-stream',
          MiuCamProtocolV2.streamAttemptId: attemptId,
        });
        return;
      }
      if (failFallback) {
        request.response.statusCode = HttpStatus.internalServerError;
        await _json(request.response, {'ok': false});
        return;
      }
      await _json(request.response, {
        'ok': true,
        'streamToken': 'recovered-stream',
        MiuCamProtocolV2.streamAttemptId: attemptId,
      });
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
      webRtcConnector: _FakeWebRtcConnector(failConnect: true),
    );
    addTearDown(controller.dispose);
    final session = _session(server.port, webRtc: true);

    await expectLater(controller.start(session), throwsA(isA<StateError>()));
    final uncertainAttempts = startAttempts.toSet();
    expect(uncertainAttempts, hasLength(2));

    failFallback = false;
    final recovered = await controller.start(session);

    expect(
      stopAttempts.toSet(),
      containsAll(uncertainAttempts),
    );
    expect(recovered?.streamToken, 'recovered-stream');
    expect(
      startAttempts.last,
      isNot(isIn(uncertainAttempts)),
    );
  });

  test('yeni foreground start eski attempt stopu bitene kadar bekler',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final stopReceived = Completer<void>();
    final releaseStop = Completer<void>();
    addTearDown(() {
      if (!releaseStop.isCompleted) releaseStop.complete();
    });
    var starts = 0;
    server.listen((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      if (request.uri.path == MiuCamProtocolV2.sessionStart) {
        starts++;
        await _json(request.response, {
          'ok': true,
          'streamToken': 'stream-$starts',
          MiuCamProtocolV2.streamAttemptId:
              body[MiuCamProtocolV2.streamAttemptId],
        });
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.sessionStop) {
        if (!stopReceived.isCompleted) stopReceived.complete();
        await releaseStop.future;
        await _json(request.response, {'ok': true});
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    final session = _session(server.port);

    await controller.start(session);
    final stopping = controller.stop(session);
    await stopReceived.future.timeout(const Duration(seconds: 1));
    final restarting = controller.start(session);
    await pumpEventQueue();

    expect(starts, 1);
    releaseStop.complete();
    await stopping.timeout(const Duration(seconds: 1));
    final restarted = await restarting.timeout(const Duration(seconds: 1));

    expect(restarted?.streamToken, 'stream-2');
    expect(controller.isActive, isTrue);
    expect(controller.lastStreamToken, 'stream-2');
  });

  test('belirsiz attempt temizligi yeni eslesme yerine asil odaya gider',
      () async {
    final oldRoom = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final newRoom = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => oldRoom.close(force: true));
    addTearDown(() => newRoom.close(force: true));
    var rejectOldRoomStop = true;
    final oldRoomStartAttempts = <String>[];
    final oldRoomStopAttempts = <String>[];
    final oldRoomStopClients = <String>[];
    final newRoomStartAttempts = <String>[];
    final newRoomStopAttempts = <String>[];

    oldRoom.listen((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      final attempt = body[MiuCamProtocolV2.streamAttemptId]!.toString();
      if (request.uri.path == MiuCamProtocolV2.sessionStart) {
        oldRoomStartAttempts.add(attempt);
        await _json(request.response, {
          'ok': true,
          'streamToken': 'old-room-stream',
          MiuCamProtocolV2.streamAttemptId: attempt,
        });
        return;
      }
      oldRoomStopAttempts.add(attempt);
      oldRoomStopClients.add(body['clientId']!.toString());
      request.response.statusCode =
          rejectOldRoomStop ? HttpStatus.internalServerError : HttpStatus.ok;
      await _json(request.response, {'ok': !rejectOldRoomStop});
    });
    newRoom.listen((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      final attempt = body[MiuCamProtocolV2.streamAttemptId]!.toString();
      if (request.uri.path == MiuCamProtocolV2.sessionStart) {
        newRoomStartAttempts.add(attempt);
        await _json(request.response, {
          'ok': true,
          'streamToken': 'new-room-stream',
          MiuCamProtocolV2.streamAttemptId: attempt,
        });
        return;
      }
      newRoomStopAttempts.add(attempt);
      await _json(request.response, const {'ok': true});
    });

    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    final oldSession = _session(
      oldRoom.port,
      clientId: 'old-client',
      deviceId: 'old-server',
      sessionToken: 'old-token',
    );
    final newSession = _session(
      newRoom.port,
      clientId: 'new-client',
      deviceId: 'new-server',
      sessionToken: 'new-token',
    );

    await controller.start(oldSession);
    await expectLater(controller.stop(oldSession), throwsA(isA<StateError>()));
    final active = await controller.start(newSession);

    expect(oldRoomStartAttempts, hasLength(1));
    expect(oldRoomStopAttempts, [
      oldRoomStartAttempts.single,
      oldRoomStartAttempts.single,
    ]);
    expect(oldRoomStopClients, ['old-client', 'old-client']);
    expect(newRoomStopAttempts, isEmpty);
    expect(newRoomStartAttempts, hasLength(1));
    expect(newRoomStartAttempts.single, isNot(oldRoomStartAttempts.single));
    expect(active?.streamToken, 'new-room-stream');

    await controller.stop(newSession);

    expect(oldRoomStopAttempts, [
      oldRoomStartAttempts.single,
      oldRoomStartAttempts.single,
      oldRoomStartAttempts.single,
    ]);
    expect(newRoomStopAttempts, [newRoomStartAttempts.single]);

    rejectOldRoomStop = false;
    await controller.stop(newSession);

    expect(oldRoomStopAttempts, [
      oldRoomStartAttempts.single,
      oldRoomStartAttempts.single,
      oldRoomStartAttempts.single,
      oldRoomStartAttempts.single,
    ]);
    expect(oldRoomStopClients, [
      'old-client',
      'old-client',
      'old-client',
      'old-client',
    ]);
    expect(newRoomStopAttempts, [newRoomStartAttempts.single]);
  });

  test('ayni sahipte token yenileme stop icin yeni bearer kullanir', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? stopAuthorization;
    server.listen((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      if (request.uri.path == MiuCamProtocolV2.sessionStart) {
        await _json(request.response, {
          'ok': true,
          'streamToken': 'stream',
          MiuCamProtocolV2.streamAttemptId:
              body[MiuCamProtocolV2.streamAttemptId],
        });
        return;
      }
      stopAuthorization =
          request.headers.value(HttpHeaders.authorizationHeader);
      await _json(request.response, const {'ok': true});
    });
    final controller = StreamSessionController(
      streamTimeout: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    final original = _session(
      server.port,
      clientId: 'same-client',
      deviceId: 'same-server',
      sessionToken: 'old-bearer',
    );

    await controller.start(original);
    await controller.stop(
      original.copyWith(sessionToken: 'renewed-bearer'),
    );

    expect(stopAuthorization, 'Bearer renewed-bearer');
  });
}

PairingSession _session(
  int port, {
  bool webRtc = false,
  String sessionToken = 'token',
  String clientId = 'client',
  String deviceId = 'server',
}) =>
    PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        deviceId: deviceId,
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: {
          'transport': 'http',
          if (webRtc) 'webrtc': const {'enabled': true},
        },
      ),
      sessionToken: sessionToken,
      clientId: clientId,
    );

Future<void> _json(HttpResponse response, Map<String, Object?> body) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

class _FakeWebRtcConnector implements WebRtcClientConnector {
  _FakeWebRtcConnector({this.failConnect = false});

  final bool failConnect;
  final handle = _FakeWebRtcHandle();

  @override
  bool get isAvailable => true;

  @override
  Future<WebRtcClientMediaHandle> connect({
    required PairingSession session,
    required String streamToken,
    required bool video,
    required bool audio,
  }) async {
    if (failConnect) {
      throw const WebRtcNegotiationException('pilot failed');
    }
    return handle;
  }

  @override
  Future<void> cancelPendingConnections() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> initialize() async => true;
}

class _FakeWebRtcHandle implements WebRtcClientMediaHandle {
  final _renderer = RTCVideoRenderer();
  bool closed = false;

  @override
  RTCPeerConnectionState get connectionState =>
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  @override
  Stream<RTCPeerConnectionState> get connectionStates => const Stream.empty();

  @override
  String get peerId => 'peer';

  @override
  RTCVideoRenderer get videoRenderer => _renderer;

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _PendingWebRtcConnector implements WebRtcClientConnector {
  final connectEntered = Completer<void>();
  final _connection = Completer<WebRtcClientMediaHandle>();
  var cancelCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<WebRtcClientMediaHandle> connect({
    required PairingSession session,
    required String streamToken,
    required bool video,
    required bool audio,
  }) {
    if (!connectEntered.isCompleted) connectEntered.complete();
    return _connection.future;
  }

  @override
  Future<void> cancelPendingConnections() async {
    cancelCalls++;
    if (!_connection.isCompleted) {
      _connection.completeError(
        const WebRtcNegotiationException('cancelled'),
      );
    }
  }

  @override
  Future<void> dispose() async {}
}
