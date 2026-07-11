import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/media/media_runtime_controller.dart';
import 'package:mimicam/features/server/media/webrtc/webrtc_server_gateway.dart';
import 'package:mimicam/features/server/server_runtime.dart';
import 'package:mimicam/services/monetization/broadcast_access_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('iOS background keeps audio active and restores video in foreground',
      () async {
    final calls = <String>[];
    final media = MediaRuntimeController(
      onStartVideo: () async => calls.add('video:start'),
      onStopVideo: () async => calls.add('video:stop'),
      onStartAudio: () async => calls.add('audio:start'),
      onStopAudio: () async => calls.add('audio:stop'),
    );
    final runtime = ServerRuntime(mediaRuntime: media);
    addTearDown(runtime.dispose);

    await runtime.startStreamSession(
      'parent',
      const StreamSessionOptions(video: true, audio: true),
    );
    expect(media.activeDemand, MediaResourceDemand.all);

    await runtime.pauseMediaForPlatform('ios_application_backgrounded');

    expect(media.videoActive, isFalse);
    expect(media.audioActive, isTrue);
    expect(runtime.currentState.cameraActive, isFalse);
    expect(runtime.currentState.microphoneActive, isTrue);
    expect(calls, ['video:start', 'audio:start', 'video:stop']);

    await runtime.recoverMediaForPlatform('application_foregrounded');

    expect(media.activeDemand, MediaResourceDemand.all);
    expect(runtime.currentState.cameraActive, isTrue);
    expect(runtime.currentState.microphoneActive, isTrue);
    expect(calls, [
      'video:start',
      'audio:start',
      'video:stop',
      'video:start',
    ]);
  });

  test('iOS background rejects a new video WebRTC capture for LAN fallback',
      () async {
    final runtime = ServerRuntime(mediaRuntime: MediaRuntimeController());
    addTearDown(runtime.dispose);
    await runtime.pauseMediaForPlatform('ios_application_backgrounded');
    await runtime.startStreamSession(
      'webrtc-parent',
      const StreamSessionOptions(
        video: true,
        audio: true,
        transport: ServerStreamTransport.webRtc,
      ),
    );

    await expectLater(
      runtime.activateExternalCapture('webrtc-parent'),
      throwsA(isA<WebRtcPilotCapacityException>()),
    );
  });

  test('Server startPairingMode sadece pairing açar, medya oturumla başlar',
      () async {
    var startCount = 0;
    var stopCount = 0;
    final media = MediaRuntimeController(
        onStart: () async => startCount++, onStop: () async => stopCount++);
    final runtime = ServerRuntime(
        mediaRuntime: media,
        onStartPairing: () async => 'mimicam://pair?payload=x');

    await runtime.startPairingMode();
    expect(media.isActive, isFalse);
    expect(startCount, 0);
    expect(runtime.currentState.cameraActive, isFalse);
    expect(runtime.currentState.microphoneActive, isFalse);

    await runtime.markClientPaired();
    expect(media.isActive, isFalse);

    await runtime.startMediaRuntimeForSession('s1');
    expect(media.isActive, isTrue);
    expect(startCount, 1);

    await runtime.endSession('s1');
    expect(media.isActive, isFalse);
    expect(stopCount, 1);

    await runtime.stop();
    expect(media.isActive, isFalse);
    expect(stopCount, 1);
  });

  test('geç pairing sonucu yeniden açılan kamera stateini ezmez', () async {
    final pairingEntered = Completer<void>();
    final pairingResult = Completer<String>();
    var videoStarts = 0;
    var videoStops = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStartVideo: () async => videoStarts++,
        onStopVideo: () async => videoStops++,
      ),
      onStartPairing: () async {
        pairingEntered.complete();
        return pairingResult.future;
      },
    );
    addTearDown(runtime.dispose);

    await runtime.startLocalPreview();
    await runtime.stopLocalPreview();

    final pairing = runtime.startPairingMode();
    await pairingEntered.future;
    await runtime.startLocalPreview();

    expect(runtime.currentState.phase, ServerRuntimePhase.mediaActive);
    expect(runtime.currentState.cameraActive, isTrue);

    pairingResult.complete('mimicam://pair?payload=reopened');
    await pairing;

    expect(videoStarts, 2);
    expect(videoStops, 1);
    expect(runtime.currentState.phase, ServerRuntimePhase.mediaActive);
    expect(runtime.currentState.cameraActive, isTrue);
    expect(
      runtime.currentState.qrPayload,
      'mimicam://pair?payload=reopened',
    );
  });

  test('Server stop idempotent şekilde kaynakları dispose eder', () async {
    final media = MediaRuntimeController();
    final runtime = ServerRuntime(mediaRuntime: media);
    await runtime.stop();
    await runtime.stop();
    expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
  });

  test('server drain callback can finish a session while runtime stops',
      () async {
    late final ServerRuntime runtime;
    runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStop: () => runtime.endSession('draining-client'),
    );
    await runtime.startStreamSession(
      'draining-client',
      const StreamSessionOptions(),
    );

    await runtime.stop().timeout(const Duration(seconds: 1));

    expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
    expect(runtime.currentState.activeClients, 0);
  });

  test('Media stop devam eden start bittikten sonra kaynakları kapatır',
      () async {
    final startCompleter = Completer<void>();
    var startCount = 0;
    var stopCount = 0;
    final media = MediaRuntimeController(
      onStart: () async {
        startCount++;
        await startCompleter.future;
      },
      onStop: () async => stopCount++,
    );

    final start = media.start();
    final stop = media.stop();
    expect(stopCount, 0);

    startCompleter.complete();
    await start;
    await stop;

    expect(startCount, 1);
    expect(stopCount, 1);
    expect(media.isActive, isFalse);
  });

  test('Media start eşzamanlı çağrılarda tek kez çalışır', () async {
    final startCompleter = Completer<void>();
    var startCount = 0;
    final media = MediaRuntimeController(
      onStart: () async {
        startCount++;
        await startCompleter.future;
      },
    );

    final first = media.start();
    final second = media.start();

    startCompleter.complete();
    await Future.wait([first, second]);

    expect(startCount, 1);
    expect(media.isActive, isTrue);
  });

  test('Media start hata alırsa aktif kalmaz ve stop çağırmaz', () async {
    var stopCount = 0;
    final media = MediaRuntimeController(
      onStart: () async => throw StateError('camera unavailable'),
      onStop: () async => stopCount++,
    );

    await expectLater(media.start(), throwsStateError);
    await media.stop();

    expect(media.isActive, isFalse);
    expect(stopCount, 0);
  });

  test('Server local preview media hatasını state içine yazar', () async {
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStart: () async => throw StateError('camera unavailable'),
      ),
    );

    await expectLater(runtime.startLocalPreview(), throwsStateError);

    expect(runtime.currentState.phase, ServerRuntimePhase.error);
    expect(runtime.currentState.cameraActive, isFalse);
    expect(runtime.currentState.activeClients, 0);
    expect(runtime.currentState.errorMessage, contains('camera unavailable'));
  });

  test('remote session kapaninca aktif local preview mediaActive kalir',
      () async {
    final media = MediaRuntimeController();
    final runtime = ServerRuntime(mediaRuntime: media);

    await runtime.startLocalPreview();
    await runtime.startStreamSession(
      'client-1',
      const StreamSessionOptions(video: true),
    );
    await runtime.endSession('client-1');

    expect(media.isActive, isTrue);
    expect(runtime.currentState.phase, ServerRuntimePhase.mediaActive);
    expect(runtime.currentState.cameraActive, isTrue);
    expect(runtime.currentState.microphoneActive, isFalse);
  });

  test('local preview kamera açar ancak mikrofon demand üretmez', () async {
    var videoStarts = 0;
    var audioStarts = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStartVideo: () async => videoStarts++,
        onStopVideo: () async {},
        onStartAudio: () async => audioStarts++,
        onStopAudio: () async {},
      ),
    );

    await runtime.startLocalPreview();

    expect(videoStarts, 1);
    expect(audioStarts, 0);
    expect(runtime.currentState.cameraActive, isTrue);
    expect(runtime.currentState.microphoneActive, isFalse);
  });

  test('native demand is published before hardware acquisition', () async {
    final events = <String>[];
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStartVideo: () async => events.add('camera-start'),
        onStopVideo: () async {},
        onStartAudio: () async {},
        onStopAudio: () async {},
      ),
      onMediaDemandChanged: (demand) async {
        events.add('demand:${demand.video}:${demand.audio}');
      },
    );

    await runtime.startLocalPreview();

    expect(events.take(2), ['demand:true:false', 'camera-start']);
  });

  test('WebRTC capture offer kabulünde atomik devralır ve demandi korur',
      () async {
    var videoStarts = 0;
    var videoStops = 0;
    final nativeDemands = <MediaResourceDemand>[];
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStartVideo: () async => videoStarts++,
        onStopVideo: () async => videoStops++,
        onStartAudio: () async {},
        onStopAudio: () async {},
      ),
      onMediaDemandChanged: (demand) async => nativeDemands.add(demand),
    );

    await runtime.startStreamSession(
      'client-webrtc',
      const StreamSessionOptions(
        video: true,
        audio: true,
        transport: ServerStreamTransport.webRtc,
      ),
    );

    expect(videoStarts, 1);
    expect(videoStops, 0);

    await runtime.activateExternalCapture('client-webrtc');

    expect(videoStops, 1);
    expect(runtime.currentState.cameraActive, isTrue);
    expect(runtime.currentState.microphoneActive, isTrue);
    expect(nativeDemands.last.video, isTrue);
    expect(nativeDemands.last.audio, isTrue);
    expect(nativeDemands.last.serviceVideoCapture, isFalse);
    expect(nativeDemands.last.serviceAudioCapture, isFalse);

    await runtime.endSession('client-webrtc');

    expect(videoStarts, 1);
    expect(runtime.currentState.cameraActive, isFalse);
    expect(runtime.currentState.microphoneActive, isFalse);
    expect(nativeDemands.last, MediaResourceDemand.none);
  });

  test('WebRTC offer legacy preview talebi varken fallback için reddedilir',
      () async {
    final runtime = ServerRuntime(mediaRuntime: MediaRuntimeController());
    await runtime.startLocalPreview();
    await runtime.startStreamSession(
      'client-webrtc',
      const StreamSessionOptions(
        video: true,
        transport: ServerStreamTransport.webRtc,
      ),
    );

    await expectLater(
      runtime.activateExternalCapture('client-webrtc'),
      throwsA(isA<WebRtcPilotCapacityException>()),
    );
    expect(runtime.currentState.cameraActive, isTrue);
    expect(runtime.currentState.activeClients, 1);
  });

  test('notification demand releases WebRTC tracks before analyzer capture',
      () async {
    final events = <String>[];
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStartVideo: () async => events.add('video-start'),
        onStopVideo: () async => events.add('video-stop'),
        onStartAudio: () async => events.add('audio-start'),
        onStopAudio: () async => events.add('audio-stop'),
      ),
      onPauseExternalMedia: (reason) async => events.add('pause:$reason'),
    );
    await runtime.startStreamSession(
      'client-webrtc',
      const StreamSessionOptions(
        video: true,
        transport: ServerStreamTransport.webRtc,
      ),
    );
    await runtime.activateExternalCapture('client-webrtc');

    await runtime.enableNotificationsForClient(
      'client-alerts',
      cry: false,
      motion: true,
    );

    expect(events.where((event) => event == 'video-start'), hasLength(2));
    expect(
      events.indexOf('pause:notificationDemand'),
      lessThan(events.lastIndexOf('video-start')),
    );
    await runtime.dispose();
  });

  test('local preview ayrılınca trial ve kamera demandi kapanır', () async {
    final media = MediaRuntimeController();
    final runtime = ServerRuntime(mediaRuntime: media);
    await runtime.startLocalPreview();

    expect(runtime.currentState.localPreviewActive, isTrue);

    await runtime.stopLocalPreview();

    expect(media.isActive, isFalse);
    expect(runtime.currentState.cameraActive, isFalse);
    expect(runtime.currentState.localPreviewActive, isFalse);
    expect(runtime.currentState.phase, ServerRuntimePhase.mediaIdle);
  });

  test('external WebRTC capture aktifken yerel önizleme güvenle reddedilir',
      () async {
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
    );
    addTearDown(runtime.dispose);
    await runtime.startStreamSession(
      'webrtc-parent',
      const StreamSessionOptions(
        video: true,
        audio: false,
        transport: ServerStreamTransport.webRtc,
      ),
    );
    await runtime.activateExternalCapture('webrtc-parent');

    expect(runtime.currentState.externalCaptureActive, isTrue);
    expect(runtime.currentState.localPreviewActive, isFalse);
    await expectLater(
      runtime.startLocalPreview(),
      throwsA(isA<WebRtcPilotCapacityException>()),
    );
    expect(runtime.currentState.externalCaptureActive, isTrue);
    expect(runtime.currentState.localPreviewActive, isFalse);
  });

  test('inactive authoritative access snapshot stale timeri durdurur',
      () async {
    final access = await _fakeBroadcastAccess(
      beginSnapshot: _accessSnapshot(active: true, remainingMs: 15),
      currentSnapshot: _accessSnapshot(active: false, remainingMs: 15),
    );
    final media = MediaRuntimeController();
    final runtime = ServerRuntime(
      mediaRuntime: media,
      broadcastAccess: access,
    );
    addTearDown(runtime.dispose);

    await runtime.startLocalPreview();
    await Future<void>.delayed(const Duration(milliseconds: 45));

    expect(access.snapshotCalls, 1);
    expect(media.isActive, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(access.snapshotCalls, 1, reason: 'inactive timer yeniden kurulmaz');
  });

  test('unlock devam ederken eski expiry generation medya kapatmaz', () async {
    final unlockCompleter = Completer<BroadcastAccessSnapshot>();
    final access = await _fakeBroadcastAccess(
      beginSnapshot: _accessSnapshot(active: true, remainingMs: 15),
      currentSnapshot: _accessSnapshot(active: true, remainingMs: 0),
      unlockOperation: () => unlockCompleter.future,
    );
    final media = MediaRuntimeController();
    final runtime = ServerRuntime(
      mediaRuntime: media,
      broadcastAccess: access,
    );
    addTearDown(runtime.dispose);

    await runtime.startLocalPreview();
    final unlock = runtime.unlockBroadcastAccess();
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(access.snapshotCalls, 0);
    expect(media.isActive, isTrue);

    unlockCompleter.complete(
      _accessSnapshot(unlocked: true, active: true, remainingMs: 1000),
    );
    await unlock;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(media.isActive, isTrue);
  });

  test('failed unlock authoritative active snapshot ile timeri yeniden kurar',
      () async {
    final access = await _fakeBroadcastAccess(
      beginSnapshot: _accessSnapshot(active: true, remainingMs: 1000),
      currentSnapshot: _accessSnapshot(active: true, remainingMs: 12),
      snapshotSequence: [
        _accessSnapshot(active: true, remainingMs: 12),
        _accessSnapshot(active: true, remainingMs: 0),
      ],
      unlockOperation: () async => throw StateError('store unavailable'),
      endAllSnapshot: _accessSnapshot(active: false, remainingMs: 0),
    );
    final media = MediaRuntimeController();
    final runtime = ServerRuntime(
      mediaRuntime: media,
      broadcastAccess: access,
    );
    addTearDown(runtime.dispose);

    await runtime.startLocalPreview();
    await expectLater(runtime.unlockBroadcastAccess(), throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 45));

    expect(access.snapshotCalls, 2);
    expect(access.endAllCalls, 1);
    expect(media.isActive, isFalse);
    expect(
        runtime.currentState.errorMessage, contains('BROADCAST_ACCESS_LOCKED'));
  });

  test('stopLocalPreview inactive access snapshot ile timeri iptal eder',
      () async {
    final access = await _fakeBroadcastAccess(
      beginSnapshot: _accessSnapshot(active: true, remainingMs: 15),
      currentSnapshot: _accessSnapshot(active: true, remainingMs: 15),
      endSessionSnapshot: _accessSnapshot(active: false, remainingMs: 15),
    );
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      broadcastAccess: access,
    );
    addTearDown(runtime.dispose);

    await runtime.startLocalPreview();
    await runtime.stopLocalPreview();
    await Future<void>.delayed(const Duration(milliseconds: 45));

    expect(access.snapshotCalls, 0);
    expect(runtime.currentState.cameraActive, isFalse);
  });

  test('queued preview stop wins over an in-flight preview start', () async {
    final beginCompleter = Completer<BroadcastAccessSnapshot>();
    final beginEntered = Completer<void>();
    final access = await _fakeBroadcastAccess(
      beginSnapshot: _accessSnapshot(active: true, remainingMs: 1000),
      currentSnapshot: _accessSnapshot(active: true, remainingMs: 1000),
      endSessionSnapshot: _accessSnapshot(active: false, remainingMs: 1000),
      beginOperation: () {
        beginEntered.complete();
        return beginCompleter.future;
      },
    );
    final media = MediaRuntimeController();
    final runtime = ServerRuntime(
      mediaRuntime: media,
      broadcastAccess: access,
    );
    addTearDown(runtime.dispose);

    final start = runtime.startLocalPreview();
    await beginEntered.future;
    final stop = runtime.stopLocalPreview();
    beginCompleter.complete(
      _accessSnapshot(active: true, remainingMs: 1000),
    );
    await Future.wait([start, stop]);

    expect(media.isActive, isFalse);
    expect(runtime.currentState.cameraActive, isFalse);
    expect(runtime.currentState.phase, ServerRuntimePhase.mediaIdle);
  });

  test('stream session media hatasında aktif client rollback yapar', () async {
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(
        onStart: () async => throw StateError('camera unavailable'),
      ),
    );

    await expectLater(
      runtime.startStreamSession('client-1', const StreamSessionOptions()),
      throwsStateError,
    );

    expect(runtime.currentState.phase, ServerRuntimePhase.error);
    expect(runtime.currentState.activeClients, 0);
    expect(runtime.currentState.activeVideoClients, 0);
    expect(runtime.currentState.errorMessage, contains('camera unavailable'));
  });

  test('Server dispose pairing start yarışından sonra medyayı başlatmaz',
      () async {
    final pairingStarted = Completer<void>();
    final pairingResult = Completer<String>();
    var mediaStartCount = 0;
    var serverStopCount = 0;
    final media = MediaRuntimeController(
      onStart: () async => mediaStartCount++,
    );
    final runtime = ServerRuntime(
      mediaRuntime: media,
      onStartPairing: () async {
        pairingStarted.complete();
        return pairingResult.future;
      },
      onStop: () async => serverStopCount++,
    );

    final start = runtime.startPairingMode();
    await pairingStarted.future;
    final dispose = runtime.dispose();

    pairingResult.complete('mimicam://pair?payload=x');
    await start;
    await dispose;

    expect(mediaStartCount, 0);
    expect(media.isActive, isFalse);
    expect(serverStopCount, 1);
    expect(runtime.currentState.phase, ServerRuntimePhase.stopped);
  });
}

