import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mimicam/features/client/media/client_stream_health_state.dart';
import 'package:mimicam/features/client/media/webrtc/webrtc_client_connector.dart';
import 'package:mimicam/features/client/media/webrtc/webrtc_client_media_supervisor.dart';

void main() {
  test('connected WebRTC stats feed frame/audio liveness', () async {
    var nowMs = 1000;
    final handle = _FakeHandle();
    final health = ClientStreamHealthState(nowMs: () => nowMs)
      ..resetForNewWatchSession();
    final supervisor = WebRtcClientMediaSupervisor(
      handle: handle,
      videoExpected: true,
      audioExpected: true,
      healthState: health,
      statsInterval: const Duration(milliseconds: 1),
      onReconnectRequired: () async {},
      onFatalError: (error) => fail(error.toString()),
    );

    handle.state = RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    await supervisor.start();
    nowMs += 6000;
    handle.stats = const WebRtcClientStatsSnapshot(
      videoBytesReceived: 200,
      audioBytesReceived: 100,
      videoFramesDecoded: 3,
      videoFramesDropped: 2,
      packetsReceived: 40,
      packetsLost: 1,
      videoCodec: 'video/H264',
      audioCodec: 'audio/opus',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await supervisor.stop();

    final snapshot = health.snapshot();
    expect(snapshot.streamTimedOut, isFalse);
    expect(snapshot.skippedVideoFrames, 2);
    expect(snapshot.transportTelemetry['transport'], 'webrtc');
    expect(snapshot.transportTelemetry['videoCodec'], 'video/H264');
  });

  test('failed state dispatches one serialized reconnect', () async {
    final handle = _FakeHandle();
    var reconnects = 0;
    final supervisor = WebRtcClientMediaSupervisor(
      handle: handle,
      videoExpected: true,
      audioExpected: false,
      statsInterval: const Duration(days: 1),
      onReconnectRequired: () async {
        reconnects++;
      },
      onFatalError: (error) => fail(error.toString()),
    );
    await supervisor.start();

    handle.emit(RTCPeerConnectionState.RTCPeerConnectionStateFailed);
    handle.emit(RTCPeerConnectionState.RTCPeerConnectionStateClosed);
    await pumpEventQueue();

    expect(reconnects, 1);
    await supervisor.stop();
  });
}

class _FakeHandle implements WebRtcClientMediaHandle, WebRtcClientStatsSource {
  final states = StreamController<RTCPeerConnectionState>.broadcast();
  RTCPeerConnectionState state =
      RTCPeerConnectionState.RTCPeerConnectionStateNew;
  WebRtcClientStatsSnapshot stats = const WebRtcClientStatsSnapshot(
    videoBytesReceived: 1,
    audioBytesReceived: 1,
    videoFramesDecoded: 1,
    videoCodec: 'video/H264',
    audioCodec: 'audio/opus',
  );

  void emit(RTCPeerConnectionState next) {
    state = next;
    states.add(next);
  }

  @override
  Future<WebRtcClientStatsSnapshot> collectStats() async => stats;

  @override
  RTCPeerConnectionState get connectionState => state;

  @override
  Stream<RTCPeerConnectionState> get connectionStates => states.stream;

  @override
  String get peerId => 'peer';

  @override
  RTCVideoRenderer get videoRenderer => RTCVideoRenderer();

  @override
  Future<void> close() => states.close();
}
