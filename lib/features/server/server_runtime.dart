import 'dart:async';

import '../../core/media/adaptive_media_profile.dart';
import '../../services/monetization/broadcast_access_service.dart';
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
    this.mediaProfile,
    this.broadcastAccess,
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
  final MediaQualityProfile? mediaProfile;
  final BroadcastAccessSnapshot? broadcastAccess;
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
    Future<void> Function()? onStopPairing,
    Future<void> Function()? onStop,
    Future<void> Function()? onSettingsChanged,
    Object? Function()? previewSource,
    MediaQualityProfile Function()? mediaProfile,
    BroadcastAccessService? broadcastAccess,
  })  : _mediaRuntime = mediaRuntime,
        _onStartPairing = onStartPairing,
        _onStopPairing = onStopPairing,
        _onStop = onStop,
        _onSettingsChanged = onSettingsChanged,
        _previewSource = previewSource,
        _mediaProfile = mediaProfile,
        _broadcastAccess = broadcastAccess;

  final MediaRuntimeController _mediaRuntime;
  final Future<String> Function()? _onStartPairing;
  final Future<void> Function()? _onStopPairing;
  final Future<void> Function()? _onStop;
  final Future<void> Function()? _onSettingsChanged;
  final Object? Function()? _previewSource;
  final MediaQualityProfile Function()? _mediaProfile;
  final BroadcastAccessService? _broadcastAccess;
  final _states = StreamController<ServerRuntimeState>.broadcast();
  final _activeSessions = <String, StreamSessionOptions>{};
  final _notificationClients = <String, ({bool cry, bool motion})>{};
  final _resources = MediaResourceCounter();
  ServerRuntimeState _state =
      const ServerRuntimeState(phase: ServerRuntimePhase.stopped);
  Timer? _broadcastAccessTimer;
  bool _disposed = false;

  Stream<ServerRuntimeState> get states => _states.stream;
  ServerRuntimeState get currentState => _state;
  Object? get previewSource => _previewSource?.call();
  MediaQualityProfile? get mediaProfile => _mediaProfile?.call();

  Future<void> refreshBroadcastAccess() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    _emit(
      _stateForPhase(
        _state.phase,
        broadcastAccess: await access.snapshot(),
      ),
    );
  }

  Future<void> unlockBroadcastAccess() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    final snapshot = await access.unlockWithOneTimePurchase();
    _emit(_stateForPhase(_state.phase, broadcastAccess: snapshot));
  }

  Future<void> restoreBroadcastAccessPurchase() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    final snapshot = await access.restorePurchase();
    _emit(_stateForPhase(_state.phase, broadcastAccess: snapshot));
  }

  Future<void> startPairingOnly() => startPairingMode();

  Future<void> startPairingMode() async {
    if (_disposed) return;
    try {
      final qr = await _onStartPairing?.call();
      if (_disposed) return;
      _emit(ServerRuntimeState(
        phase: ServerRuntimePhase.pairingActive,
        qrPayload: qr,
        mediaProfile: mediaProfile,
        broadcastAccess: _state.broadcastAccess,
      ));
    } catch (error) {
      if (_disposed) return;
      _emit(ServerRuntimeState(
        phase: ServerRuntimePhase.error,
        qrPayload: _state.qrPayload,
        errorMessage: error.toString(),
        mediaProfile: mediaProfile,
        broadcastAccess: _state.broadcastAccess,
      ));
    }
  }

  Future<void> stopPairingMode() async {
    if (_disposed) return;
    await _onStopPairing?.call();
    if (_disposed) return;
    if (_state.phase == ServerRuntimePhase.pairingActive) {
      _emit(_stateForPhase(ServerRuntimePhase.pairingIdle));
    }
  }

  Future<void> startLocalPreview() async {
    if (_disposed) return;
    final access = _broadcastAccess;
    BroadcastAccessSnapshot? accessSnapshot;
    const accessSessionId = 'server.localPreview';
    if (access != null) {
      try {
        accessSnapshot = await access.beginSession(accessSessionId);
      } on BroadcastAccessLockedException catch (error) {
        _emit(_errorState(error, broadcastAccess: error.snapshot));
        rethrow;
      }
    }
    _resources.localPreviewActive = true;
    _emit(_stateForPhase(
      ServerRuntimePhase.mediaStarting,
      broadcastAccess: accessSnapshot,
    ));
    try {
      await _mediaRuntime.start();
      if (_disposed) {
        _resources.localPreviewActive = false;
        await access?.endSession(accessSessionId);
        await _mediaRuntime.stop();
        return;
      }
      _emit(_stateForPhase(
        ServerRuntimePhase.mediaActive,
        broadcastAccess: accessSnapshot,
      ));
      _scheduleBroadcastAccessTimer(accessSnapshot);
    } catch (error) {
      _resources.localPreviewActive = false;
      accessSnapshot = await access?.endSession(accessSessionId);
      _emit(_errorState(error, broadcastAccess: accessSnapshot));
      rethrow;
    }
  }

  Future<void> markClientPaired() async {
    if (_disposed) return;
    _emit(_stateForPhase(ServerRuntimePhase.clientPaired));
  }

  Future<void> onClientPaired(Object client) => markClientPaired();

  Future<void> startStreamSession(
      String clientId, StreamSessionOptions options) async {
    if (_disposed) return;
    _activeSessions[clientId] = options;
    try {
      await _recomputeResources(
          startMediaIfNeeded: true, phase: ServerRuntimePhase.mediaActive);
    } catch (error) {
      _activeSessions.remove(clientId);
      _refreshResourceCounts();
      _emit(_errorState(error));
      rethrow;
    }
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
    if (_disposed) return;
    _notificationClients[clientId] = (cry: cry, motion: motion);
    try {
      await _recomputeResources(
          startMediaIfNeeded: cry || motion,
          phase: ServerRuntimePhase.mediaActive);
    } catch (error) {
      _notificationClients.remove(clientId);
      _refreshResourceCounts();
      _emit(_errorState(error));
      rethrow;
    }
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
    await _broadcastAccess?.endAllSessions();
    _broadcastAccessTimer?.cancel();
    await _mediaRuntime.stop();
    await _onStop?.call();
    _emit(ServerRuntimeState(
      phase: ServerRuntimePhase.stopped,
      broadcastAccess: _state.broadcastAccess,
    ));
  }

  Future<void> reloadAnalysisSettings() async {
    if (_disposed) return;
    await _onSettingsChanged?.call();
    if (_disposed) return;
    _emit(_stateForPhase(_state.phase));
  }

  void refreshMediaProfile() {
    if (_disposed) return;
    _emit(_stateForPhase(_state.phase));
  }

  Future<void> _recomputeResources(
      {required bool startMediaIfNeeded,
      required ServerRuntimePhase phase}) async {
    if (_disposed) return;
    _refreshResourceCounts();
    if (startMediaIfNeeded &&
        (_resources.needsVideoCapture || _resources.needsAudioCapture)) {
      _emit(_stateForPhase(ServerRuntimePhase.mediaStarting));
      try {
        await _mediaRuntime.start();
      } catch (error) {
        _emit(_errorState(error));
        rethrow;
      }
      if (_disposed) {
        await _mediaRuntime.stop();
        return;
      }
    }
    _emit(_stateForPhase(phase));
  }

  void _refreshResourceCounts() {
    _resources.activeVideoClients =
        _activeSessions.values.where((s) => s.video).length;
    _resources.activeAudioClients =
        _activeSessions.values.where((s) => s.audio).length;
    _resources.activeEventClients = _notificationClients.length;
    _resources.wantsCryDetection =
        _notificationClients.values.any((s) => s.cry);
    _resources.wantsMotionDetection =
        _notificationClients.values.any((s) => s.motion);
  }

  ServerRuntimeState _stateForPhase(
    ServerRuntimePhase phase, {
    BroadcastAccessSnapshot? broadcastAccess,
  }) {
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
      mediaProfile: mediaProfile,
      broadcastAccess: broadcastAccess ?? _state.broadcastAccess,
    );
  }

  ServerRuntimeState _errorState(
    Object error, {
    BroadcastAccessSnapshot? broadcastAccess,
  }) =>
      ServerRuntimeState(
        phase: ServerRuntimePhase.error,
        powerMode: _state.powerMode,
        activeClients: _activeSessions.length,
        activeVideoClients: _resources.activeVideoClients,
        activeAudioClients: _resources.activeAudioClients,
        activeEventClients: _notificationClients.length,
        cameraActive: false,
        microphoneActive: false,
        motionAnalyzerActive: false,
        cryAnalyzerActive: false,
        qrPayload: _state.qrPayload,
        lastAlert: _state.lastAlert,
        errorMessage: error.toString(),
        mediaProfile: mediaProfile,
        broadcastAccess: broadcastAccess ?? _state.broadcastAccess,
      );

  void _emit(ServerRuntimeState state) {
    if (_disposed && state.phase != ServerRuntimePhase.stopped) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  void _scheduleBroadcastAccessTimer(BroadcastAccessSnapshot? snapshot) {
    _broadcastAccessTimer?.cancel();
    if (snapshot == null || snapshot.unlocked || snapshot.remainingMs <= 0) {
      return;
    }
    _broadcastAccessTimer = Timer(snapshot.remaining, () {
      unawaited(_handleBroadcastAccessExpired());
    });
  }

  Future<void> _handleBroadcastAccessExpired() async {
    if (_disposed) return;
    await _mediaRuntime.stop();
    _activeSessions.clear();
    _notificationClients.clear();
    _resources.localPreviewActive = false;
    final snapshot = await _broadcastAccess?.endAllSessions();
    _broadcastAccessTimer?.cancel();
    if (_disposed || snapshot == null || !snapshot.isLocked) return;
    _emit(_errorState(
      BroadcastAccessLockedException(snapshot),
      broadcastAccess: snapshot,
    ));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _broadcastAccess?.dispose();
    await _states.close();
  }
}
