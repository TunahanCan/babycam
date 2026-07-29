import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueChanged, VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/media/active_stream_session.dart';
import 'package:miucam/features/client/media/client_live_audio_pipeline.dart';
import 'package:miucam/features/client/media/client_media_stream_supervisor.dart';
import 'package:miucam/features/client/media/client_stream_health_state.dart';
import 'package:miucam/features/client/media/pcm_audio_output.dart';

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

  test('MJPEG burstte eski kareyi atip yalniz en yeniyi UIa verir', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/x-mixed-replace; boundary=frame',
      );
      request.response.add([
        ..._mjpegFrame([1, 2, 3], sequence: 1),
        ..._mjpegFrame([7, 8, 9], sequence: 2),
      ]);
      await request.response.close();
    });
    final received = Completer<Uint8List>();
    final health = ClientStreamHealthState();
    final supervisor = ClientMediaStreamSupervisor(
      session: _session(server.port),
      activeStream: const ActiveStreamSession(streamToken: 'stream'),
      audioEnabled: false,
      healthState: health,
      retryDelay: const Duration(seconds: 30),
      onVideoFrame: (frame) {
        if (!received.isCompleted) received.complete(frame);
      },
    );
    addTearDown(supervisor.stop);

    await supervisor.start();
    expect(
        await received.future.timeout(const Duration(seconds: 2)), [7, 8, 9]);
    final snapshot = health.snapshot();
    expect(snapshot.skippedVideoFrames, 0);
    expect(snapshot.coalescedVideoFrames, 1);
  });

  test('MJPEG sequence boslugu coalesced kareden ayri raporlanir', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/x-mixed-replace; boundary=frame',
      );
      request.response.add([
        ..._mjpegFrame([1, 2, 3], sequence: 1),
        ..._mjpegFrame([7, 8, 9], sequence: 3),
      ]);
      await request.response.close();
    });
    final received = Completer<Uint8List>();
    final health = ClientStreamHealthState();
    final supervisor = ClientMediaStreamSupervisor(
      session: _session(server.port),
      activeStream: const ActiveStreamSession(streamToken: 'stream'),
      audioEnabled: false,
      healthState: health,
      retryDelay: const Duration(seconds: 30),
      onVideoFrame: (frame) {
        if (!received.isCompleted) received.complete(frame);
      },
    );
    addTearDown(supervisor.stop);

    await supervisor.start();
    expect(
        await received.future.timeout(const Duration(seconds: 2)), [7, 8, 9]);
    final snapshot = health.snapshot();
    expect(snapshot.skippedVideoFrames, 1);
    expect(snapshot.coalescedVideoFrames, 1);
  });

  test('eski audio pipeline callbackleri yeni session healthini degistirmez',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = Completer<void>();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await server.close(force: true);
    });
    server.listen((request) async {
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/x-mixed-replace; boundary=frame',
      );
      request.response.add(
        '--frame\r\nContent-Length: 0\r\n\r\n\r\n'.codeUnits,
      );
      await request.response.flush();
      await release.future;
    });

    final pipelines = <_ControlledAudioPipeline>[];
    final health = ClientStreamHealthState(nowMs: () => 1000)
      ..resetForNewWatchSession();
    final supervisor = ClientMediaStreamSupervisor(
      session: _session(server.port),
      activeStream: const ActiveStreamSession(streamToken: 'stream'),
      audioEnabled: true,
      healthState: health,
      onVideoFrame: (_) {},
      audioPipelineFactory: (audioOutput) {
        final pipeline = _ControlledAudioPipeline(audioOutput);
        pipelines.add(pipeline);
        return pipeline;
      },
    );
    addTearDown(supervisor.stop);

    await supervisor.start();
    expect(pipelines, hasLength(1));
    final oldPipeline = pipelines.single;

    await supervisor.stop();
    health.resetForNewWatchSession();
    await supervisor.start();
    expect(pipelines, hasLength(2));
    final currentPipeline = pipelines.last;

    oldPipeline
      ..emitStatus(droppedBufferFrames: 4)
      ..emitAudioChunk();

    var snapshot = health.snapshot();
    expect(snapshot.skippedAudioChunks, 0);
    expect(snapshot.lastAudioChunkAtMs, isNull);

    currentPipeline
      ..emitStatus(droppedBufferFrames: 1)
      ..emitAudioChunk();

    snapshot = health.snapshot();
    expect(snapshot.skippedAudioChunks, 1);
    expect(snapshot.lastAudioChunkAtMs, 1000);
  });

  test('ses ac kapa video baglantisini yeniden baslatmaz', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = Completer<void>();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await server.close(force: true);
    });
    var videoRequests = 0;
    server.listen((request) async {
      videoRequests++;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/x-mixed-replace; boundary=frame',
      );
      request.response.add(
        '--frame\r\nContent-Length: 0\r\n\r\n\r\n'.codeUnits,
      );
      await request.response.flush();
      await release.future;
    });
    final pipelines = <_ControlledAudioPipeline>[];
    final supervisor = ClientMediaStreamSupervisor(
      session: _session(server.port),
      activeStream: const ActiveStreamSession(streamToken: 'stream'),
      audioEnabled: true,
      onVideoFrame: (_) {},
      audioPipelineFactory: (audioOutput) {
        final pipeline = _ControlledAudioPipeline(audioOutput);
        pipelines.add(pipeline);
        return pipeline;
      },
    );
    addTearDown(supervisor.stop);

    await supervisor.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(videoRequests, 1);
    expect(pipelines, hasLength(1));

    await supervisor.setAudioEnabled(false);
    expect(pipelines.single.stopCount, 1);
    expect(videoRequests, 1);

    await supervisor.setAudioEnabled(true);
    expect(pipelines, hasLength(2));
    expect(videoRequests, 1);
  });
}

