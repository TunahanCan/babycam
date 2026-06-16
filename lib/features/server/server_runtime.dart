import 'dart:async';

import 'media/media_resource_counter.dart';
import 'media/media_runtime_controller.dart';
import 'media/server_power_mode.dart';

class ServerRuntimeState {
  const ServerRuntimeState({
    required this.phase,
    this.powerMode = ServerPowerMode.pairingOnly,
    this.activeClients = 0,
    this.activeVideoClients = 0,
    this.activeAudioClients = 0,
    this.activeEventClients = 0,
    this.cameraActive = false,
    this.microphoneActive = false,
    this.motionAnalyzerActive = false,
    this.cryAnalyzerActive = false,
    this.qrPayload,
    this.lastAlert,
    this.errorMessage,
  });

  final ServerRuntimePhase phase;
  final ServerPowerMode powerMode;
  final int activeClients;
  final int activeVideoClients;
  final int activeAudioClients;
  final int activeEventClients;
  final bool cameraActive;
  final bool microphoneActive;
  final bool motionAnalyzerActive;
  final bool cryAnalyzerActive;
  final String? qrPayload;
  final String? lastAlert;
  final String? errorMessage;
}

enum ServerRuntimePhase {
  stopped,
  pairingIdle,
  pairingActive,
  clientPaired,
  mediaIdle,
  mediaStarting,
  mediaActive,
  error
}

class StreamSessionOptions {
  const StreamSessionOptions({this.video = true, this.audio = false});
  final bool video;
  final bool audio;
}

class ServerRuntime {
  ServerRuntime({
    required MediaRuntimeController mediaRuntime,
    Future<String> Function()? onStartPairing,
    Future<void> Function()? onStop,
    Future<void> Function()? onSettingsChanged,
    Object? Function()? previewSource,
  })  : _mediaRuntime = mediaRuntime,
        _onStartPairing = onStartPairing,
        _onStop = onStop,
        _onSettingsChanged = onSettingsChanged,
        _previewSource = previewSource;

  final MediaRuntimeController _mediaRuntime;
  final Future<String> Function()? _onStartPairing;
  final Future<void> Function()? _onStop;
  final Future<void> Function()? _onSettingsChanged;
  final Object? Function()? _previewSource;
  final _states = StreamController<ServerRuntimeState>.broadcast();
  final _activeSessions = <String, StreamSessionOptions>{};
  final _notificationClients = <String, ({bool cry, bool motion})>{};
  final _resources = MediaResourceCounter();
  ServerRuntimeState _state =
      const ServerRuntimeState(phase: ServerRuntimePhase.stopped);
  bool _disposed = false;

  Stream<ServerRuntimeState> get states => _states.stream;
  ServerRuntimeState get currentState => _state;
  Object? get previewSource => _previewSource?.call();

  Future<void> startPairingOnly() => startPairingMode();

  Future<void> startPairingMode() async {
    try {
      final qr = await _onStartPairing?.call();
      _emit(ServerRuntimeState(
          phase: ServerRuntimePhase.pairingActive, qrPayload: qr));
      await startLocalPreview();
    } catch (error) {
      _emit(ServerRuntimeState(
        phase: ServerRuntimePhase.error,
        qrPayload: _state.qrPayload,
        errorMessage: error.toString(),
      ));
    }
  }

  Future<void> startLocalPreview() async {
    _resources.localPreviewActive = true;
    _emit(_stateForPhase(ServerRuntimePhase.mediaStarting));
    try {
      await _mediaRuntime.start();
      _emit(_stateForPhase(ServerRuntimePhase.mediaActive));
    } catch (_) {
      _resources.localPreviewActive = false;
      rethrow;
    }
  }

  Future<void> markClientPaired() async =>
      _emit(_stateForPhase(ServerRuntimePhase.clientPaired));

  Future<void> onClientPaired(Object client) => markClientPaired();

