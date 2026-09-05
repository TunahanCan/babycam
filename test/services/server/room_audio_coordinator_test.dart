import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/platform/pcm_audio_output.dart';
import 'package:miucam/services/server/baby_monitor_feature_controller.dart';
import 'package:miucam/services/server/baby_monitor_feature_services.dart';
import 'package:miucam/services/server/room_audio_coordinator.dart';

void main() {
  for (final failure in ['error', 'timeout', 'rejection']) {
    test('comfort $failure clears output mode and advertised playback state',
        () async {
      final pending = Completer<bool>();
      final sink = _ControlledWriteSink()
        ..writeBehavior = () {
          if (failure == 'error') throw StateError('native output lost');
          return failure == 'timeout' ? pending.future : Future.value(false);
        };
      final demands = <bool>[];
      final audio = RoomAudioCoordinator(
        sink: sink,
        frameDuration: const Duration(milliseconds: 5),
        nativeOperationTimeout: const Duration(milliseconds: 20),
        onOutputDemandChanged: demands.add,
      );
      final controller = BabyMonitorFeatureController(roomAudio: audio);
      addTearDown(() async {
        if (!pending.isCompleted) pending.complete(false);
        await controller.dispose();
      });
      await controller
          .applyComfortCommand(const {'action': 'play', 'trackId': 'rain'});
      await _waitUntil(() => audio.mode == RoomAudioMode.idle);
      expect(controller.comfortAudio.state.playing, isFalse);
      expect(
          controller.comfortAudio.state.lastError, contains('PLAYBACK_FAILED'));
      expect((await audio.snapshot())['comfortRequested'], isFalse);
      expect(demands.last, isFalse);

      sink.writeBehavior = null;
      final resumed = await controller
          .applyComfortCommand(const {'action': 'play', 'trackId': 'rain'});
      expect(resumed.playing, isTrue);
      expect(audio.mode, RoomAudioMode.comfort);
      await _waitUntil(() => sink.writes.isNotEmpty);
    });
  }

  test('isolated comfort backpressure recovers without stopping playback',
      () async {
    var writes = 0;
    final sink = _ControlledWriteSink()
      ..writeBehavior = () async => ++writes > 2;
    final audio = RoomAudioCoordinator(
      sink: sink,
      frameDuration: const Duration(milliseconds: 5),
    );
    addTearDown(audio.dispose);
    await audio.applyComfort(playing: true, trackId: 'rain', volume: .3);
    await _waitUntil(() => writes >= 5);
    expect(audio.mode, RoomAudioMode.comfort);
  });

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

  test('talk attempt tombstone rejects late start without stopping successor',
      () {
    var now = DateTime.utc(2026, 1, 1);
    final sessions = TalkSessionRegistry(
      now: () => now,
      attemptTombstoneTtl: const Duration(minutes: 1),
      maxAttemptTombstones: 2,
    );

    expect(
      sessions.stop(clientId: 'anne', attemptId: 'attempt-a'),
      isFalse,
    );
    expect(
      () => sessions.start(clientId: 'anne', attemptId: 'attempt-a'),
      throwsA(isA<TalkSessionCancelledException>()),
    );

    final successor = sessions.start(clientId: 'anne', attemptId: 'attempt-b');
    expect(
      sessions.stop(clientId: 'anne', attemptId: 'attempt-a'),
      isFalse,
    );
    expect(sessions.activeSession?.token, successor.token);
    expect(
      sessions.stop(
        clientId: 'anne',
        token: successor.token,
        attemptId: 'attempt-b',
      ),
      isTrue,
    );

    sessions
      ..cancelAttempt('anne', 'attempt-c')
      ..cancelAttempt('anne', 'attempt-d');
    expect(sessions.attemptTombstoneCount, 2);

    now = now.add(const Duration(minutes: 2));
    expect(sessions.attemptTombstoneCount, 0);
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

    expect(events, ['stop', 'demand:true', 'start', 'stop', 'demand:false']);
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

  test('hanging native start is bounded and cannot poison its successor',
      () async {
    final sink = _ControllableLeasePcmAudioSink(hangingStartLeaseId: 1);
    final demands = <bool>[];
    final audio = RoomAudioCoordinator(
      sink: sink,
      nativeOperationTimeout: const Duration(milliseconds: 20),
      onOutputDemandChanged: demands.add,
    );
    addTearDown(() async {
      sink.releaseAll();
      await audio.dispose();
    });

    await expectLater(audio.beginTalk(), throwsA(isA<TimeoutException>()));

    expect(audio.mode, RoomAudioMode.idle);
    expect(sink.activeLeaseId, isNull);
    expect(demands, [true, false]);

    await audio.beginTalk();
    expect(audio.mode, RoomAudioMode.talk);
    expect(sink.activeLeaseId, 2);

    sink.releaseStart();
    await Future<void>.delayed(Duration.zero);

    expect(sink.activeLeaseId, 2);
    expect(await audio.writeTalk(Uint8List.fromList([1, 0])), isTrue);
  });

  test('hanging talk write is bounded and successor accepts audio', () async {
    final sink = _ControllableLeasePcmAudioSink(hangingWriteLeaseId: 1);
    final audio = RoomAudioCoordinator(
      sink: sink,
      nativeOperationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(() async {
      sink.releaseAll();
      await audio.dispose();
    });
    await audio.beginTalk();

    final elapsed = Stopwatch()..start();
    expect(await audio.writeTalk(Uint8List.fromList([1, 0])), isFalse);
    elapsed.stop();

    expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 500)));
    await audio.endTalk();
    await audio.beginTalk();
    expect(sink.activeLeaseId, 2);
    expect(await audio.writeTalk(Uint8List.fromList([2, 0])), isTrue);

    sink.releaseWrite();
    await Future<void>.delayed(Duration.zero);

    expect(sink.activeLeaseId, 2);
  });

  test('late comfort write cannot cross into a talk playback lease', () async {
    final sink = _ControllableLeasePcmAudioSink(hangingWriteLeaseId: 1);
    final audio = RoomAudioCoordinator(
      sink: sink,
      frameDuration: const Duration(milliseconds: 5),
      nativeOperationTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(() async {
      sink.releaseAll();
      await audio.dispose();
    });

    await audio.applyComfort(
      playing: true,
      trackId: 'rain',
      volume: .3,
    );
    await audio.beginTalk();

    expect(sink.activeLeaseId, 2);
    expect(await audio.writeTalk(Uint8List.fromList([3, 0])), isTrue);

    sink.releaseWrite();
    await Future<void>.delayed(Duration.zero);

    expect(audio.mode, RoomAudioMode.talk);
    expect(sink.activeLeaseId, 2);
  });

  test('hanging stop is bounded and its late completion spares successor',
      () async {
    final sink = _ControllableLeasePcmAudioSink(hangingStopLeaseId: 1);
    final audio = RoomAudioCoordinator(
      sink: sink,
      nativeOperationTimeout: const Duration(milliseconds: 20),
    );
    final controller = BabyMonitorFeatureController(
      talkSessions: TalkSessionRegistry(
        sessionTtl: const Duration(seconds: 2),
      ),
      roomAudio: audio,
    );
    addTearDown(() async {
      sink.releaseAll();
      await controller.dispose();
    });

    final first = await controller.startTalk(clientId: 'anne');
    final elapsed = Stopwatch()..start();
    expect(
      await controller.stopTalk(clientId: 'anne', token: first.token),
      isTrue,
    );
    elapsed.stop();

    expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 500)));
    expect(audio.mode, RoomAudioMode.idle);
    final successor = await controller.startTalk(clientId: 'anne');
    expect(successor.token, isNot(first.token));
    expect(sink.activeLeaseId, 2);

    sink.releaseStop();
    await Future<void>.delayed(Duration.zero);

    expect(sink.activeLeaseId, 2);
    expect(audio.mode, RoomAudioMode.talk);
  });

  test('talk expiry survives hanging native stop and permits a successor',
      () async {
    final sink = _ControllableLeasePcmAudioSink(hangingStopLeaseId: 1);
    final audio = RoomAudioCoordinator(
      sink: sink,
      nativeOperationTimeout: const Duration(milliseconds: 20),
    );
    final controller = BabyMonitorFeatureController(
      talkSessions: TalkSessionRegistry(
        sessionTtl: const Duration(milliseconds: 35),
      ),
      roomAudio: audio,
    );
    addTearDown(() async {
      sink.releaseAll();
      await controller.dispose();
    });

    final expired = await controller.startTalk(
      clientId: 'anne',
      attemptId: 'attempt-a',
    );
    await _waitUntil(() => audio.mode == RoomAudioMode.idle);

    expect(controller.isTalkTokenActive(expired.token), isFalse);
    expect(sink.activeLeaseId, isNull);

    final successor = await controller.startTalk(
      clientId: 'anne',
      attemptId: 'attempt-b',
    );
    expect(successor.token, isNot(expired.token));
    expect(sink.activeLeaseId, 2);

    sink.releaseStop();
    await Future<void>.delayed(Duration.zero);

    expect(sink.activeLeaseId, 2);
    expect(controller.isTalkTokenActive(successor.token), isTrue);
  });

  test('hanging playback demand and status callbacks are bounded', () async {
    final sink = _ControllableLeasePcmAudioSink(hangingStatus: true);
    final firstDemand = Completer<void>();
    var hangNextActivation = true;
    final demands = <bool>[];
    final audio = RoomAudioCoordinator(
      sink: sink,
      nativeOperationTimeout: const Duration(milliseconds: 20),
      onOutputDemandChanged: (active) {
        demands.add(active);
        if (active && hangNextActivation) {
          hangNextActivation = false;
          return firstDemand.future;
        }
      },
    );
    addTearDown(() async {
      if (!firstDemand.isCompleted) firstDemand.complete();
      sink.releaseAll();
      await audio.dispose();
    });

    await expectLater(audio.beginTalk(), throwsA(isA<TimeoutException>()));
    expect(audio.mode, RoomAudioMode.idle);
    expect(demands, [true, false]);

    await audio.beginTalk();
    expect(audio.mode, RoomAudioMode.talk);

    final elapsed = Stopwatch()..start();
    final snapshot = await audio.snapshot();
    elapsed.stop();

    expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 500)));
    expect(snapshot['native'], isEmpty);
    expect(snapshot['lastError'], contains('TimeoutException'));

    firstDemand.complete();
    sink.releaseStatus();
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      fail('Condition was not met within $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
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

class _ControlledWriteSink extends _FakePcmAudioSink {
  Future<bool> Function()? writeBehavior;

  @override
  Future<bool> write(Uint8List pcm16le) =>
      writeBehavior?.call() ?? super.write(pcm16le);
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

class _ControllableLeasePcmAudioSink
    implements PcmAudioSink, PcmAudioLeaseSink {
  _ControllableLeasePcmAudioSink({
    this.hangingStartLeaseId,
    this.hangingWriteLeaseId,
    this.hangingStopLeaseId,
    this.hangingStatus = false,
  });

  final int? hangingStartLeaseId;
  final int? hangingWriteLeaseId;
  final int? hangingStopLeaseId;
  final bool hangingStatus;
  final Completer<void> _startRelease = Completer<void>();
  final Completer<void> _writeRelease = Completer<void>();
  final Completer<void> _stopRelease = Completer<void>();
  final Completer<void> _statusRelease = Completer<void>();
  final Set<int> _retiredLeaseIds = <int>{};
  int _nextLeaseId = 0;
  int? activeLeaseId;

  @override
  PcmAudioPlaybackLease createPlaybackLease() =>
      _ControllablePlaybackLease(this, ++_nextLeaseId);

  Future<void> startLease(int leaseId) {
    final gate = leaseId == hangingStartLeaseId
        ? _startRelease.future
        : Future<void>.value();
    return gate.then((_) {
      if (!_retiredLeaseIds.contains(leaseId)) activeLeaseId = leaseId;
    });
  }

  Future<bool> writeLease(int leaseId, Uint8List bytes) {
    if (_retiredLeaseIds.contains(leaseId) || activeLeaseId != leaseId) {
      return Future<bool>.value(false);
    }
    final gate = leaseId == hangingWriteLeaseId
        ? _writeRelease.future
        : Future<void>.value();
    return gate.then(
      (_) => !_retiredLeaseIds.contains(leaseId) && activeLeaseId == leaseId,
    );
  }

  Future<void> stopLease(int leaseId) {
    _retiredLeaseIds.add(leaseId);
    if (activeLeaseId == leaseId) activeLeaseId = null;
    return leaseId == hangingStopLeaseId
        ? _stopRelease.future
        : Future<void>.value();
  }

  @override
  Future<void> resetPlayback() async {
    final active = activeLeaseId;
    if (active != null) _retiredLeaseIds.add(active);
    activeLeaseId = null;
  }

  @override
  Future<Map<String, Object?>> status() async {
    if (hangingStatus) await _statusRelease.future;
    return {'activeLeaseId': activeLeaseId};
  }

  void releaseStart() {
    if (!_startRelease.isCompleted) _startRelease.complete();
  }

  void releaseWrite() {
    if (!_writeRelease.isCompleted) _writeRelease.complete();
  }

  void releaseStop() {
    if (!_stopRelease.isCompleted) _stopRelease.complete();
  }

  void releaseStatus() {
    if (!_statusRelease.isCompleted) _statusRelease.complete();
  }

  void releaseAll() {
    releaseStart();
    releaseWrite();
    releaseStop();
    releaseStatus();
  }

  @override
  Future<void> start({
    required int sampleRate,
    required int channels,
  }) =>
      Future<void>.error(
        UnsupportedError('Use createPlaybackLease in this test sink.'),
      );

  @override
  Future<void> stop() => resetPlayback();

  @override
  Future<bool> write(Uint8List pcm16le) => Future<bool>.value(false);
}

class _ControllablePlaybackLease implements PcmAudioPlaybackLease {
  _ControllablePlaybackLease(this._sink, this._leaseId);

  final _ControllableLeasePcmAudioSink _sink;
  final int _leaseId;
  Future<void>? _startOperation;
  Future<void>? _stopOperation;
  bool _retired = false;

  @override
  Future<void> start({
    required int sampleRate,
    required int channels,
  }) {
    if (_retired) return Future<void>.error(StateError('Lease is retired.'));
    return _startOperation ??= _sink.startLease(_leaseId);
  }

  @override
  Future<void> stop() {
    final current = _stopOperation;
    if (current != null) return current;
    _retired = true;
    return _stopOperation = _sink.stopLease(_leaseId);
  }

  @override
  Future<bool> write(Uint8List pcm16le) {
    if (_retired) return Future<bool>.value(false);
    return _sink.writeLease(_leaseId, pcm16le);
  }
}