Future<_FakeBroadcastAccessService> _fakeBroadcastAccess({
  required BroadcastAccessSnapshot beginSnapshot,
  required BroadcastAccessSnapshot currentSnapshot,
  BroadcastAccessSnapshot? endSessionSnapshot,
  BroadcastAccessSnapshot? endAllSnapshot,
  List<BroadcastAccessSnapshot> snapshotSequence = const [],
  Future<BroadcastAccessSnapshot> Function()? unlockOperation,
  Future<BroadcastAccessSnapshot> Function()? beginOperation,
}) async {
  SharedPreferences.setMockInitialValues({});
  return _FakeBroadcastAccessService(
    await SharedPreferences.getInstance(),
    beginSnapshot: beginSnapshot,
    currentSnapshot: currentSnapshot,
    endSessionSnapshot: endSessionSnapshot,
    endAllSnapshot: endAllSnapshot,
    snapshotSequence: snapshotSequence,
    unlockOperation: unlockOperation,
    beginOperation: beginOperation,
  );
}

BroadcastAccessSnapshot _accessSnapshot({
  bool unlocked = false,
  required bool active,
  required int remainingMs,
}) =>
    BroadcastAccessSnapshot(
      unlocked: unlocked,
      active: active,
      freeLimitMs: 1000,
      usedMs: 1000 - remainingMs.clamp(0, 1000).toInt(),
      remainingMs: remainingMs,
      priceLabel: 'test',
      productId: BroadcastAccessConfig.productId,
    );

