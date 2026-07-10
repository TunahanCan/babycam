import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../client_stream_health_state.dart';
import 'webrtc_client_connector.dart';

class WebRtcClientMediaSupervisor {
  WebRtcClientMediaSupervisor({
    required this.handle,
    required this.videoExpected,
    required this.audioExpected,
    required this.onReconnectRequired,
    required this.onFatalError,
    this.healthState,
    this.statsInterval = const Duration(seconds: 1),
    this.disconnectedGrace = const Duration(seconds: 3),
  });

  final WebRtcClientMediaHandle handle;
  final bool videoExpected;
  final bool audioExpected;
  final ClientStreamHealthState? healthState;
  final Future<void> Function() onReconnectRequired;
  final void Function(Object error) onFatalError;
  final Duration statsInterval;
  final Duration disconnectedGrace;

  StreamSubscription<RTCPeerConnectionState>? _states;
  Timer? _statsTimer;
  Timer? _disconnectTimer;
  WebRtcClientStatsSnapshot? _previousStats;
  bool _reconnectDispatched = false;
  bool _sampleInFlight = false;
  bool _stopped = false;

  Future<void> start() async {
    if (_stopped || _states != null) return;
    _states = handle.connectionStates.listen(
      _handleConnectionState,
      onError: _handleFatal,
      onDone: () {
        if (!_stopped) _dispatchReconnect();
      },
    );
    _handleConnectionState(handle.connectionState);
    _statsTimer = Timer.periodic(statsInterval, (_) => _sampleStats());
    await _sampleStats();
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    await _states?.cancel();
    _states = null;
  }

  void _handleConnectionState(RTCPeerConnectionState state) {
    if (_stopped) return;
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _disconnectTimer?.cancel();
        _disconnectTimer = null;
        if (videoExpected) healthState?.markVideoFrameReceived();
        if (audioExpected) healthState?.markAudioChunkReceived();
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _disconnectTimer ??= Timer(disconnectedGrace, _dispatchReconnect);
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _dispatchReconnect();
      case RTCPeerConnectionState.RTCPeerConnectionStateNew ||
            RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        break;
    }
  }

  Future<void> _sampleStats() async {
    if (_stopped || _sampleInFlight) return;
    if (handle is! WebRtcClientStatsSource) return;
    final source = handle as WebRtcClientStatsSource;
    _sampleInFlight = true;
    try {
      final current = await source.collectStats();
      if (_stopped) return;
      final previous = _previousStats;
      if (videoExpected &&
          (previous == null ||
              current.videoBytesReceived > previous.videoBytesReceived ||
              current.videoFramesDecoded > previous.videoFramesDecoded)) {
        healthState?.markVideoFrameReceived();
      }
      if (audioExpected &&
          (previous == null ||
              current.audioBytesReceived > previous.audioBytesReceived)) {
        healthState?.markAudioChunkReceived();
      }
      final jitterMs = current.jitterMs;
      if (jitterMs != null) {
        healthState?.updateVideoTransport(
          jitterMs: jitterMs,
          queueDelayMs: (current.jitterBufferDelayMs ?? 0).round(),
        );
      }
      healthState?.updateTransportTelemetry({
        'transport': 'webrtc',
        'videoBytesReceived': current.videoBytesReceived,
        'audioBytesReceived': current.audioBytesReceived,
        'videoFramesDecoded': current.videoFramesDecoded,
        'videoFramesDropped': current.videoFramesDropped,
        'packetsReceived': current.packetsReceived,
        'packetsLost': current.packetsLost,
        'jitterMs': current.jitterMs,
        'jitterBufferDelayMs': current.jitterBufferDelayMs,
        'videoCodec': current.videoCodec,
        'audioCodec': current.audioCodec,
        'measuredAtMs': current.measuredAtMs,
      });
      if (previous != null) {
        healthState?.markVideoFramesSkipped(
          current.videoFramesDropped - previous.videoFramesDropped,
        );
      }
      _previousStats = current;
      _validateNegotiatedCodecs(current);
    } catch (error) {
      if (!_stopped) _handleFatal(error);
    } finally {
      _sampleInFlight = false;
    }
  }

  void _validateNegotiatedCodecs(WebRtcClientStatsSnapshot stats) {
    final videoCodec = stats.videoCodec?.toLowerCase();
    final audioCodec = stats.audioCodec?.toLowerCase();
    if (videoExpected && videoCodec != null && !videoCodec.contains('h264')) {
      _handleFatal(
          StateError('WebRTC negotiated $videoCodec instead of H.264.'));
    }
    if (audioExpected && audioCodec != null && !audioCodec.contains('opus')) {
      _handleFatal(
          StateError('WebRTC negotiated $audioCodec instead of Opus.'));
    }
  }

  void _handleFatal(Object error) {
    if (_stopped) return;
    onFatalError(error);
    _dispatchReconnect();
  }

  void _dispatchReconnect() {
    if (_stopped || _reconnectDispatched) return;
    _reconnectDispatched = true;
    healthState?.markReconnectAttempt();
    unawaited(Future<void>.sync(onReconnectRequired).catchError((Object error) {
      onFatalError(error);
    }));
  }
}
