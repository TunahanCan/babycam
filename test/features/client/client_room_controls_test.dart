import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/controls/client_room_controls.dart';
import 'package:mimicam/features/server/media/microphone_capture_service.dart';
import 'package:record/record.dart';

void main() {
  test('comfort command and microphone PCM reach the room control endpoints',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final receivedTalk = BytesBuilder(copy: false);
    unawaited(server.forEach((request) async {
      if (request.uri.path == MimiCamProtocolV2.comfortCommand) {
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
      if (request.uri.path == MimiCamProtocolV2.talkStart) {
        await utf8.decoder.bind(request).join();
        await _json(request.response, {
          'ok': true,
          'session': {'talkToken': 'talk-token'},
        });
        return;
      }
      if (request.uri.path == MimiCamProtocolV2.talkAudio) {
        await for (final chunk in request) {
          receivedTalk.add(chunk);
        }
        await _json(request.response, {'ok': true});
        return;
      }
      if (request.uri.path == MimiCamProtocolV2.talkStop) {
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
    expect(controls.currentState.talking, isFalse);
    expect(controls.currentState.talkBytesSent, 4);
  });
}

PairingSession _session(int port) => PairingSession(
      payload: PairingPayload(
        schemaVersion: MimiCamProtocolV2.schemaVersion,
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

class _FakeRecorder implements MicrophoneRecorderPort {
  final _stream = StreamController<Uint8List>();

  void add(Uint8List bytes) => _stream.add(bytes);

  @override
  Future<void> dispose() => _stream.close();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async =>
      _stream.stream;

  @override
  Future<void> stop() async {}
}
