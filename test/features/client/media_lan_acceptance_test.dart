import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/media/active_stream_session.dart';
import 'package:miucam/features/client/media/client_media_stream_supervisor.dart';
import 'package:miucam/features/client/media/client_stream_health_state.dart';
import 'package:miucam/features/client/media/pcm_audio_output.dart';
import 'package:miucam/services/server/wav_pcm16.dart';

/// Uses real loopback TCP/HTTP and both production client media pipelines.
/// Only the room's producer and the native speaker boundary are substitutes.
void main() {
  test('fragmented WAV and MJPEG reach playback with intact sample order',
      () async {
    final rig = await _MediaRig.create();
    addTearDown(rig.close);
    await rig.supervisor.start();
    final video = await rig.room.request(MiuCamProtocolV2.video);
    final audio = await rig.room.request(MiuCamProtocolV2.audio);
    final pcm = _pcmFrames(6);

    await video.video(_jpeg, sequence: 1, fragmented: true);
    await audio.audio(pcm, fragmented: true);
    await _until(() => rig.sink.writes.length == 6 && rig.frames.isNotEmpty);

    expect(rig.frames.single, _jpeg);
    expect(rig.sink.formats, [(sampleRate: 16000, channels: 1)]);
    expect(rig.sink.writes.expand((bytes) => bytes).toList(), pcm);
    expect(rig.sink.writes.every((bytes) => bytes.length == 640), isTrue,
        reason: 'HTTP chunks must not become partial PCM playback frames.');
    for (final request in [video, audio]) {
      expect(request.request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer trusted-parent');
      expect(request.request.uri.queryParameters['streamToken'], 'watch-1');
    }
    expect(rig.health.snapshot().lastAudioChunkAtMs, isNotNull);
    expect(rig.health.snapshot().lastVideoFrameAtMs, isNotNull);
    await rig.supervisor.terminate();
    expect(rig.sink.active, isFalse);
  });

  test('mute releases the real audio connection while video keeps its owner',
      () async {
    final rig = await _MediaRig.create();
    addTearDown(rig.close);
    await rig.supervisor.start();
    final video = await rig.room.request(MiuCamProtocolV2.video);
    final audio = await rig.room.request(MiuCamProtocolV2.audio);
    await video.video(_jpeg, sequence: 1);
    await audio.audio(_pcmFrames(6));
    await _until(() => rig.sink.writes.isNotEmpty);

    await rig.supervisor.setAudioEnabled(false);
    final writesAtMute = rig.sink.writes.length;
    expect(rig.sink.active, isFalse);
    await video.video(_jpeg, sequence: 2);
    await _until(() => rig.frames.length == 2);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(rig.sink.writes.length, writesAtMute);
    expect(rig.room.count(MiuCamProtocolV2.audio), 1);
    expect(rig.room.count(MiuCamProtocolV2.video), 1);

    await rig.supervisor.setAudioEnabled(true);
    final resumedAudio = await rig.room.request(MiuCamProtocolV2.audio, at: 1);
    await resumedAudio.audio(_pcmFrames(6, startSample: 7000));
    await _until(() => rig.sink.writes.length > writesAtMute);
    expect(rig.sink.writes[writesAtMute], _pcmFrames(1, startSample: 7000));
    expect(rig.room.count(MiuCamProtocolV2.video), 1);
    expect(rig.sink.maximumActiveOwners, 1);
  });

  test('both streams recover after connection loss without stale PCM replay',
      () async {
    final rig = await _MediaRig.create();
    addTearDown(rig.close);
    await rig.supervisor.start();
    final video = await rig.room.request(MiuCamProtocolV2.video);
    final audio = await rig.room.request(MiuCamProtocolV2.audio);
    await video.video(_jpeg, sequence: 1);
    await audio.audio(_pcmFrames(6));
    await _until(() => rig.sink.writes.isNotEmpty && rig.frames.isNotEmpty);
    await Future.wait([video.close(), audio.close()]);

    final nextVideo = await rig.room.request(MiuCamProtocolV2.video, at: 1);
    final nextAudio = await rig.room.request(MiuCamProtocolV2.audio, at: 1);
    final oldWrites = rig.sink.writes.length;
    await nextVideo.video(_jpeg, sequence: 2);
    await nextAudio.audio(_pcmFrames(6, startSample: 9000));
    await _until(
        () => rig.sink.writes.length > oldWrites && rig.frames.length == 2);

    expect(rig.sink.writes[oldWrites], _pcmFrames(1, startSample: 9000));
    expect(rig.sink.formats, hasLength(2));
    expect(rig.sink.maximumActiveOwners, 1);
    expect(rig.updates.any((event) => event.event == 'video_reconnecting'),
        isTrue);
    expect(rig.updates.any((event) => event.event == 'audio_reconnecting'),
        isTrue);
    await rig.supervisor.terminate();
    final requestsAtExit = rig.room.requests.length;
    final writesAtExit = rig.sink.writes.length;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(rig.room.requests.length, requestsAtExit);
    expect(rig.sink.writes.length, writesAtExit);
    expect(rig.sink.active, isFalse);
  });

  test('stalled open sockets time out and recover both channels', () async {
    final rig = await _MediaRig.create(
      readTimeout: const Duration(milliseconds: 250),
    );
    addTearDown(rig.close);
    await rig.supervisor.start();
    final video = await rig.room.request(MiuCamProtocolV2.video);
    final audio = await rig.room.request(MiuCamProtocolV2.audio);
    await video.video(_jpeg, sequence: 1);
    await audio.audio(_pcmFrames(6));
    await _until(() => rig.sink.writes.isNotEmpty);
    // The server leaves both responses open, then sends no further bytes.
    final nextVideo = await rig.room.request(MiuCamProtocolV2.video, at: 1);
    final nextAudio = await rig.room.request(MiuCamProtocolV2.audio, at: 1);
    final oldWrites = rig.sink.writes.length;
    await nextVideo.video(_jpeg, sequence: 2);
    await nextAudio.audio(_pcmFrames(6, startSample: 12000));
    await _until(
        () => rig.sink.writes.length > oldWrites && rig.frames.length == 2);

    for (final channel in ['video', 'audio']) {
      expect(
        rig.updates.any((event) =>
            event.event == '${channel}_reconnecting' &&
            event.failure?.kind == ClientMediaStreamFailureKind.timeout),
        isTrue,
      );
    }
    expect(rig.sink.writes[oldWrites], _pcmFrames(1, startSample: 12000));
    expect(rig.sink.maximumActiveOwners, 1);
  });

  for (final status in [HttpStatus.unauthorized, HttpStatus.forbidden]) {
    test('audio HTTP $status ends both channels and requests one refresh',
        () async {
      final rig = await _MediaRig.create();
      addTearDown(rig.close);
      await rig.supervisor.start();
      final video = await rig.room.request(MiuCamProtocolV2.video);
      final audio = await rig.room.request(MiuCamProtocolV2.audio);
      await video.video(_jpeg, sequence: 1);
      // Deliberately unfinished response: rejecting authorization must not
      // wait for the server to finish an error document.
      audio.request.response
        ..statusCode = status
        ..bufferOutput = false
        ..write('Access revoked');
      await audio.request.response.flush();
      await _until(() => rig.refreshes.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(rig.refreshes, hasLength(1));
      expect(rig.refreshes.single.statusCode, status);
      expect(rig.room.count(MiuCamProtocolV2.video), 1);
      expect(rig.room.count(MiuCamProtocolV2.audio), 1);
      expect(rig.sink.writes, isEmpty);
      expect(rig.health.snapshot().watchActive, isFalse);
    });
  }

  test('role exit cancels both requests waiting for response headers',
      () async {
    final rig = await _MediaRig.create();
    addTearDown(rig.close);
    await rig.supervisor.start();
    await rig.room.request(MiuCamProtocolV2.video);
    await rig.room.request(MiuCamProtocolV2.audio);
    // No headers are sent. Shutdown must not wait for the connect timeout.
    await rig.supervisor.terminate().timeout(const Duration(milliseconds: 500));
    await rig.supervisor.start();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(rig.room.requests, hasLength(2));
    expect(rig.sink.formats, isEmpty);
    expect(rig.sink.writes, isEmpty);
    expect(rig.frames, isEmpty);
    expect(rig.updates.where((event) => event.event.endsWith('_reconnecting')),
        isEmpty);
    expect(rig.health.snapshot().watchActive, isFalse);
  });
}

class _MediaRig {
  _MediaRig(this.room, {required Duration readTimeout}) {
    supervisor = ClientMediaStreamSupervisor(
      session: PairingSession(
        payload: PairingPayload(
          schemaVersion: MiuCamProtocolV2.schemaVersion,
          host: InternetAddress.loopbackIPv4.address,
          port: room.server.port,
          deviceId: 'synthetic-room',
          deviceName: 'Test room',
          pairingNonce: 'nonce',
          expiresAtMs: DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          capabilities: const {'transport': 'http_ws'},
        ),
        sessionToken: 'trusted-parent',
        clientId: 'parent',
      ),
      activeStream: const ActiveStreamSession(streamToken: 'watch-1'),
      audioEnabled: true,
      audioOutput: sink,
      healthState: health,
      connectTimeout: const Duration(seconds: 2),
      readTimeout: readTimeout,
      retryDelay: const Duration(milliseconds: 30),
      maxRetryDelay: const Duration(milliseconds: 60),
      onVideoFrame: (bytes) => frames.add(Uint8List.fromList(bytes)),
      onStatus: updates.add,
      onSessionRefreshRequired: (failure) async => refreshes.add(failure),
    );
  }

  static Future<_MediaRig> create({
    Duration readTimeout = const Duration(seconds: 2),
  }) async =>
      _MediaRig(await _MockRoom.create(), readTimeout: readTimeout);

  final _MockRoom room;
  final sink = _RecordingSpeaker();
  final health = ClientStreamHealthState();
  final frames = <Uint8List>[];
  final updates = <ClientMediaStreamUpdate>[];
  final refreshes = <ClientMediaStreamFailure>[];
  late final ClientMediaStreamSupervisor supervisor;

  Future<void> close() async {
    try {
      await supervisor.terminate();
    } finally {
      await room.server.close(force: true);
    }
  }
}

class _MockRoom {
  _MockRoom(this.server) {
    server.listen((request) => requests.add(_MediaResponse(request)));
  }

  static Future<_MockRoom> create() async =>
      _MockRoom(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer server;
  final requests = <_MediaResponse>[];

  int count(String path) =>
      requests.where((value) => value.request.uri.path == path).length;

  Future<_MediaResponse> request(String path, {int at = 0}) async {
    await _until(() => count(path) > at);
    return requests
        .where((value) => value.request.uri.path == path)
        .elementAt(at);
  }
}

class _MediaResponse {
  _MediaResponse(this.request) {
    request.response.bufferOutput = false;
  }

  final HttpRequest request;
  bool _started = false;

  Future<void> video(Uint8List jpeg,
      {required int sequence, bool fragmented = false}) {
    if (!_started) {
      request.response.headers.set(HttpHeaders.contentTypeHeader,
          'multipart/x-mixed-replace; boundary=frame');
      _started = true;
    }
    return _send([
      ...utf8.encode('--frame\r\nContent-Type: image/jpeg\r\n'
          'Content-Length: ${jpeg.length}\r\n'
          'X-MiuCam-Sequence: $sequence\r\n\r\n'),
      ...jpeg,
      ...utf8.encode('\r\n'),
    ], fragmented: fragmented);
  }

  Future<void> audio(Uint8List pcm, {bool fragmented = false}) async {
    if (!_started) {
      request.response.headers.contentType = ContentType('audio', 'wav');
      _started = true;
      await _send(
          WavPcm16.header(sampleRate: 16000, channels: 1, bitsPerSample: 16),
          fragmented: fragmented);
    }
    await _send(pcm, fragmented: fragmented);
  }

  Future<void> _send(List<int> bytes, {required bool fragmented}) async {
    if (!fragmented) {
      request.response.add(bytes);
      await request.response.flush();
      return;
    }
    // Odd boundaries split RIFF fields, 16-bit samples and 20 ms frames.
    const sizes = [1, 7, 3, 211, 639, 17, 1021];
    for (int offset = 0, index = 0; offset < bytes.length; index++) {
      final end = (offset + sizes[index % sizes.length]).clamp(0, bytes.length);
      request.response.add(bytes.sublist(offset, end));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      offset = end;
    }
  }

  Future<void> close() => request.response.close();
}

class _RecordingSpeaker implements PcmAudioSink {
  final formats = <({int sampleRate, int channels})>[];
  final writes = <Uint8List>[];
  int _activeOwners = 0;
  int maximumActiveOwners = 0;
  bool get active => _activeOwners > 0;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    formats.add((sampleRate: sampleRate, channels: channels));
    _activeOwners++;
    if (_activeOwners > maximumActiveOwners) {
      maximumActiveOwners = _activeOwners;
    }
  }

  @override
  Future<bool> write(Uint8List pcm16le) async {
    expect(active, isTrue, reason: 'PCM must have a live playback owner.');
    writes.add(Uint8List.fromList(pcm16le));
    return true;
  }

  @override
  Future<Map<String, Object?>> status() async => const {};

  @override
  Future<void> stop() async => _activeOwners = 0;
}

Uint8List _pcmFrames(int count, {int startSample = 0}) {
  final bytes = Uint8List(count * 640);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < bytes.length ~/ 2; index++) {
    data.setInt16(index * 2, startSample + index, Endian.little);
  }
  return bytes;
}

Future<void> _until(bool Function() condition) async {
  final deadline = Stopwatch()..start();
  while (!condition()) {
    if (deadline.elapsed > const Duration(seconds: 3)) {
      fail('Local media acceptance condition did not settle within 3 seconds.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

// A generated one-pixel JPEG; no camera or recorded user data is used.
final _jpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////'
  '2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/'
  '8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/'
  '9oACAEBAAEFAqf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/ASP/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/ASP/'
  'xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/Ap//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/IV//2gAMAwEAAgADAAAAEP/'
  'EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8QH//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8QH//EABQQAQAAAAAAAAAAAA'
  'AAAAAAABD/2gAIAQEAAT8QH//Z',
);
