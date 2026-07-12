import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/platform/pcm_audio_output.dart';
import 'package:mimicam/services/server/baby_monitor_feature_controller.dart';
import 'package:mimicam/services/server/baby_monitor_feature_services.dart';
import 'package:mimicam/services/server/room_audio_coordinator.dart';

void main() {
  test('comfort audio generates PCM and resumes after talk', () async {
    final sink = _FakePcmAudioSink();
    final audio = RoomAudioCoordinator(
      sink: sink,
      frameDuration: const Duration(milliseconds: 5),
    );
    final modes = <RoomAudioMode>[];
    final modeSubscription = audio.modeChanges.listen(modes.add);
    addTearDown(modeSubscription.cancel);
    addTearDown(audio.dispose);

    await audio.applyComfort(
      playing: true,
      trackId: 'rain',
      volume: .4,
    );
    await Future<void>.delayed(const Duration(milliseconds: 25));
    final comfortWrites = sink.writes.length;

    await audio.beginTalk();
    final talkPayload = Uint8List.fromList([1, 0, 2, 0]);
    expect(await audio.writeTalk(talkPayload), isTrue);
    await audio.endTalk();
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(comfortWrites, greaterThan(0));
    expect(sink.starts, greaterThanOrEqualTo(3));
    expect(audio.mode, RoomAudioMode.comfort);
    expect(modes, [
      RoomAudioMode.comfort,
      RoomAudioMode.talk,
      RoomAudioMode.idle,
      RoomAudioMode.comfort,
    ]);
    expect(
      sink.writes.any((bytes) =>
          bytes.length == talkPayload.length &&
          List<int>.generate(bytes.length, (index) => index)
              .every((index) => bytes[index] == talkPayload[index])),
      isTrue,
    );
  });

  test('feature facade sends accepted talk PCM to the room sink', () async {
    final sink = _FakePcmAudioSink();
    final controller = BabyMonitorFeatureController(
      talkSessions: TalkSessionRegistry(
        sessionTtl: const Duration(seconds: 2),
      ),
      roomAudio: RoomAudioCoordinator(sink: sink),
    );
    addTearDown(controller.dispose);

    final session = await controller.startTalk(clientId: 'anne');
    final result = await controller.acceptTalkAudio(
      session.token,
      Uint8List.fromList([8, 0, 9, 0]),
    );

    expect(result.played, isTrue);
    expect(result.session?.audioBytesReceived, 4);
    expect(sink.writes.single, Uint8List.fromList([8, 0, 9, 0]));
    expect(
      await controller.stopTalk(clientId: 'anne', token: session.token),
      isTrue,
    );
  });

  test('comfort generator returns bounded little-endian PCM frames', () {
    final generator = ComfortPcmGenerator(sampleRate: 16000);

    final frame = generator.nextFrame(
      trackId: 'soft_lullaby',
      volume: .5,
      duration: const Duration(milliseconds: 20),
    );

    expect(frame, hasLength(640));
    expect(frame.any((value) => value != 0), isTrue);
  });

  test('comfort generator supports the soft shushing track', () {
    final generator = ComfortPcmGenerator(sampleRate: 16000);

    final frame = generator.nextFrame(
      trackId: 'shushing',
      volume: .5,
      duration: const Duration(milliseconds: 100),
    );

    expect(frame, hasLength(3200));
    expect(frame.any((value) => value != 0), isTrue);
  });

  test('comfort catalog exposes the soft shushing track to Client', () {
    final service = ComfortAudioService();

    expect(
      service.trackCatalog.map((track) => track['id']),
      contains('shushing'),
    );
    expect(
      service.applyCommand(
          const {'action': 'play', 'trackId': 'shushing'}).trackId,
      'shushing',
    );
  });

  test('native start failure does not poison later room audio commands',
      () async {
    final sink = _FailFirstStartPcmAudioSink();
    final audio = RoomAudioCoordinator(sink: sink);
    addTearDown(audio.dispose);

    await expectLater(
      audio.beginTalk(),
      throwsA(isA<StateError>()),
    );
    await audio.applyComfort(
      playing: true,
      trackId: 'white_noise',
      volume: .2,
    );

    expect(sink.starts, 2);
    expect(audio.mode, RoomAudioMode.comfort);
  });

  test('publishes playback demand before native output starts and after stop',
      () async {
    final events = <String>[];
    final sink = _OrderingPcmAudioSink(events);
    final audio = RoomAudioCoordinator(
      sink: sink,
      onOutputDemandChanged: (active) async {
        events.add('demand:$active');
      },
    );
    addTearDown(audio.dispose);

    await audio.beginTalk();
    await audio.endTalk();

    expect(events, ['stop', 'demand:true', 'start', 'stop', 'demand:false']);
  });

  test('revokes preflight playback demand when native start fails', () async {
    final events = <String>[];
    final sink = _FailingOrderingPcmAudioSink(events);
    final audio = RoomAudioCoordinator(
      sink: sink,
      onOutputDemandChanged: (active) async {
        events.add('demand:$active');
      },
    );
    addTearDown(audio.dispose);

    await expectLater(audio.beginTalk(), throwsA(isA<StateError>()));

    expect(events, ['stop', 'demand:true', 'start', 'demand:false']);
    expect(audio.mode, RoomAudioMode.idle);
  });

  test('failed talk transition restores real comfort output', () async {
    final sink = _FailSecondStartPcmAudioSink();
    final audio = RoomAudioCoordinator(sink: sink);
    addTearDown(audio.dispose);
    await audio.applyComfort(
      playing: true,
      trackId: 'rain',
      volume: .3,
    );

    await expectLater(audio.beginTalk(), throwsA(isA<StateError>()));

    expect(sink.starts, 3);
    expect(audio.mode, RoomAudioMode.comfort);
    expect((await audio.snapshot())['comfortRequested'], isTrue);
  });

  test('unrecoverable native output loss clears mode and playback demand',
      () async {
    final demands = <bool>[];
    final audio = RoomAudioCoordinator(
      sink: _FakePcmAudioSink(),
      onOutputDemandChanged: demands.add,
    );
    addTearDown(audio.dispose);
    await audio.applyComfort(
      playing: true,
      trackId: 'rain',
      volume: .3,
    );

    await audio.handleOutputLost();

    expect(audio.mode, RoomAudioMode.idle);
    expect((await audio.snapshot())['comfortRequested'], isFalse);
    expect(demands.last, isFalse);
  });
}

class _FakePcmAudioSink implements PcmAudioSink {
  int starts = 0;
  int stops = 0;
  final writes = <Uint8List>[];

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    starts++;
  }

  @override
  Future<Map<String, Object?>> status() async => {
        'started': starts > stops,
        'writes': writes.length,
      };

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<bool> write(Uint8List pcm16le) async {
    writes.add(Uint8List.fromList(pcm16le));
    return true;
  }
}

class _FailFirstStartPcmAudioSink extends _FakePcmAudioSink {
  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    starts++;
    if (starts == 1) throw StateError('native output unavailable');
  }
}

class _FailSecondStartPcmAudioSink extends _FakePcmAudioSink {
  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    starts++;
    if (starts == 2) throw StateError('talk output unavailable');
  }
}

class _OrderingPcmAudioSink extends _FakePcmAudioSink {
  _OrderingPcmAudioSink(this.events);

  final List<String> events;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    events.add('start');
    await super.start(sampleRate: sampleRate, channels: channels);
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    await super.stop();
  }
}

class _FailingOrderingPcmAudioSink extends _OrderingPcmAudioSink {
  _FailingOrderingPcmAudioSink(super.events);

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    events.add('start');
    throw StateError('native output unavailable');
  }
}
