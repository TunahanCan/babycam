import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/features/client/media/client_stream_health_state.dart';

void main() {
  test('initial snapshot safe defaults taşır', () {
    final monitor = ClientStreamHealthState(nowMs: () => 1000);
    final snapshot = monitor.snapshot();

    expect(snapshot.videoFrameGapMs, isNull);
    expect(snapshot.audioGapMs, isNull);
    expect(snapshot.watchActive, isFalse);
    expect(snapshot.healthTier, NetworkQualityTier.unknown);
  });

  test('video frame gap 2 saniyede weak, 5 saniyede critical olur', () {
    var nowMs = 1000;
    final monitor = ClientStreamHealthState(nowMs: () => nowMs)
      ..resetForNewWatchSession();

    monitor.markVideoFrameReceived();
    expect(monitor.snapshot().videoFrameGapMs, 0);

    nowMs += 2000;
    expect(monitor.snapshot().healthTier, NetworkQualityTier.weak);

    nowMs += 3000;
    final critical = monitor.snapshot();
    expect(critical.streamTimedOut, isTrue);
    expect(critical.healthTier, NetworkQualityTier.critical);
  });

  test('frame callback gelince lastVideoFrameAt güncellenir', () {
    var nowMs = 1000;
    final state = ClientStreamHealthState(nowMs: () => nowMs)
      ..resetForNewWatchSession();

    nowMs = 1234;
    state.markVideoFrameReceived();
    final snapshot = state.snapshot();

    expect(snapshot.lastVideoFrameAtMs, 1234);
    expect(snapshot.videoFrameGapMs, 0);
  });

  test('audio gap 1500ms üstünde underrun üretir', () {
    var nowMs = 1000;
    final monitor = ClientStreamHealthState(nowMs: () => nowMs)
      ..resetForNewWatchSession()
      ..markAudioChunkReceived();

    expect(monitor.snapshot().audioGapMs, 0);

    nowMs += 1500;
    final snapshot = monitor.snapshot();
    expect(snapshot.audioUnderrun, isTrue);
    expect(snapshot.healthTier, NetworkQualityTier.critical);
  });

  test('audio callback gelince lastAudioChunkAt güncellenir', () {
    var nowMs = 1000;
    final state = ClientStreamHealthState(nowMs: () => nowMs)
      ..resetForNewWatchSession();

    nowMs = 1450;
    state.markAudioChunkReceived();
    final snapshot = state.snapshot();

    expect(snapshot.lastAudioChunkAtMs, 1450);
    expect(snapshot.audioGapMs, 0);
  });

  test('ws disconnect sayaç artırır', () {
    final state = ClientStreamHealthState(nowMs: () => 1000)
      ..resetForNewWatchSession();

    state.markWsDisconnected();

    expect(state.snapshot().wsDisconnectCount, 1);
  });

  test('ws disconnect ve reconnect sayaçları session reset ile temizlenir', () {
    var nowMs = 1000;
    final monitor = ClientStreamHealthState(nowMs: () => nowMs)
      ..resetForNewWatchSession()
      ..markWsDisconnected()
      ..markReconnectAttempt();

    var snapshot = monitor.snapshot();
    expect(snapshot.wsDisconnectCount, 1);
    expect(snapshot.reconnectCount, 1);
    expect(snapshot.recentlyReconnected, isTrue);
    expect(snapshot.healthTier, NetworkQualityTier.weak);

    nowMs += 11000;
    expect(monitor.snapshot().recentlyReconnected, isFalse);

    monitor.resetForNewWatchSession();
    snapshot = monitor.snapshot();
    expect(snapshot.wsDisconnectCount, 0);
    expect(snapshot.reconnectCount, 0);
  });

  test('video skip ve queue delay yalniz yakin kalite penceresini etkiler', () {
    var nowMs = 1000;
    final state = ClientStreamHealthState(nowMs: () => nowMs)
      ..resetForNewWatchSession()
      ..markVideoFrameReceived()
      ..markVideoFramesSkipped(4)
      ..updateVideoTransport(jitterMs: 20, queueDelayMs: 180);

    var snapshot = state.snapshot();
    expect(snapshot.skippedVideoFrames, 4);
    expect(snapshot.videoQueueDelayMs, 180);
    expect(snapshot.healthTier, NetworkQualityTier.weak);

    nowMs += 9000;
    state
      ..markVideoFrameReceived()
      ..updateVideoTransport(jitterMs: 10, queueDelayMs: 0);
    snapshot = state.snapshot();
    expect(snapshot.skippedVideoFrames, 0);
  });

  test('coalesced video kareleri kalite tierini dusurmez', () {
    final state = ClientStreamHealthState(nowMs: () => 1000)
      ..resetForNewWatchSession()
      ..markVideoFrameReceived()
      ..markVideoFramesCoalesced(5);

    final snapshot = state.snapshot();
    expect(snapshot.coalescedVideoFrames, 5);
    expect(snapshot.skippedVideoFrames, 0);
    expect(snapshot.healthTier, NetworkQualityTier.excellent);
    expect(
      snapshot.toQualityReportJson(
        clientId: 'anne',
        networkTier: NetworkQualityTier.excellent,
      )['coalescedVideoFrames'],
      5,
    );
  });

  test('audio pipeline drop deltalari skipped audio olarak raporlanir', () {
    final state = ClientStreamHealthState(nowMs: () => 1000)
      ..resetForNewWatchSession()
      ..updateAudioPipelineStatus(const {
        'droppedBufferFrames': 2,
        'droppedNativeWrites': 1,
        'playoutUnderruns': 0,
      });

    final snapshot = state.snapshot();
    expect(snapshot.skippedAudioChunks, 3);
    expect(
        snapshot.toQualityReportJson(
          clientId: 'anne',
          networkTier: NetworkQualityTier.excellent,
        )['skippedAudioChunks'],
        3);
  });

  test('eski async audio status drop baselineini geri dusurmez', () {
    final state = ClientStreamHealthState(nowMs: () => 1000)
      ..resetForNewWatchSession()
      ..updateAudioPipelineStatus(const {
        'droppedBufferFrames': 2,
        'droppedNativeWrites': 1,
        'playoutUnderruns': 0,
      });

    expect(state.snapshot().skippedAudioChunks, 3);

    state.updateAudioPipelineStatus(const {
      'droppedBufferFrames': 1,
      'droppedNativeWrites': 0,
      'playoutUnderruns': 0,
    });
    state.updateAudioPipelineStatus(const {
      'droppedBufferFrames': 2,
      'droppedNativeWrites': 1,
      'playoutUnderruns': 0,
    });

    expect(state.snapshot().skippedAudioChunks, 3);

    state.updateAudioPipelineStatus(const {
      'droppedBufferFrames': 3,
      'droppedNativeWrites': 1,
      'playoutUnderruns': 0,
    });
    expect(state.snapshot().skippedAudioChunks, 4);
  });

  test('native drop ve underrun deltalari tekrar sayilmadan izlenir', () {
    final state = ClientStreamHealthState(nowMs: () => 1000)
      ..resetForNewWatchSession()
      ..updateAudioPipelineStatus(const {
        'droppedBufferFrames': 0,
        'droppedNativeWrites': 0,
        'playoutUnderruns': 0,
        'native': {
          'writesDropped': 10,
          'underrunCount': 4,
          'starts': 2,
        },
      });

    expect(state.snapshot().skippedAudioChunks, 0);

    state.updateAudioPipelineStatus(const {
      'droppedBufferFrames': 0,
      'droppedNativeWrites': 1,
      'playoutUnderruns': 1,
      'native': {
        'writesDropped': 11,
        'underrunCount': 5,
        'starts': 2,
      },
    });
    expect(state.snapshot().skippedAudioChunks, 2);

    state.updateAudioPipelineStatus(const {
      'droppedBufferFrames': 0,
      'droppedNativeWrites': 1,
      'playoutUnderruns': 1,
      'native': {
        'writesDropped': 12,
        'underrunCount': 6,
        'starts': 2,
      },
    });
    expect(state.snapshot().skippedAudioChunks, 4);

    state.updateAudioPipelineStatus(const {
      'droppedBufferFrames': 0,
      'droppedNativeWrites': 1,
      'playoutUnderruns': 1,
      'native': {
        'writesDropped': 11,
        'underrunCount': 5,
        'starts': 2,
      },
    });
    expect(state.snapshot().skippedAudioChunks, 4);

    state.updateAudioPipelineStatus(const {
      'droppedBufferFrames': 0,
      'droppedNativeWrites': 1,
      'playoutUnderruns': 1,
      'native': {
        'writesDropped': 12,
        'underrunCount': 6,
        'starts': 3,
      },
    });
    state.updateAudioPipelineStatus(const {
      'droppedBufferFrames': 0,
      'droppedNativeWrites': 1,
      'playoutUnderruns': 1,
      'native': {
        'writesDropped': 12,
        'underrunCount': 0,
        'starts': 3,
      },
    });
    state.updateAudioPipelineStatus(const {
      'droppedBufferFrames': 0,
      'droppedNativeWrites': 1,
      'playoutUnderruns': 1,
      'native': {
        'writesDropped': 12,
        'underrunCount': 1,
        'starts': 3,
      },
    });
    expect(state.snapshot().skippedAudioChunks, 5);
  });
}