  Future<void> startStreamSession(
      String clientId, StreamSessionOptions options) async {
    _activeSessions[clientId] = options;
    await _recomputeResources(
        startMediaIfNeeded: true, phase: ServerRuntimePhase.mediaActive);
  }

  Future<void> stopStreamSession(String clientId) => endSession(clientId);

  Future<void> startMediaRuntimeForSession(String sessionId) =>
      startStreamSession(sessionId, const StreamSessionOptions());

  Future<void> endSession(String sessionId) async {
    _activeSessions.remove(sessionId);
    await stopMediaRuntimeIfNoActiveClients();
  }

  Future<void> enableNotificationsForClient(String clientId,
      {required bool cry, required bool motion}) async {
    _notificationClients[clientId] = (cry: cry, motion: motion);
    await _recomputeResources(
        startMediaIfNeeded: cry || motion,
        phase: ServerRuntimePhase.mediaActive);
  }

  Future<void> disableNotificationsForClient(String clientId) async {
    _notificationClients.remove(clientId);
    await stopMediaRuntimeIfNoActiveClients();
  }

  Future<void> stopMediaRuntimeIfNoActiveClients() async {
    await _recomputeResources(
        startMediaIfNeeded: false, phase: ServerRuntimePhase.mediaIdle);
    if (!_resources.needsVideoCapture && !_resources.needsAudioCapture) {
      await _mediaRuntime.stop();
    }
    _emit(_stateForPhase(_resources.hasNotificationDemand
        ? ServerRuntimePhase.mediaIdle
        : ServerRuntimePhase.mediaIdle));
  }

  Future<void> stop() async {
    _activeSessions.clear();
    _notificationClients.clear();
    _resources.localPreviewActive = false;
    await _mediaRuntime.stop();
    await _onStop?.call();
    _emit(const ServerRuntimeState(phase: ServerRuntimePhase.stopped));
  }

  Future<void> reloadAnalysisSettings() async {
    await _onSettingsChanged?.call();
    _emit(_stateForPhase(_state.phase));
  }

  Future<void> _recomputeResources(
      {required bool startMediaIfNeeded,
      required ServerRuntimePhase phase}) async {
    _resources.activeVideoClients =
        _activeSessions.values.where((s) => s.video).length;
    _resources.activeAudioClients =
        _activeSessions.values.where((s) => s.audio).length;
    _resources.activeEventClients = _notificationClients.length;
    _resources.wantsCryDetection =
        _notificationClients.values.any((s) => s.cry);
    _resources.wantsMotionDetection =
        _notificationClients.values.any((s) => s.motion);
    if (startMediaIfNeeded &&
        (_resources.needsVideoCapture || _resources.needsAudioCapture)) {
      _emit(_stateForPhase(ServerRuntimePhase.mediaStarting));
      await _mediaRuntime.start();
    }
    _emit(_stateForPhase(phase));
  }

  ServerRuntimeState _stateForPhase(ServerRuntimePhase phase) {
    final powerMode = _resources.hasLiveWatch
        ? ServerPowerMode.liveWatch
        : _resources.hasNotificationDemand
            ? ServerPowerMode.notificationArmed
            : ServerPowerMode.pairingOnly;
    return ServerRuntimeState(
      phase: phase,
      powerMode: powerMode,
      activeClients: _activeSessions.length,
      activeVideoClients: _resources.activeVideoClients,
      activeAudioClients: _resources.activeAudioClients,
      activeEventClients: _resources.activeEventClients,
      cameraActive: _resources.needsVideoCapture,
      microphoneActive: _resources.needsAudioCapture,
      motionAnalyzerActive: _resources.wantsMotionDetection,
      cryAnalyzerActive: _resources.wantsCryDetection,
      qrPayload: _state.qrPayload,
      lastAlert: _state.lastAlert,
      errorMessage: _state.errorMessage,
    );
  }

  void _emit(ServerRuntimeState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _states.close();
  }
}
