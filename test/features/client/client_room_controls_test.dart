import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/controls/client_room_controls.dart';
import 'package:miucam/features/server/media/microphone_capture_service.dart';
import 'package:record/record.dart';

void main() {
  test('room detection pause reflects another parent talk and clears on idle',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var paused = true;
    server.listen((request) async {
      expect(request.uri.path, MiuCamProtocolV2.comfortState);
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer trusted-token');
      await _json(request.response, {
        'state': {
          'playing': false,
          'volume': 0,
          'loop': true,
          'updatedAtMs': 1,
        },
        'audioDetection': {'paused': paused, 'reason': paused ? 'talk' : null},
      });
    });
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        recorder: _FakeRecorder(),
        sampleRate: 16000,
        channels: 1,
      ),
    );
    addTearDown(controls.dispose);

    await controls.refreshComfort(_session(server.port));
    expect(controls.currentState.talking, isFalse);
    expect(controls.currentState.comfort?.playing, isFalse);
    expect(controls.currentState.isAudioDetectionPaused, isTrue);

    paused = false;
    await controls.refreshComfort(_session(server.port));
    expect(controls.currentState.isAudioDetectionPaused, isFalse);
  });

  test('comfort command and microphone PCM reach the room control endpoints',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final receivedTalk = BytesBuilder(copy: false);
    var talkAudioAuthorized = false;
    unawaited(server.forEach((request) async {
      if (request.uri.path == MiuCamProtocolV2.comfortCommand) {
        await utf8.decoder.bind(request).join();
        await _json(request.response, {
          'ok': true,
          'state': {
            'playing': true,
            'trackId': 'rain',
            'trackTitle': 'Rain',
            'volume': .6,
            'loop': true,
            'playlistTrackIds': const ['rain'],
            'updatedAtMs': 1,
          },
        });
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.talkStart) {
        final body = await _requestJson(request);
        await _json(request.response, {
          'ok': true,
          'session': {
            'talkToken': 'talk-token',
            MiuCamProtocolV2.talkAttemptId:
                body[MiuCamProtocolV2.talkAttemptId],
          },
        });
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.talkAudio) {
        talkAudioAuthorized = request.headers.value(
              HttpHeaders.authorizationHeader,
            ) ==
            'Bearer trusted-token';
        await for (final chunk in request) {
          receivedTalk.add(chunk);
        }
        await _json(request.response, {'ok': true});
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.talkStop) {
        await utf8.decoder.bind(request).join();
        await _json(request.response, {'ok': true});
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }));
    addTearDown(() => server.close(force: true));

    final recorder = _FakeRecorder();
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        sampleRate: 16000,
        channels: 1,
        recorder: recorder,
      ),
    );
    addTearDown(controls.dispose);
    final session = _session(server.port);

    final comfort = await controls.setComfort(
      session,
      action: 'play',
      trackId: 'rain',
      volume: .6,
    );
    await controls.startTalking(session);
    recorder.add(Uint8List.fromList([1, 0, 2, 0]));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await controls.stopTalking();

    expect(comfort?.playing, isTrue);
    expect(comfort?.trackId, 'rain');
    expect(receivedTalk.takeBytes(), [1, 0, 2, 0]);
    expect(talkAudioAuthorized, isTrue);
    expect(controls.currentState.talking, isFalse);
    expect(controls.currentState.talkBytesSent, 4);
  });

  test('missing v2 talk attempt echo rolls back the exact attempt', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var stops = 0;
    String? startedAttemptId;
    Map<String, Object?>? stopBody;
    unawaited(server.forEach((request) async {
      if (request.uri.path == MiuCamProtocolV2.talkStart) {
        final body = await _requestJson(request);
        startedAttemptId = body[MiuCamProtocolV2.talkAttemptId]?.toString();
        await _json(request.response, {
          'ok': true,
          'session': const <String, Object?>{'talkToken': 'unconfirmed-token'},
        });
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.talkStop) {
        stopBody = await _requestJson(request);
        stops++;
        await _json(request.response, {'ok': true});
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }));
    addTearDown(() => server.close(force: true));
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        sampleRate: 16000,
        channels: 1,
        recorder: _FakeRecorder(),
      ),
    );
    addTearDown(controls.dispose);

    await expectLater(
      controls.startTalking(_session(server.port)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('confirm'),
        ),
      ),
    );

    expect(stops, 1);
    expect(startedAttemptId, isNotNull);
    expect(
      stopBody?[MiuCamProtocolV2.talkAttemptId],
      startedAttemptId,
    );
    expect(stopBody?['talkToken'], isNull);
    expect(controls.currentState.talking, isFalse);
  });

  test('mismatched v2 talk attempt echo rolls back only the owned attempt',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? startedAttemptId;
    Map<String, Object?>? stopBody;
    unawaited(server.forEach((request) async {
      if (request.uri.path == MiuCamProtocolV2.talkStart) {
        final body = await _requestJson(request);
        startedAttemptId = body[MiuCamProtocolV2.talkAttemptId]?.toString();
        await _json(request.response, {
          'ok': true,
          'session': {
            'talkToken': 'foreign-token',
            MiuCamProtocolV2.talkAttemptId: 'foreign-attempt',
          },
        });
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.talkStop) {
        stopBody = await _requestJson(request);
        await _json(request.response, {'ok': true});
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }));
    addTearDown(() => server.close(force: true));
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        sampleRate: 16000,
        channels: 1,
        recorder: _FakeRecorder(),
      ),
    );
    addTearDown(controls.dispose);

    await expectLater(
      controls.startTalking(_session(server.port)),
      throwsA(isA<StateError>()),
    );

    expect(startedAttemptId, isNotNull);
    expect(
      stopBody?[MiuCamProtocolV2.talkAttemptId],
      startedAttemptId,
    );
    expect(
      stopBody?[MiuCamProtocolV2.talkAttemptId],
      isNot('foreign-attempt'),
    );
    expect(stopBody?['talkToken'], isNull);
    expect(controls.currentState.talking, isFalse);
  });

  test('microphone denial is typed before opening a room talk session',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var starts = 0;
    var stops = 0;
    server.listen((request) {
      unawaited(() async {
        if (request.uri.path == MiuCamProtocolV2.talkStart) {
          final body = await _requestJson(request);
          starts++;
          await _json(request.response, {
            'ok': true,
            'session': {
              'talkToken': 'talk-token',
              MiuCamProtocolV2.talkAttemptId:
                  body[MiuCamProtocolV2.talkAttemptId],
            },
          });
          return;
        }
        if (request.uri.path == MiuCamProtocolV2.talkAudio) {
          try {
            await request.drain<void>();
            await _json(request.response, {'ok': true});
          } catch (_) {
            // Permission denial force-closes the unused streaming upload.
          }
          return;
        }
        if (request.uri.path == MiuCamProtocolV2.talkStop) {
          await utf8.decoder.bind(request).join();
          stops++;
          await _json(request.response, {'ok': true});
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }());
    });
    addTearDown(() => server.close(force: true));
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        sampleRate: 16000,
        channels: 1,
        recorder: _FakeRecorder(hasPermissionResult: false),
      ),
    );
    addTearDown(controls.dispose);

    await expectLater(
      controls.startTalking(_session(server.port)),
      throwsA(isA<RoomMicrophonePermissionException>()),
    );

    expect(starts, 0);
    expect(stops, 0);
    expect(controls.currentState.talking, isFalse);
  });

  test('stop during permission prompt prevents a late room talk start',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final events = <String>[];
    var stops = 0;
    server.listen((request) {
      unawaited(() async {
        if (request.uri.path == MiuCamProtocolV2.talkStart) {
          final body = await _requestJson(request);
          events.add('server-started');
          await _json(request.response, {
            'ok': true,
            'session': {
              'talkToken': 'talk-token',
              MiuCamProtocolV2.talkAttemptId:
                  body[MiuCamProtocolV2.talkAttemptId],
            },
          });
          return;
        }
        if (request.uri.path == MiuCamProtocolV2.talkAudio) {
          try {
            await request.drain<void>();
            events.add('audio-closed');
            await _json(request.response, {'ok': true});
          } catch (_) {
            // A failed assertion may tear down the streaming client.
          }
          return;
        }
        if (request.uri.path == MiuCamProtocolV2.talkStop) {
          await utf8.decoder.bind(request).join();
          stops++;
          events.add('server-stopped');
          await _json(request.response, {'ok': true});
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }());
    });
    addTearDown(() => server.close(force: true));

    final recorder = _DelayedPermissionRecorder(events);
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        sampleRate: 16000,
        channels: 1,
        recorder: recorder,
        cleanupTimeout: const Duration(milliseconds: 30),
      ),
    );
    addTearDown(controls.dispose);

    final start = controls.startTalking(_session(server.port));
    await recorder.permissionRequested.future.timeout(
      const Duration(seconds: 1),
    );
    final stop = controls.stopTalking();
    await stop.timeout(const Duration(seconds: 1));
    expect(stops, 0);

    recorder.resolvePermission(true);
    await start.timeout(const Duration(seconds: 1));

    expect(stops, 0);
    expect(controls.currentState.talking, isFalse);
    expect(events, isNot(contains('server-started')));
    expect(events, isNot(contains('recorder-started')));
  });

  test('hic bitmeyen eski izin istegi sonraki talk baslangicini bloke etmez',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var starts = 0;
    server.listen((request) {
      unawaited(() async {
        if (request.uri.path == MiuCamProtocolV2.talkStart) {
          final body = await _requestJson(request);
          starts++;
          await _json(request.response, {
            'ok': true,
            'session': {
              'talkToken': 'talk-token-$starts',
              MiuCamProtocolV2.talkAttemptId:
                  body[MiuCamProtocolV2.talkAttemptId],
            },
          });
          return;
        }
        if (request.uri.path == MiuCamProtocolV2.talkAudio) {
          try {
            await request.drain<void>();
            await _json(request.response, {'ok': true});
          } catch (_) {}
          return;
        }
        if (request.uri.path == MiuCamProtocolV2.talkStop) {
          await utf8.decoder.bind(request).join();
          await _json(request.response, {'ok': true});
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }());
    });
    addTearDown(() => server.close(force: true));
    final firstPermission = Completer<bool>();
    final first = _ConfigurableRecorder(
      permissionResult: firstPermission.future,
    );
    final second = _ConfigurableRecorder();
    final recorders = [first, second];
    var factoryCalls = 0;
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        sampleRate: 16000,
        channels: 1,
        recorderFactory: () => recorders[factoryCalls++],
        cleanupTimeout: const Duration(milliseconds: 20),
      ),
      timeout: const Duration(milliseconds: 200),
    );
    addTearDown(controls.dispose);

    unawaited(controls.startTalking(_session(server.port)));
    await first.permissionRequested.future.timeout(const Duration(seconds: 1));
    await controls.stopTalking().timeout(const Duration(seconds: 1));
    await controls.startTalking(_session(server.port)).timeout(
          const Duration(seconds: 1),
        );

    expect(factoryCalls, 2);
    expect(second.startCalls, 1);
    expect(starts, 1);
    expect(controls.currentState.talking, isTrue);
    await controls.stopTalking();
  });

  test('lifecycle stop sirasinda reddedilen izin typed hata olarak korunur',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var roomRequests = 0;
    server.listen((request) async {
      roomRequests++;
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final recorder = _DelayedPermissionRecorder(<String>[]);
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        sampleRate: 16000,
        channels: 1,
        recorder: recorder,
        cleanupTimeout: const Duration(milliseconds: 30),
      ),
    );
    addTearDown(controls.dispose);

    final starting = controls.startTalking(_session(server.port));
    await recorder.permissionRequested.future.timeout(
      const Duration(seconds: 1),
    );
    await controls.stopTalking().timeout(const Duration(seconds: 1));
    recorder.resolvePermission(false);

    await expectLater(
      starting,
      throwsA(isA<RoomMicrophonePermissionException>()),
    );
    expect(roomRequests, 0);
    expect(controls.currentState.talking, isFalse);
  });

  test('stalled talk flush has a bounded single-flight stop', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var stops = 0;
    unawaited(server.forEach((request) async {
      if (request.uri.path == MiuCamProtocolV2.talkStart) {
        final body = await _requestJson(request);
        await _json(request.response, {
          'ok': true,
          'session': {
            'talkToken': 'talk-token',
            MiuCamProtocolV2.talkAttemptId:
                body[MiuCamProtocolV2.talkAttemptId],
          },
        });
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.talkAudio) {
        try {
          await request.drain<void>();
          await _json(request.response, {'ok': true});
        } catch (_) {
          // The client intentionally force-closes this stalled upload.
        }
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.talkStop) {
        await utf8.decoder.bind(request).join();
        stops++;
        await _json(request.response, {'ok': true});
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }));
    addTearDown(() => server.close(force: true));

    final flushStarted = Completer<void>();
    final blockedFlush = Completer<void>();
    addTearDown(() {
      if (!blockedFlush.isCompleted) blockedFlush.complete();
    });
    final recorder = _FakeRecorder();
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        sampleRate: 16000,
        channels: 1,
        recorder: recorder,
      ),
      talkFlushTimeout: const Duration(milliseconds: 50),
      talkRequestFlusher: (_) {
        if (!flushStarted.isCompleted) flushStarted.complete();
        return blockedFlush.future;
      },
    );
    addTearDown(controls.dispose);

    await controls.startTalking(_session(server.port));
    recorder.add(Uint8List.fromList([1, 0, 2, 0]));
    await flushStarted.future.timeout(const Duration(seconds: 1));

    final stopwatch = Stopwatch()..start();
    final firstStop = controls.stopTalking();
    final repeatedStop = controls.stopTalking();

    expect(identical(firstStop, repeatedStop), isTrue);
    await expectLater(firstStop, throwsA(isA<TimeoutException>()));
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(stops, 1);
    expect(controls.currentState.talking, isFalse);
    expect(controls.currentState.lastError, isA<TimeoutException>());
  });

  test('room talk stop is not blocked by a stalled recorder stop', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverStopped = Completer<void>();
    unawaited(server.forEach((request) async {
      if (request.uri.path == MiuCamProtocolV2.talkStart) {
        final body = await _requestJson(request);
        await _json(request.response, {
          'ok': true,
          'session': {
            'talkToken': 'talk-token',
            MiuCamProtocolV2.talkAttemptId:
                body[MiuCamProtocolV2.talkAttemptId],
          },
        });
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.talkAudio) {
        await request.drain<void>();
        await _json(request.response, {'ok': true});
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.talkStop) {
        await utf8.decoder.bind(request).join();
        if (!serverStopped.isCompleted) serverStopped.complete();
        await _json(request.response, {'ok': true});
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }));
    addTearDown(() => server.close(force: true));

    final recorder = _HangingStopRecorder();
    final controls = ClientRoomControls(
      microphone: MicrophoneCaptureService(
        sampleRate: 16000,
        channels: 1,
        recorder: recorder,
        cleanupTimeout: const Duration(milliseconds: 30),
      ),
      timeout: const Duration(milliseconds: 250),
    );
    addTearDown(() {
      recorder.releaseStop();
      return controls.dispose();
    });

    await controls.startTalking(_session(server.port));
    final stopping = controls.stopTalking();

    await serverStopped.future.timeout(const Duration(seconds: 1));
    expect(recorder.stopReleased, isFalse);
    await stopping.timeout(const Duration(seconds: 1));
    expect(controls.currentState.talking, isFalse);
  });
}

