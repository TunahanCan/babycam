import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/media/server_media_source.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('hanging runtime start cannot retain the global session queue',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final firstRuntimeStartEntered = Completer<void>();
    final releaseFirstRuntimeStart = Completer<void>();
    var hangFirstStart = true;
    var runtimeStarts = 0;
    var runtimeStops = 0;
    final server = MiuCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      httpPort: 0,
      startMediaOnSessionStart: false,
      streamSessionLifecycleTimeout: const Duration(milliseconds: 40),
      webRtcCleanupTimeout: const Duration(milliseconds: 40),
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) async {
        runtimeStarts++;
        if (!hangFirstStart) return;
        if (!firstRuntimeStartEntered.isCompleted) {
          firstRuntimeStartEntered.complete();
        }
        await releaseFirstRuntimeStart.future;
      },
      onStreamSessionStopped: (_) {
        runtimeStops++;
      },
    );
    addTearDown(server.dispose);
    addTearDown(() {
      if (!releaseFirstRuntimeStart.isCompleted) {
        releaseFirstRuntimeStart.complete();
      }
    });

    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final stopwatch = Stopwatch()..start();
    final starting = _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {
        'clientId': trusted.clientId,
        'video': true,
        'audio': false,
        MiuCamProtocolV2.streamAttemptId: 'attempt-a',
      },
    );
    await firstRuntimeStartEntered.future.timeout(const Duration(seconds: 1));
    final stopping = _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      trusted.token,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'attempt-a',
      },
    );

    final failedStart = await starting.timeout(const Duration(seconds: 1));
    final queuedStop = await stopping.timeout(const Duration(seconds: 1));
    stopwatch.stop();

    expect(failedStart.statusCode, HttpStatus.internalServerError);
    expect(failedStart.body['code'], 'MEDIA_START_FAILED');
    expect(queuedStop.statusCode, HttpStatus.ok);
    expect(runtimeStarts, 1);
    expect(runtimeStops, 1);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));

    releaseFirstRuntimeStart.complete();
    hangFirstStart = false;
    await pumpEventQueue();

    final recovered = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {
        'clientId': trusted.clientId,
        'video': true,
        'audio': false,
        MiuCamProtocolV2.streamAttemptId: 'attempt-b',
      },
    );
    expect(recovered.statusCode, HttpStatus.ok);
    expect(
      recovered.body[MiuCamProtocolV2.streamAttemptId],
      'attempt-b',
    );

    final recoveredStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      trusted.token,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'attempt-b',
      },
    );
    expect(recoveredStop.statusCode, HttpStatus.ok);
    expect(runtimeStarts, 2);
    expect(runtimeStops, 2);
  });

  test('production runtime chain admits successor before old capture releases',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final source = _HangingFirstMediaSource();
    late final ServerRuntime runtime;
    late final MiuCamServer server;
    server = MiuCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      httpPort: 0,
      mediaSource: source,
      startMediaOnSessionStart: false,
      mediaLifecycleOperationTimeout: const Duration(milliseconds: 25),
      streamSessionLifecycleTimeout: const Duration(milliseconds: 200),
      onStreamSessionStarted: (
        clientId, {
        required video,
        required audio,
        required mediaTransport,
      }) =>
          runtime.startStreamSession(
        clientId,
        StreamSessionOptions(video: video, audio: audio),
      ),
      onStreamSessionStopped: (clientId) => runtime.endSession(clientId),
    );
    final media = MediaRuntimeController(
      operationTimeout: const Duration(milliseconds: 25),
      onStartVideo: server.startVideoRuntime,
      onStopVideo: server.stopVideoRuntime,
      onStartAudio: server.startAudioRuntime,
      onStopAudio: server.stopAudioRuntime,
    );
    runtime = ServerRuntime(
      mediaRuntime: media,
      mediaOperationTimeout: const Duration(milliseconds: 25),
    );
    addTearDown(() async {
      source.releaseFirst();
      await runtime.dispose();
      await server.dispose();
    });

    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final failed = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {
        'clientId': trusted.clientId,
        'video': true,
        'audio': false,
        MiuCamProtocolV2.streamAttemptId: 'attempt-a',
      },
    ).timeout(const Duration(seconds: 1));
    expect(failed.statusCode, HttpStatus.internalServerError);
    expect(source.firstEntered.isCompleted, isTrue);

    final successor = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {
        'clientId': trusted.clientId,
        'video': true,
        'audio': false,
        MiuCamProtocolV2.streamAttemptId: 'attempt-b',
      },
    ).timeout(const Duration(seconds: 1));
    expect(successor.statusCode, HttpStatus.ok);
    expect(source.active, isTrue);
    expect(runtime.currentState.activeClients, 1);

    source.releaseFirst();
    await pumpEventQueue();

    expect(source.active, isTrue);
    expect(runtime.currentState.activeClients, 1);
    expect(runtime.currentState.cameraActive, isTrue);

    final stopped = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      trusted.token,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'attempt-b',
      },
    );
    expect(stopped.statusCode, HttpStatus.ok);
    expect(source.active, isFalse);
  });
}

Future<({int statusCode, Map<String, Object?> body})> _postJson(
  HttpClient client,
  int port,
  String path,
  String bearerToken,
  Map<String, Object?> body,
) async {
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  request.write(jsonEncode(body));
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  final decoded =
      responseBody.isEmpty ? <String, Object?>{} : jsonDecode(responseBody);
  return (
    statusCode: response.statusCode,
    body: decoded is Map
        ? Map<String, Object?>.from(decoded)
        : <String, Object?>{},
  );
}

class _HangingFirstMediaSource extends ServerMediaSource {
  final firstEntered = Completer<void>();
  final _firstRelease = Completer<void>();
  var calls = 0;
  var active = false;

  void releaseFirst() {
    if (!_firstRelease.isCompleted) _firstRelease.complete();
  }

  @override
  Future<void> reconcile({
    required bool video,
    required bool audio,
    required ServerVideoFrameSink onVideoFrame,
    required ServerAudioChunkSink onAudioChunk,
    ServerMediaErrorSink? onError,
  }) async {
    calls++;
    if (calls == 1) {
      firstEntered.complete();
      await _firstRelease.future;
    }
    active = video || audio;
  }

  @override
  bool get isActive => active;

  @override
  ServerMediaSourceSnapshot get snapshot => ServerMediaSourceSnapshot(
        active: active,
        videoFrames: 0,
        audioChunks: 0,
        lastVideoFrameAtMs: null,
        lastVideoFrameBytes: 0,
        lastAudioChunkAtMs: null,
        lastAudioChunkBytes: 0,
        lastError: null,
      );

  @override
  void resetDiagnostics() {}

  @override
  Future<void> stop() async {
    active = false;
  }
}