class _ControlledAudioPipeline extends ClientLiveAudioPipeline {
  _ControlledAudioPipeline(PcmAudioSink audioOutput)
      : super(audioOutput: audioOutput);

  VoidCallback? _onAudioChunkWritten;
  ValueChanged<ClientLiveAudioStatus>? _onStatus;
  int stopCount = 0;

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
    _onAudioChunkWritten = onAudioChunkWritten;
    _onStatus = onStatus;
  }

  @override
  Future<void> stop() async => stopCount++;

  void emitAudioChunk() => _onAudioChunkWritten?.call();

  void emitStatus({required int droppedBufferFrames}) {
    _onStatus?.call(ClientLiveAudioStatus(
      event: 'write',
      connectedAtMs: 1000,
      sampleRate: 16000,
      channels: 1,
      wavHeaderParsed: true,
      networkBytesReceived: 640,
      pcmChunksParsed: 1,
      pcmBytesParsed: 640,
      bytesWritten: 640,
      chunksWritten: 1,
      bufferedBytes: 0,
      bufferedAudioMs: 0,
      droppedBufferBytes: droppedBufferFrames * 640,
      droppedBufferFrames: droppedBufferFrames,
      estimatedJitterMs: 0,
      targetPlayoutDelayMs: 60,
      playoutStarts: 1,
      playoutUnderruns: 0,
      nativeWriteAttempts: 1,
      nativeWriteCallsAccepted: 1,
      nativeWriteCallsDropped: 0,
      nativeBytesWritten: 640,
      nativeStatusBytesWritten: 640,
      droppedNativeWrites: 0,
      reconnects: 0,
      lastWriteAtMs: 1000,
      lastError: null,
      nativeStatus: const {},
    ));
  }
}

List<int> _mjpegFrame(List<int> jpeg, {required int sequence}) => [
      ...utf8.encode(
        '--frame\r\nContent-Type: image/jpeg\r\n'
        'Content-Length: ${jpeg.length}\r\n'
        'X-MiuCam-Sequence: $sequence\r\n'
        'X-MiuCam-Sent-At-Ms: ${1000 + sequence * 20}\r\n\r\n',
      ),
      ...jpeg,
      ...utf8.encode('\r\n'),
    ];

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
        capabilities: const {'transport': 'http_ws'},
      ),
      sessionToken: 'trusted',
      clientId: 'client',
    );