class _FakeBroadcastAccessService extends BroadcastAccessService {
  _FakeBroadcastAccessService(
    super.preferences, {
    required this.beginSnapshot,
    required this.currentSnapshot,
    this.endSessionSnapshot,
    this.endAllSnapshot,
    List<BroadcastAccessSnapshot> snapshotSequence = const [],
    this.unlockOperation,
    this.beginOperation,
  })  : _snapshotSequence = List.of(snapshotSequence),
        super(purchaseGateway: _NoopPurchaseGateway());

  final BroadcastAccessSnapshot beginSnapshot;
  BroadcastAccessSnapshot currentSnapshot;
  final BroadcastAccessSnapshot? endSessionSnapshot;
  final BroadcastAccessSnapshot? endAllSnapshot;
  final Future<BroadcastAccessSnapshot> Function()? unlockOperation;
  final Future<BroadcastAccessSnapshot> Function()? beginOperation;
  final List<BroadcastAccessSnapshot> _snapshotSequence;
  int snapshotCalls = 0;
  int endAllCalls = 0;

  @override
  Future<BroadcastAccessSnapshot> beginSession(String sessionId) async {
    final operation = beginOperation;
    return operation == null ? beginSnapshot : operation();
  }

  @override
  Future<BroadcastAccessSnapshot> snapshot() async {
    snapshotCalls++;
    if (_snapshotSequence.isNotEmpty) {
      currentSnapshot = _snapshotSequence.removeAt(0);
    }
    return currentSnapshot;
  }

