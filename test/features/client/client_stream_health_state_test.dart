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
}