PairingSession _session(int port) => PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        deviceId: 'server',
        deviceName: 'Room',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: 'trusted-token',
      clientId: 'client',
    );

Future<void> _json(HttpResponse response, Map<String, Object?> body) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

Future<Map<String, Object?>> _requestJson(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  final decoded = jsonDecode(body);
  return Map<String, Object?>.from(decoded as Map);
}

class _FakeRecorder implements MicrophoneRecorderPort {
  _FakeRecorder({this.hasPermissionResult = true});

  final bool hasPermissionResult;
  final _stream = StreamController<Uint8List>.broadcast();

  void add(Uint8List bytes) => _stream.add(bytes);

  @override
  Future<void> dispose() => _stream.close();

  @override
  Future<bool> hasPermission() async => hasPermissionResult;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async =>
      _stream.stream;

  @override
  Future<void> stop() async {}
}

class _DelayedPermissionRecorder implements MicrophoneRecorderPort {
  _DelayedPermissionRecorder(this.events);

  final List<String> events;
  final permissionRequested = Completer<void>();
  final _permissionResult = Completer<bool>();
  final _stream = StreamController<Uint8List>();

  void resolvePermission(bool granted) {
    if (!_permissionResult.isCompleted) _permissionResult.complete(granted);
  }

  @override
  Future<void> dispose() => _stream.close();

