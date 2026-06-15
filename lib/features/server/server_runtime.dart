import 'dart:async';

import 'media/media_runtime_controller.dart';

class ServerRuntimeState {
  const ServerRuntimeState({required this.phase, this.activeClients = 0, this.qrPayload, this.lastAlert});
  final ServerRuntimePhase phase;
  final int activeClients;
  final String? qrPayload;
  final String? lastAlert;
}

enum ServerRuntimePhase { stopped, pairingIdle, pairingActive, clientPaired, mediaIdle, mediaStarting, mediaActive, error }

class ServerRuntime {
  ServerRuntime({required MediaRuntimeController mediaRuntime, Future<String> Function()? onStartPairing, Future<void> Function()? onStop}) : _mediaRuntime = mediaRuntime, _onStartPairing = onStartPairing, _onStop = onStop;
  final MediaRuntimeController _mediaRuntime;
  final Future<String> Function()? _onStartPairing;
  final Future<void> Function()? _onStop;
  final _states = StreamController<ServerRuntimeState>.broadcast();
  final _activeSessions = <String>{};
  ServerRuntimeState _state = const ServerRuntimeState(phase: ServerRuntimePhase.stopped);

  Stream<ServerRuntimeState> get states => _states.stream;
  ServerRuntimeState get currentState => _state;

  Future<void> startPairingMode() async {
    final qr = await _onStartPairing?.call();
    _emit(ServerRuntimeState(phase: ServerRuntimePhase.pairingActive, qrPayload: qr));
  }

  Future<void> markClientPaired() async => _emit(ServerRuntimeState(phase: ServerRuntimePhase.clientPaired, activeClients: _activeSessions.length, qrPayload: _state.qrPayload));

  Future<void> startMediaRuntimeForSession(String sessionId) async {
    _activeSessions.add(sessionId);
    _emit(ServerRuntimeState(phase: ServerRuntimePhase.mediaStarting, activeClients: _activeSessions.length, qrPayload: _state.qrPayload));
    await _mediaRuntime.start();
    _emit(ServerRuntimeState(phase: ServerRuntimePhase.mediaActive, activeClients: _activeSessions.length, qrPayload: _state.qrPayload));
  }

  Future<void> endSession(String sessionId) async {
    _activeSessions.remove(sessionId);
    await stopMediaRuntimeIfNoActiveClients();
  }

  Future<void> stopMediaRuntimeIfNoActiveClients() async {
    if (_activeSessions.isNotEmpty) return;
    await _mediaRuntime.stop();
    _emit(ServerRuntimeState(phase: ServerRuntimePhase.mediaIdle, qrPayload: _state.qrPayload));
  }

  Future<void> stop() async {
    _activeSessions.clear();
    await _mediaRuntime.stop();
    await _onStop?.call();
    _emit(const ServerRuntimeState(phase: ServerRuntimePhase.stopped));
  }

  void _emit(ServerRuntimeState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> dispose() async {
    await stop();
    await _states.close();
  }
}
