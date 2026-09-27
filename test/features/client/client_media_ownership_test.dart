import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/active_stream_session.dart';
import 'package:miucam/features/client/media/client_live_audio_pipeline.dart';
import 'package:miucam/features/client/media/client_media_stream_supervisor.dart';
import 'package:miucam/features/client/media/pcm_audio_output.dart';

void main() {
  for (final widgetReleased in [false, true]) {
    test('role exit owns media cleanup after widget release=$widgetReleased',
        () async {
      final runtime = _runtime();
      final client = _PendingClient();
      final audio = _AudioPipeline()..holdStop = Completer<void>();
      final supervisor = _supervisor(client, audio);
      Future<void> teardown() {
        supervisor.cancelImmediately();
        return supervisor.terminate();
      }

      expect(runtime.registerMediaTeardown(teardown), isTrue);
      await supervisor.start();
      await client.requested.future;
      final widgetStop =
          widgetReleased ? runtime.unregisterMediaTeardown(teardown) : null;
      var completed = false;
      final closing = runtime.dispose().then((_) => completed = true);
      expect(client.closed, isTrue,
          reason: 'HTTP must close before waiting for native audio teardown.');
      expect(audio.stops, 1);
      await pumpEventQueue();
      expect(completed, isFalse);
      audio.holdStop!.complete();
      await widgetStop;
      await closing;
      expect(completed, isTrue);
      expect(audio.stops, 1);
    });
  }

  test('role exit awaits audio start that was already accepted by a screen',
      () async {
    final runtime = _runtime();
    final client = _PendingClient();
    final audio = _AudioPipeline()..holdStart = Completer<void>();
    final supervisor = _supervisor(client, audio);
    runtime.registerMediaTeardown(() {
      supervisor.cancelImmediately();
      return supervisor.terminate();
    });
    final starting = supervisor.start();
    await audio.startEntered.future;
    var completed = false;
    final closing = runtime.dispose().then((_) => completed = true);
    await pumpEventQueue();
    expect(client.closed, isTrue);
    expect(completed, isFalse);
    audio.holdStart!.complete();
    await starting;
    await closing;
    expect(audio.stops, 1,
        reason: 'The same terminal cleanup also covers a late accepted start.');
  });

  test('failed widget media cleanup still prevents successful role handover',
      () async {
    final runtime = _runtime();
    final failure = StateError('audio output still owns playback');
    Future<void> teardown() async => throw failure;
    runtime.registerMediaTeardown(teardown);
    await expectLater(
        runtime.unregisterMediaTeardown(teardown), throwsA(same(failure)));
    await expectLater(runtime.dispose(), throwsA(same(failure)));
  });

  test('terminal supervisor preserves an audio shutdown failure for the role',
      () async {
    final runtime = _runtime();
    final failure = StateError('native audio stop failed');
    final audio = _AudioPipeline()..stopFailure = failure;
    final client = _PendingClient();
    final supervisor = _supervisor(client, audio);
    runtime.registerMediaTeardown(supervisor.terminate);
    await supervisor.start();
    await expectLater(runtime.dispose(), throwsA(same(failure)));
    expect(client.closed, isTrue);
    await supervisor.start();
    expect(audio.stops, 1,
        reason: 'A permanently released supervisor cannot restart.');
  });

  test('a late screen cannot register media on a disposed role', () async {
    final runtime = _runtime();
    await runtime.dispose();
    var canceled = false;
    final accepted = runtime.registerMediaTeardown(() async {
      canceled = true;
    });
    expect(accepted, isFalse);
    expect(canceled, isTrue);
  });
}

ClientRuntime _runtime() => ClientRuntime(
      pair: (payload) async =>
          PairingSession(payload: payload, sessionToken: 'token'),
    );

ClientMediaStreamSupervisor _supervisor(
        _PendingClient client, _AudioPipeline audio) =>
    ClientMediaStreamSupervisor(
      session: const PairingSession(
        payload: PairingPayload(
          schemaVersion: 2,
          host: '127.0.0.1',
          port: 8080,
          deviceId: 'room',
          deviceName: 'Room',
          pairingNonce: 'nonce',
          expiresAtMs: 9999999999999,
          capabilities: {},
        ),
        sessionToken: 'token',
      ),
      activeStream: const ActiveStreamSession(streamToken: 'stream'),
      audioEnabled: true,
      onVideoFrame: (_) {},
      videoClientFactory: () => client,
      audioPipelineFactory: (_) => audio,
    );

class _PendingClient implements HttpClient {
  final requested = Completer<void>();
  final request = Completer<HttpClientRequest>();
  bool closed = false;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri uri) {
    requested.complete();
    return request.future;
  }

  @override
  void close({bool force = false}) {
    closed = true;
    if (!request.isCompleted) {
      request.completeError(const HttpException('closed'));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AudioPipeline extends ClientLiveAudioPipeline {
  _AudioPipeline() : super(audioOutput: const PcmAudioOutput());

  Completer<void>? holdStart;
  Completer<void>? holdStop;
  final startEntered = Completer<void>();
  int stops = 0;
  Object? stopFailure;

  @override
  Future<void> start({
    required Uri uri,
    required String pairedServerHost,
    required int pairedServerPort,
    String? bearerToken,
    bool Function(Object error)? shouldRetry,
    VoidCallback? onAudioChunkWritten,
    ValueChanged<ClientLiveAudioStatus>? onStatus,
    ValueChanged<Object>? onError,
  }) async {
    startEntered.complete();
    await holdStart?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    await holdStop?.future;
    if (stopFailure != null) throw stopFailure!;
  }
}