  @override
  Future<bool> hasPermission() async {
    events.add('permission-requested');
    if (!permissionRequested.isCompleted) permissionRequested.complete();
    final granted = await _permissionResult.future;
    events.add('permission-resolved');
    return granted;
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    events.add('recorder-started');
    return _stream.stream;
  }

  @override
  Future<void> stop() async {
    events.add('recorder-stopped');
  }
}

class _ConfigurableRecorder implements MicrophoneRecorderPort {
  _ConfigurableRecorder({Future<bool>? permissionResult})
      : _permissionResult = permissionResult ?? Future<bool>.value(true);

  final Future<bool> _permissionResult;
  final permissionRequested = Completer<void>();
  final _stream = StreamController<Uint8List>.broadcast();
  int startCalls = 0;

  @override
  Future<void> dispose() => _stream.close();

  @override
  Future<bool> hasPermission() {
    if (!permissionRequested.isCompleted) permissionRequested.complete();
    return _permissionResult;
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    startCalls++;
    return _stream.stream;
  }

  @override
  Future<void> stop() async {}
}

class _HangingStopRecorder extends _FakeRecorder {
  final _stopRelease = Completer<void>();

  bool get stopReleased => _stopRelease.isCompleted;

  void releaseStop() {
    if (!_stopRelease.isCompleted) _stopRelease.complete();
  }

  @override
  Future<void> stop() => _stopRelease.future;
}
