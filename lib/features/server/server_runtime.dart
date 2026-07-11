import 'dart:async';

import '../../core/media/adaptive_media_profile.dart';
import '../../services/monetization/broadcast_access_service.dart';
import '../../services/platform/platform_runtime_contract.dart';
import 'media/media_resource_counter.dart';
import 'media/media_runtime_controller.dart';
import 'media/server_power_mode.dart';
import 'media/webrtc/webrtc_server_gateway.dart';

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
    this.localPreviewActive = false,
    this.externalCaptureActive = false,
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
  final bool localPreviewActive;
  final bool externalCaptureActive;
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

enum ServerStreamTransport { legacy, webRtc }

class StreamSessionOptions {
  const StreamSessionOptions({
    this.video = true,
    this.audio = false,
    this.transport = ServerStreamTransport.legacy,
  });

  final bool video;
  final bool audio;
  final ServerStreamTransport transport;

  bool get ownsCaptureExternally => transport == ServerStreamTransport.webRtc;
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
    PlatformMediaLifecycleCoordinator? platformLifecycle,
    Future<void> Function(MediaResourceDemand demand)? onMediaDemandChanged,
    Future<void> Function(String reason)? onPauseExternalMedia,
  })  : _mediaRuntime = mediaRuntime,
        _onStartPairing = onStartPairing,
        _onStopPairing = onStopPairing,
        _onStop = onStop,
        _onSettingsChanged = onSettingsChanged,
        _previewSource = previewSource,
        _mediaProfile = mediaProfile,
        _broadcastAccess = broadcastAccess,
        _platformLifecycle = platformLifecycle,
        _onMediaDemandChanged = onMediaDemandChanged,
        _onPauseExternalMedia = onPauseExternalMedia {
    _platformLifecycle?.start();
  }

  final MediaRuntimeController _mediaRuntime;
  final Future<String> Function()? _onStartPairing;
  final Future<void> Function()? _onStopPairing;
  final Future<void> Function()? _onStop;
  final Future<void> Function()? _onSettingsChanged;
  final Object? Function()? _previewSource;
  final MediaQualityProfile Function()? _mediaProfile;
  final BroadcastAccessService? _broadcastAccess;
  final PlatformMediaLifecycleCoordinator? _platformLifecycle;
  final Future<void> Function(MediaResourceDemand demand)?
      _onMediaDemandChanged;
  final Future<void> Function(String reason)? _onPauseExternalMedia;
  final _states = StreamController<ServerRuntimeState>.broadcast();
  final _activeSessions = <String, StreamSessionOptions>{};
  final _externalCaptureOwners = <String>{};
  final _legacyMediaSuspensions = <String>{};
  final _notificationClients = <String, ({bool cry, bool motion})>{};
  final _resources = MediaResourceCounter();
  ServerRuntimeState _state =
      const ServerRuntimeState(phase: ServerRuntimePhase.stopped);
  Timer? _broadcastAccessTimer;
  int _broadcastAccessTimerGeneration = 0;
  Future<void> _mutationTail = Future<void>.value();
  bool _disposed = false;

  Stream<ServerRuntimeState> get states => _states.stream;
  ServerRuntimeState get currentState => _state;
  Object? get previewSource => _previewSource?.call();
  MediaQualityProfile? get mediaProfile => _mediaProfile?.call();

  Future<void> refreshBroadcastAccess() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    final snapshot = await access.snapshot();
    if (_disposed) return;
    _scheduleBroadcastAccessTimer(snapshot);
    _emit(
      _stateForPhase(
        _state.phase,
        broadcastAccess: snapshot,
      ),
    );
  }

  Future<void> unlockBroadcastAccess() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    _cancelBroadcastAccessTimer();
    late final BroadcastAccessSnapshot snapshot;
    try {
      snapshot = await access.unlockWithOneTimePurchase();
    } catch (error, stackTrace) {
      await _restoreBroadcastAccessTimer(access);
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (_disposed) return;
    _scheduleBroadcastAccessTimer(snapshot);
    _emit(_stateForPhase(_state.phase, broadcastAccess: snapshot));
  }

  Future<void> restoreBroadcastAccessPurchase() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    _cancelBroadcastAccessTimer();
    late final BroadcastAccessSnapshot snapshot;
    try {
      snapshot = await access.restorePurchase();
    } catch (error, stackTrace) {
      await _restoreBroadcastAccessTimer(access);
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (_disposed) return;
    _scheduleBroadcastAccessTimer(snapshot);
    _emit(_stateForPhase(_state.phase, broadcastAccess: snapshot));
  }

  Future<void> startPairingOnly() => startPairingMode();

  Future<void> startPairingMode() async {
    if (_disposed) return;
    try {
      final qr = await _onStartPairing?.call();
      if (_disposed) return;
      _emit(_stateForPhase(
        _phaseAfterPairingResult(success: true),
        qrPayload: qr,
        preserveErrorMessage: false,
      ));
    } catch (error) {
      if (_disposed) return;
      _emit(_stateForPhase(
        _phaseAfterPairingResult(success: false),
        errorMessage: error.toString(),
        preserveErrorMessage: false,
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

  Future<void> startLocalPreview() =>
      _serializeMutation(_startLocalPreviewLocked);

  Future<void> _startLocalPreviewLocked() async {
    if (_disposed) return;
    if (_externalCaptureOwners.isNotEmpty) {
      throw const WebRtcPilotCapacityException();
    }
    final access = _broadcastAccess;
    BroadcastAccessSnapshot? accessSnapshot;
    const accessSessionId = 'server.localPreview';
    if (access != null) {
      try {
        accessSnapshot = await access.beginSession(accessSessionId);
        _scheduleBroadcastAccessTimer(accessSnapshot);
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
      final demand = _resourceDemand();
      await _publishMediaDemand(demandOverride: demand);
      await _mediaRuntime.reconcile(demand);
      await _publishMediaDemand();
      if (_disposed) {
        _resources.localPreviewActive = false;
        await access?.endSession(accessSessionId);
        await _mediaRuntime.reconcile(MediaResourceDemand.none);
        await _publishMediaDemand();
        return;
      }
      _emit(_stateForPhase(
        ServerRuntimePhase.mediaActive,
        broadcastAccess: accessSnapshot,
      ));
    } catch (error, stackTrace) {
      _resources.localPreviewActive = false;
      _cancelBroadcastAccessTimer();
      try {
        accessSnapshot = await access?.endSession(accessSessionId);
        _scheduleBroadcastAccessTimer(accessSnapshot);
      } catch (_) {
        if (access != null) await _restoreBroadcastAccessTimer(access);
      }
      try {
        await _mediaRuntime.reconcile(_resourceDemand());
      } catch (_) {}
      await _publishMediaDemand();
      _emit(_errorState(error, broadcastAccess: accessSnapshot));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> stopLocalPreview() =>
      _serializeMutation(_stopLocalPreviewLocked);

  Future<void> _stopLocalPreviewLocked() async {
    final access = _broadcastAccess;
    if (!_resources.localPreviewActive) {
      if (access != null && !_disposed) {
        _cancelBroadcastAccessTimer();
        await _restoreBroadcastAccessTimer(access);
      }
      return;
    }
    _cancelBroadcastAccessTimer();
    _resources.localPreviewActive = false;
    BroadcastAccessSnapshot? accessSnapshot;
    Object? accessError;
    StackTrace? accessStackTrace;
    try {
      accessSnapshot = await access?.endSession('server.localPreview');
      _scheduleBroadcastAccessTimer(accessSnapshot);
    } catch (error, stackTrace) {
      accessError = error;
      accessStackTrace = stackTrace;
      if (access != null) {
        accessSnapshot = await _restoreBroadcastAccessTimer(access);
      }
    }
    await _recomputeResources(
      startMediaIfNeeded: false,
      phase: ServerRuntimePhase.mediaIdle,
    );
    final demand = _resourceDemand();
    _emit(_stateForPhase(
      demand.isEmpty
          ? ServerRuntimePhase.mediaIdle
          : ServerRuntimePhase.mediaActive,
      broadcastAccess: accessSnapshot,
    ));
    if (accessError != null) {
      Error.throwWithStackTrace(accessError, accessStackTrace!);
    }
  }

  Future<void> markClientPaired() async {
    if (_disposed) return;
    _emit(_stateForPhase(ServerRuntimePhase.clientPaired));
  }

  Future<void> onClientPaired(Object client) => markClientPaired();

  Future<void> startStreamSession(
    String clientId,
    StreamSessionOptions options,
  ) =>
      _serializeMutation(
        () => _startStreamSessionLocked(clientId, options),
      );

  Future<void> _startStreamSessionLocked(
    String clientId,
    StreamSessionOptions options,
  ) async {
    if (_disposed) return;
    final previous = _activeSessions[clientId];
    final wasExternalActive = _externalCaptureOwners.remove(clientId);
    _activeSessions[clientId] = options;
    try {
      await _recomputeResources(
          startMediaIfNeeded: true, phase: ServerRuntimePhase.mediaActive);
    } catch (error) {
      if (previous == null) {
        _activeSessions.remove(clientId);
      } else {
        _activeSessions[clientId] = previous;
      }
      if (wasExternalActive) {
        _externalCaptureOwners.add(clientId);
      }
      _refreshResourceCounts();
      await _publishMediaDemand();
      _emit(_errorState(error));
      rethrow;
    }
  }

  /// Transfers camera/microphone ownership to an accepted WebRTC peer.
  ///
  /// The transfer happens immediately before getUserMedia, not during the
  /// preceding HTTP session reservation. This keeps fallback transactional and
  /// prevents an abandoned offer from suspending the room indefinitely.
  Future<void> activateExternalCapture(String clientId) =>
      _serializeMutation(() => _activateExternalCaptureLocked(clientId));

  Future<void> _activateExternalCaptureLocked(String clientId) async {
    if (_disposed) throw StateError('ServerRuntime is disposed.');
    final session = _activeSessions[clientId];
    if (session == null || session.transport != ServerStreamTransport.webRtc) {
      throw const WebRtcPeerNotFoundException();
    }
    if (_externalCaptureOwners.contains(clientId)) return;
    _refreshResourceCounts();
    if (_hasCompetingLegacyDemand(clientId, session)) {
      throw const WebRtcPilotCapacityException();
    }
    _externalCaptureOwners.add(clientId);
    try {
      await _recomputeResources(
        startMediaIfNeeded: false,
        phase: ServerRuntimePhase.mediaActive,
      );
    } catch (error) {
      _externalCaptureOwners.remove(clientId);
      _refreshResourceCounts();
      rethrow;
    }
  }

  Future<void> deactivateExternalCapture(String clientId) =>
      _serializeMutation(() => _deactivateExternalCaptureLocked(clientId));

  Future<void> _deactivateExternalCaptureLocked(String clientId) async {
    if (!_externalCaptureOwners.remove(clientId)) return;
    await _recomputeResources(
      startMediaIfNeeded: true,
      phase: ServerRuntimePhase.mediaActive,
    );
  }

  Future<void> stopStreamSession(String clientId) => endSession(clientId);

  Future<void> startMediaRuntimeForSession(String sessionId) =>
      startStreamSession(sessionId, const StreamSessionOptions());

  Future<void> endSession(String sessionId) =>
      _serializeMutation(() => _endSessionLocked(sessionId));

  Future<void> _endSessionLocked(String sessionId) async {
    _activeSessions.remove(sessionId);
    _externalCaptureOwners.remove(sessionId);
    await _stopMediaRuntimeIfNoActiveClientsLocked();
  }

  Future<void> enableNotificationsForClient(String clientId,
          {required bool cry, required bool motion}) =>
      _serializeMutation(
        () => _enableNotificationsForClientLocked(
          clientId,
          cry: cry,
          motion: motion,
        ),
      );

  Future<void> _enableNotificationsForClientLocked(
    String clientId, {
    required bool cry,
    required bool motion,
  }) async {
    if (_disposed) return;
    if ((cry || motion) && _externalCaptureOwners.isNotEmpty) {
      final pauseExternal = _onPauseExternalMedia;
      if (pauseExternal == null) {
        throw const WebRtcPilotCapacityException();
      }
      // The pilot cannot yet route WebRTC frames into the Dart analyzers.
      // Release its native tracks first so reconnect can select MJPEG/WAV
      // while notification analysis owns camera and microphone capture.
      await pauseExternal('notificationDemand');
    }
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

  Future<void> disableNotificationsForClient(String clientId) =>
      _serializeMutation(() => _disableNotificationsForClientLocked(clientId));

  Future<void> _disableNotificationsForClientLocked(String clientId) async {
    _notificationClients.remove(clientId);
    await _stopMediaRuntimeIfNoActiveClientsLocked();
  }

  Future<void> stopMediaRuntimeIfNoActiveClients() =>
      _serializeMutation(_stopMediaRuntimeIfNoActiveClientsLocked);

  Future<void> _stopMediaRuntimeIfNoActiveClientsLocked() async {
    await _recomputeResources(
        startMediaIfNeeded: false, phase: ServerRuntimePhase.mediaIdle);
    final demand = _resourceDemand();
    final mediaStillRequired = !demand.isEmpty;
    _emit(_stateForPhase(mediaStillRequired
        ? ServerRuntimePhase.mediaActive
        : ServerRuntimePhase.mediaIdle));
  }

  Future<void> stop() async {
    Object? serverError;
    StackTrace? serverStack;
    try {
      // Do not hold the resource mutation queue while MimiCamServer drains its
      // HTTP session queue: an in-flight session may still need to enqueue its
      // final runtime callback here.
      await _onStop?.call();
    } catch (error, stackTrace) {
      serverError = error;
      serverStack = stackTrace;
    }
    await _serializeMutation(_stopLocked);
    if (serverError != null) {
      Error.throwWithStackTrace(serverError, serverStack!);
    }
  }

  Future<void> _stopLocked() async {
    _cancelBroadcastAccessTimer();
    _activeSessions.clear();
    _externalCaptureOwners.clear();
    _notificationClients.clear();
    _resources.localPreviewActive = false;
    _refreshResourceCounts();
    await _broadcastAccess?.endAllSessions();
    await _mediaRuntime.reconcile(MediaResourceDemand.none);
    _legacyMediaSuspensions.clear();
    if (_mediaRuntime.isSuspended) await _mediaRuntime.resume();
    await _publishMediaDemand();
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

  Future<void> pauseMediaForPlatform(String reason) =>
      _serializeMutation(() => _pauseMediaForPlatformLocked(reason));

  Future<void> _pauseMediaForPlatformLocked(String reason) async {
    if (_disposed) return;
    await _addLegacyMediaSuspension('platform');
    await _onPauseExternalMedia?.call(reason);
    await _publishMediaDemand(forceNone: true);
    if (_disposed) return;
    _emit(_stateForPhase(ServerRuntimePhase.mediaIdle));
  }

  Future<void> recoverMediaForPlatform(String reason) =>
      _serializeMutation(() => _recoverMediaForPlatformLocked(reason));

  Future<void> _recoverMediaForPlatformLocked(String reason) async {
    if (_disposed) return;
    await _removeLegacyMediaSuspension('platform');
    await _publishMediaDemand();
    if (_disposed) return;
    _emit(_stateForPhase(
      _mediaRuntime.isActive
          ? ServerRuntimePhase.mediaActive
          : ServerRuntimePhase.mediaIdle,
    ));
  }

  Future<void> _recomputeResources(
      {required bool startMediaIfNeeded,
      required ServerRuntimePhase phase}) async {
    if (_disposed) return;
    _refreshResourceCounts();
    final demand = _resourceDemand();
    final acquiringHardware = (demand.video && !_mediaRuntime.videoActive) ||
        (demand.audio && !_mediaRuntime.audioActive);
    if (acquiringHardware) {
      // Android requires the exact foreground-service types to be active
      // before CameraX/AudioRecord acquisition. Publish the target first and
      // reconcile it back to the actual state if acquisition fails.
      await _publishMediaDemand(
          demandOverride: MediaResourceDemand(
        video: demand.video || _resources.externalVideoClients > 0,
        audio: demand.audio || _resources.externalAudioClients > 0,
        serviceVideoCapture: demand.video,
        serviceAudioCapture: demand.audio,
      ));
    }
    if (startMediaIfNeeded && !demand.isEmpty) {
      _emit(_stateForPhase(ServerRuntimePhase.mediaStarting));
      try {
        await _mediaRuntime.reconcile(demand);
      } catch (error) {
        await _publishMediaDemand();
        _emit(_errorState(error));
        rethrow;
      }
      if (_disposed) {
        await _mediaRuntime.reconcile(MediaResourceDemand.none);
        return;
      }
    } else {
      await _mediaRuntime.reconcile(demand);
    }
    await _publishMediaDemand();
    _emit(_stateForPhase(phase));
  }

  void _refreshResourceCounts() {
    _resources.activeVideoClients =
        _activeSessions.values.where((s) => s.video).length;
    _resources.activeAudioClients =
        _activeSessions.values.where((s) => s.audio).length;
    _resources.externalVideoClients = _activeSessions.entries
        .where((entry) =>
            entry.value.video && _externalCaptureOwners.contains(entry.key))
        .length;
    _resources.externalAudioClients = _activeSessions.entries
        .where((entry) =>
            entry.value.audio && _externalCaptureOwners.contains(entry.key))
        .length;
    _resources.activeEventClients = _notificationClients.length;
    _resources.wantsCryDetection =
        _notificationClients.values.any((s) => s.cry);
    _resources.wantsMotionDetection =
        _notificationClients.values.any((s) => s.motion);
  }

  MediaResourceDemand _resourceDemand() => MediaResourceDemand(
        video: _resources.needsVideoCapture,
        audio: _resources.needsAudioCapture,
      );

  ServerRuntimeState _stateForPhase(
    ServerRuntimePhase phase, {
    BroadcastAccessSnapshot? broadcastAccess,
    String? qrPayload,
    String? errorMessage,
    bool preserveErrorMessage = true,
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
      cameraActive: _mediaRuntime.videoActive ||
          (_resources.externalVideoClients > 0 &&
              !_legacyMediaSuspensions.contains('platform')),
      microphoneActive: _mediaRuntime.audioActive ||
          (_resources.externalAudioClients > 0 &&
              !_legacyMediaSuspensions.contains('platform')),
      motionAnalyzerActive:
          _mediaRuntime.videoActive && _resources.wantsMotionDetection,
      cryAnalyzerActive:
          _mediaRuntime.audioActive && _resources.wantsCryDetection,
      localPreviewActive: _resources.localPreviewActive,
      externalCaptureActive: _externalCaptureOwners.isNotEmpty,
      qrPayload: qrPayload ?? _state.qrPayload,
      lastAlert: _state.lastAlert,
      errorMessage: preserveErrorMessage ? _state.errorMessage : errorMessage,
      mediaProfile: mediaProfile,
      broadcastAccess: broadcastAccess ?? _state.broadcastAccess,
    );
  }

  ServerRuntimePhase _phaseAfterPairingResult({required bool success}) {
    if (_state.phase == ServerRuntimePhase.mediaStarting) {
      return ServerRuntimePhase.mediaStarting;
    }
    if (_mediaRuntime.isActive ||
        _resources.externalVideoClients > 0 ||
        _resources.externalAudioClients > 0) {
      return ServerRuntimePhase.mediaActive;
    }
    return success
        ? ServerRuntimePhase.pairingActive
        : ServerRuntimePhase.error;
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
        localPreviewActive: _resources.localPreviewActive,
        externalCaptureActive: _externalCaptureOwners.isNotEmpty,
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

  void _cancelBroadcastAccessTimer() {
    _broadcastAccessTimerGeneration++;
    _broadcastAccessTimer?.cancel();
    _broadcastAccessTimer = null;
  }

  void _scheduleBroadcastAccessTimer(BroadcastAccessSnapshot? snapshot) {
    _cancelBroadcastAccessTimer();
    if (snapshot == null || snapshot.unlocked || !snapshot.active) {
      return;
    }
    final generation = _broadcastAccessTimerGeneration;
    final delay = snapshot.isLocked ? Duration.zero : snapshot.remaining;
    _broadcastAccessTimer = Timer(delay, () {
      if (_disposed || generation != _broadcastAccessTimerGeneration) return;
      _broadcastAccessTimer = null;
      unawaited(
        _handleBroadcastAccessExpired(generation).then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        ),
      );
    });
  }

  Future<BroadcastAccessSnapshot?> _restoreBroadcastAccessTimer(
    BroadcastAccessService access,
  ) async {
    if (_disposed) return null;
    try {
      final snapshot = await access.snapshot();
      if (_disposed) return snapshot;
      _scheduleBroadcastAccessTimer(snapshot);
      _emit(_stateForPhase(_state.phase, broadcastAccess: snapshot));
      return snapshot;
    } catch (_) {
      _cancelBroadcastAccessTimer();
      return null;
    }
  }

  Future<void> _handleBroadcastAccessExpired(int generation) =>
      _serializeMutation(() => _handleBroadcastAccessExpiredLocked(generation));

  Future<void> _handleBroadcastAccessExpiredLocked(int generation) async {
    if (_disposed || generation != _broadcastAccessTimerGeneration) return;
    final access = _broadcastAccess;
    if (access == null) {
      _cancelBroadcastAccessTimer();
      return;
    }
    final authoritative = await access.snapshot();
    if (_disposed || generation != _broadcastAccessTimerGeneration) return;
    if (!authoritative.active || authoritative.unlocked) {
      _cancelBroadcastAccessTimer();
      _emit(_stateForPhase(_state.phase, broadcastAccess: authoritative));
      return;
    }
    if (!authoritative.isLocked) {
      _scheduleBroadcastAccessTimer(authoritative);
      _emit(_stateForPhase(_state.phase, broadcastAccess: authoritative));
      return;
    }

    // Invalidate this callback before releasing resources. Any unlock, restore,
    // or local-preview transition that started while the snapshot was being
    // read has already advanced the generation and returns above.
    _cancelBroadcastAccessTimer();
    await _mediaRuntime.reconcile(MediaResourceDemand.none);
    _activeSessions.clear();
    _externalCaptureOwners.clear();
    _notificationClients.clear();
    _resources.localPreviewActive = false;
    _refreshResourceCounts();
    _legacyMediaSuspensions.clear();
    if (_mediaRuntime.isSuspended) await _mediaRuntime.resume();
    await _publishMediaDemand();
    final snapshot = await access.endAllSessions();
    if (_disposed || !snapshot.isLocked) return;
    _emit(_errorState(
      BroadcastAccessLockedException(snapshot),
      broadcastAccess: snapshot,
    ));
  }

  Future<void> _serializeMutation(Future<void> Function() operation) {
    final next = _mutationTail.then<void>(
      (_) => operation(),
      onError: (_) => operation(),
    );
    // Callers still receive their own failure, while a rejected mutation does
    // not poison later stop/recovery work.
    _mutationTail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _platformLifecycle?.dispose();
    await stop();
    await _broadcastAccess?.dispose();
    await _states.close();
  }

  Future<void> _addLegacyMediaSuspension(String owner) async {
    if (!_legacyMediaSuspensions.add(owner)) return;
    if (_legacyMediaSuspensions.length == 1) await _mediaRuntime.suspend();
  }

  Future<void> _removeLegacyMediaSuspension(String owner) async {
    if (!_legacyMediaSuspensions.remove(owner)) return;
    if (_legacyMediaSuspensions.isEmpty) await _mediaRuntime.resume();
  }

  Future<void> _publishMediaDemand({
    bool forceNone = false,
    MediaResourceDemand? demandOverride,
  }) async {
    final callback = _onMediaDemandChanged;
    if (callback == null) return;
    final demand = forceNone
        ? MediaResourceDemand.none
        : demandOverride ??
            MediaResourceDemand(
              video: _mediaRuntime.videoActive ||
                  _resources.externalVideoClients > 0,
              audio: _mediaRuntime.audioActive ||
                  _resources.externalAudioClients > 0,
              serviceVideoCapture: _mediaRuntime.videoActive,
              serviceAudioCapture: _mediaRuntime.audioActive,
            );
    await callback(demand);
  }

  bool _hasCompetingLegacyDemand(
    String clientId,
    StreamSessionOptions requested,
  ) {
    final otherSessions = _activeSessions.entries.where(
      (entry) => entry.key != clientId,
    );
    final videoConflict = requested.video &&
        (_resources.localPreviewActive ||
            _resources.wantsMotionDetection ||
            otherSessions.any((entry) => entry.value.video));
    final audioConflict = requested.audio &&
        (_resources.wantsCryDetection ||
            otherSessions.any((entry) => entry.value.audio));
    return videoConflict || audioConflict;
  }
}