  @override
  Future<BroadcastAccessSnapshot> endSession(String sessionId) async {
    currentSnapshot = endSessionSnapshot ??
        currentSnapshot.copyWith(active: false, remainingMs: remainingMs);
    return currentSnapshot;
  }

  int get remainingMs => currentSnapshot.remainingMs;

  @override
  Future<BroadcastAccessSnapshot> endAllSessions() async {
    endAllCalls++;
    currentSnapshot = endAllSnapshot ??
        currentSnapshot.copyWith(active: false, remainingMs: remainingMs);
    return currentSnapshot;
  }

  @override
  Future<BroadcastAccessSnapshot> unlockWithOneTimePurchase() async {
    final operation = unlockOperation;
    if (operation != null) return operation();
    currentSnapshot = currentSnapshot.copyWith(unlocked: true);
    return currentSnapshot;
  }

  @override
  Future<BroadcastAccessSnapshot> restorePurchase() =>
      unlockWithOneTimePurchase();
}

class _NoopPurchaseGateway implements BroadcastPurchaseGateway {
  @override
  Future<void> dispose() async {}

  @override
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  }) async =>
      const BroadcastPurchaseResult(status: BroadcastPurchaseStatus.canceled);

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async =>
      const BroadcastPurchaseResult(status: BroadcastPurchaseStatus.canceled);
}
