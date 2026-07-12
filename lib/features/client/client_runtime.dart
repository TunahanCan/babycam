import 'dart:async';

import '../../core/media/adaptive_media_profile.dart';
import '../../core/protocol/alert_event_dto.dart';
import '../../core/protocol/pairing_payload.dart';
import '../../core/protocol/pairing_session.dart';
import '../../services/monetization/broadcast_access_service.dart';
import '../../services/discovery/mimicam_service_discovery.dart';
import 'alerts/client_alert_history.dart';
import 'controls/client_room_controls.dart';
import 'media/active_stream_session.dart';
import 'media/client_stream_health_state.dart';
import 'pairing/pairing_failure.dart';

class ClientRuntimeState {
  const ClientRuntimeState({
    required this.phase,
    this.session,
    this.error,
    this.networkQuality,
    this.mediaProfile,
    this.activeStream,
    this.alertsActive = false,
    this.broadcastAccess,
  });

  final ClientRuntimePhase phase;
  final PairingSession? session;
  final Object? error;
  final NetworkQualitySnapshot? networkQuality;
  final MediaQualityProfile? mediaProfile;
  final ActiveStreamSession? activeStream;
  final bool alertsActive;
  final BroadcastAccessSnapshot? broadcastAccess;
}

enum ClientRuntimePhase {
  unpaired,
  scanningQr,
  pairing,
  pairedIdle,
  renewingToken,
  watching,
  alertOnly,
  reconnecting,
  offline,
  revoked,
  error,
}

class ClientRuntime {
  ClientRuntime({
    required Future<PairingSession> Function(PairingPayload payload) pair,
    Future<PairingSession?> Function(PairingSession session)? renew,
    Future<ActiveStreamSession?> Function(
      PairingSession session, {
      bool audioEnabled,
    })? startStream,
    Future<void> Function(PairingSession session)? stopStream,
    Stream<NetworkQualityUpdate> Function(PairingSession session)?
        watchNetworkQuality,
    Future<bool> Function(PairingSession session)? startAlerts,
    Future<void> Function()? stopAlerts,
    Stream<bool>? alertConnectionStates,
    Future<void> Function()? clearStore,
    Stream<PairingSession> Function(PairingSession session)?
        watchSessionEndpoints,
    Future<void> Function(PairingSession session)? persistReboundSession,
    Future<BroadcastAccessSnapshot?> Function(PairingSession session)?
        refreshRemoteBroadcastAccess,
    ClientAlertHistory? alertHistory,
    this.streamHealthState,
    this.roomControls,
    this.serviceBrowser,
    BroadcastAccessService? broadcastAccess,
  })  : _pair = pair,
        _renew = renew,
        _startStream = startStream,
        _stopStream = stopStream,
        _watchNetworkQuality = watchNetworkQuality,
        _startAlerts = startAlerts,
        _stopAlerts = stopAlerts,
        _clearStore = clearStore,
        _watchSessionEndpoints = watchSessionEndpoints,
        _persistReboundSession = persistReboundSession,
        _refreshRemoteBroadcastAccess = refreshRemoteBroadcastAccess,
        _broadcastAccess = broadcastAccess,
        alertHistory = alertHistory ?? ClientAlertHistory() {
    _alertConnectionSubscription =
        alertConnectionStates?.distinct().listen(_setAlertTransportConnected);
  }

  final Future<PairingSession> Function(PairingPayload payload) _pair;
  final Future<PairingSession?> Function(PairingSession session)? _renew;
  final Future<ActiveStreamSession?> Function(
    PairingSession session, {
    bool audioEnabled,
  })? _startStream;
  final Future<void> Function(PairingSession session)? _stopStream;
  final Stream<NetworkQualityUpdate> Function(PairingSession session)?
      _watchNetworkQuality;
  final Future<bool> Function(PairingSession session)? _startAlerts;
  final Future<void> Function()? _stopAlerts;
  final Future<void> Function()? _clearStore;
  final Stream<PairingSession> Function(PairingSession session)?
      _watchSessionEndpoints;
  final Future<void> Function(PairingSession session)? _persistReboundSession;
  final Future<BroadcastAccessSnapshot?> Function(PairingSession session)?
      _refreshRemoteBroadcastAccess;
  final BroadcastAccessService? _broadcastAccess;
  final ClientAlertHistory alertHistory;
  final ClientStreamHealthState? streamHealthState;
  final ClientRoomControls? roomControls;
  final MimiCamServiceBrowser? serviceBrowser;
  final _states = StreamController<ClientRuntimeState>.broadcast();
  ClientRuntimeState _state =
      const ClientRuntimeState(phase: ClientRuntimePhase.unpaired);
  StreamSubscription<NetworkQualityUpdate>? _networkQualitySubscription;
  StreamSubscription<PairingSession>? _endpointSubscription;
  StreamSubscription<bool>? _alertConnectionSubscription;
  Timer? _broadcastAccessTimer;
  PairingSession? _activeStreamOwnerSession;
  Future<void>? _pairingOperation;
  Future<void> _watchTail = Future<void>.value();
  Future<void> _endpointRebindTail = Future<void>.value();
  int _endpointGeneration = 0;
  int _broadcastAccessTimerGeneration = 0;
  int _watchPresentationGeneration = 0;
  bool _disposed = false;
  bool _alertTransportConnected = false;

  ClientRuntimeState get currentState => _state;
  bool get alertTransportConnected => _alertTransportConnected;
  Stream<ClientRuntimeState> get states => Stream<ClientRuntimeState>.multi(
        (controller) {
          controller.add(_state);
          final subscription = _states.stream.listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
          controller.onCancel = subscription.cancel;
        },
      );
  List<AlertEventDto> get alerts => alertHistory.alerts;
  Stream<List<AlertEventDto>> get alertUpdates => alertHistory.changes;
  List<MimiCamDiscoveredService> get discoveredServices =>
      serviceBrowser?.services ?? const [];
  Stream<List<MimiCamDiscoveredService>> get discoveryUpdates =>
      serviceBrowser?.updates ?? const Stream.empty();
  bool get canManageBroadcastPurchase => _broadcastAccess != null;

  /// Claims ownership of watch/alert presentation transitions for one screen.
  /// A later screen claim invalidates delayed teardown work from the previous
  /// screen without canceling the new stream.
  int claimWatchPresentation() => ++_watchPresentationGeneration;

  bool isWatchPresentationCurrent(int generation) =>
      !_disposed && generation == _watchPresentationGeneration;

  Future<void> releaseWatchPresentation(int generation) =>
      _enqueueWatch(() async {
        if (!isWatchPresentationCurrent(generation)) return;
        final alertsWereActive = _state.alertsActive;
        await _stopWatchingUnlocked();
        if (!isWatchPresentationCurrent(generation) ||
            !alertsWereActive ||
            _state.alertsActive ||
            _state.session == null ||
            _state.activeStream != null) {
          return;
        }
        await startAlertListening();
      });

  Future<void> startDiscovery() async {
    await serviceBrowser?.start();
  }

  Future<void> stopDiscovery() async {
    await serviceBrowser?.stop();
  }

  Future<void> recordAlert(AlertEventDto alert) => alertHistory.add(alert);
  Future<void> loadAlertHistory() => alertHistory.load();
  Future<void> clearAlertHistory() => alertHistory.clear();

  Future<void> refreshBroadcastAccess() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    final snapshot = await access.snapshot();
    _emit(_copyState(broadcastAccess: snapshot));
    if (_state.activeStream != null) _scheduleBroadcastAccessTimer(snapshot);
  }

  Future<void> unlockBroadcastAccess() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    _cancelBroadcastAccessTimer();
    try {
      final snapshot = await access.unlockWithOneTimePurchase();
      _emit(_copyState(broadcastAccess: snapshot, clearError: true));
      if (_state.activeStream != null) _scheduleBroadcastAccessTimer(snapshot);
    } catch (_) {
      if (!_disposed && _state.activeStream != null) {
        _scheduleBroadcastAccessTimer(await access.snapshot());
      }
      rethrow;
    }
  }

  Future<void> restoreBroadcastAccessPurchase() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    _cancelBroadcastAccessTimer();
    try {
      final snapshot = await access.restorePurchase();
      _emit(_copyState(broadcastAccess: snapshot, clearError: true));
      if (_state.activeStream != null) _scheduleBroadcastAccessTimer(snapshot);
    } catch (_) {
      if (!_disposed && _state.activeStream != null) {
        _scheduleBroadcastAccessTimer(await access.snapshot());
      }
      rethrow;
    }
  }

  Future<void> restoreSession(PairingSession session) async {
    if (_disposed) return;
    final mediaProfile = MediaQualityProfile.fromJson(
      session.payload.capabilities['mediaProfile'],
    );
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.pairedIdle,
      session: session,
      mediaProfile: mediaProfile,
      broadcastAccess: _state.broadcastAccess,
    ));
    _startNetworkQuality(session);
    await _startEndpointResolution(session);
    if (session.shouldRenew(DateTime.now())) {
      await renewTokenIfNeeded();
    }
  }

  Future<void> pairWithServer(PairingPayload payload) {
    if (_disposed) return Future<void>.value();
    if (_pairingOperation != null) {
      return Future<void>.error(
        const PairingFailure(PairingFailureCode.pairingInProgress),
      );
    }
    late final Future<void> operation;
    operation = _pairWithServer(payload).whenComplete(() {
      if (identical(_pairingOperation, operation)) {
        _pairingOperation = null;
      }
    });
    _pairingOperation = operation;
    return operation;
  }

  Future<void> _pairWithServer(PairingPayload payload) async {
    if (payload.isExpired) {
      throw const PairingFailure(PairingFailureCode.payloadExpired);
    }
    final previousState = _state;
    _emit(_copyState(
      phase: ClientRuntimePhase.pairing,
      clearError: true,
    ));
    late final PairingSession session;
    try {
      session = await _pair(payload);
    } catch (error) {
      if (!_disposed) {
        // A second QR attempt must not blank a healthy room view or its
        // alerts. The caller receives the actionable error for the banner.
        if (previousState.session != null) {
          _emit(previousState);
        } else {
          _emit(ClientRuntimeState(
            phase: ClientRuntimePhase.error,
            error: error,
            broadcastAccess: previousState.broadcastAccess,
          ));
        }
      }
      rethrow;
    }
    if (_disposed) return;
    if (previousState.session != null) {
      await _releasePreviousRoomForReplacement(previousState);
    }
    if (_disposed) return;
    if (previousState.session?.deviceId != session.deviceId) {
      // Alerts describe the child in the paired room. Do not show a new
      // caregiver the previous room's history after switching devices.
      await alertHistory.clear();
    }
    final mediaProfile = MediaQualityProfile.fromJson(
        session.payload.capabilities['mediaProfile']);
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.pairedIdle,
      session: session,
      mediaProfile: mediaProfile,
      broadcastAccess: _state.broadcastAccess,
    ));
    _startNetworkQuality(session);
    await _startEndpointResolution(session);
  }

  Future<void> _releasePreviousRoomForReplacement(
    ClientRuntimeState previousState,
  ) async {
    await _networkQualitySubscription?.cancel();
    _networkQualitySubscription = null;
    await _cancelEndpointResolution();
    await _enqueueWatch(() async {
      final previousSession = previousState.session;
      if (previousSession != null && previousState.activeStream != null) {
        try {
          await _stopStream?.call(_activeStreamOwnerSession ?? previousSession);
        } catch (_) {
          // The replacement session remains usable even when the old room is
          // already unreachable.
        }
      }
      _activeStreamOwnerSession = null;
      _cancelBroadcastAccessTimer();
      await _broadcastAccess?.endSession('client.watch');
      streamHealthState?.setWatchActive(false);
    });
    try {
      // Stop unconditionally: an alert subscription may still be connecting
      // even when the old immutable state has not flipped to active yet.
      await _stopAlerts?.call();
    } catch (_) {
      // A stale WebSocket must never prevent a fresh pairing.
    }
    _setAlertTransportConnected(false);
  }

  Future<void> renewTokenIfNeeded({DateTime? now}) async {
    if (_disposed) return;
    final renew = _renew;
    if (renew == null) return;
    final session = _state.session;
    if (session == null || !session.shouldRenew(now ?? DateTime.now())) return;
    _emit(_copyState(phase: ClientRuntimePhase.renewingToken));
    final renewed = await renew(session);
    if (_disposed) return;
    if (renewed == null) {
      await _handleRevokedSession(session);
      return;
    }
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.pairedIdle,
      session: renewed,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: _state.activeStream,
      alertsActive: _state.alertsActive,
      broadcastAccess: _state.broadcastAccess,
    ));
    _startNetworkQuality(renewed);
    await _startEndpointResolution(renewed);
  }

  Future<void> startWatching({bool audioEnabled = false}) =>
      _enqueueWatch(() => _startWatchingUnlocked(audioEnabled: audioEnabled));

  Future<void> _startWatchingUnlocked({bool audioEnabled = false}) async {
    if (_disposed || _state.session == null) return;
    final session = _state.session!;
    // Keep the event WebSocket independent from the media transport. When the
    // server cannot analyze alongside WebRTC it rejects the pilot and the
    // stream controller falls back to MJPEG/WAV; dropping alerts here instead
    // silently disabled iOS notifications throughout live viewing.
    if (_state.activeStream != null) {
      try {
        await _stopStream?.call(_activeStreamOwnerSession ?? session);
      } catch (_) {
        // Starting a replacement must not retain the previous transport.
      }
      _activeStreamOwnerSession = null;
      streamHealthState?.setWatchActive(false);
    }
    final access = _broadcastAccess;
    BroadcastAccessSnapshot? accessSnapshot;
    const accessSessionId = 'client.watch';
    if (access != null) {
      try {
        accessSnapshot = await access.beginSession(accessSessionId);
      } on BroadcastAccessLockedException catch (error) {
        if (!_disposed) {
          _emit(ClientRuntimeState(
            phase: ClientRuntimePhase.pairedIdle,
            session: session,
            error: error,
            networkQuality: _state.networkQuality,
            mediaProfile: _state.mediaProfile,
            alertsActive: _state.alertsActive,
            broadcastAccess: error.snapshot,
          ));
        }
        rethrow;
      }
    }
    late final ActiveStreamSession? activeStream;
    try {
      activeStream = await _startStream?.call(
        session,
        audioEnabled: audioEnabled,
      );
    } catch (error) {
      if (access != null) {
        accessSnapshot = await access.endSession(accessSessionId);
      }
      if (!_disposed) {
        if (error is BroadcastAccessLockedException) {
          _emit(ClientRuntimeState(
            phase: ClientRuntimePhase.pairedIdle,
            session: session,
            error: error,
            networkQuality: _state.networkQuality,
            mediaProfile: _state.mediaProfile,
            alertsActive: _state.alertsActive,
            broadcastAccess: error.snapshot,
          ));
          rethrow;
        }
        _emit(ClientRuntimeState(
          phase: ClientRuntimePhase.error,
          session: session,
          error: error,
          networkQuality: _state.networkQuality,
          mediaProfile: _state.mediaProfile,
          alertsActive: _state.alertsActive,
          broadcastAccess: accessSnapshot ?? _state.broadcastAccess,
        ));
      }
      rethrow;
    }
    if (_disposed) {
      await _stopStream?.call(session);
      await access?.endSession(accessSessionId);
      return;
    }
    _activeStreamOwnerSession = activeStream == null ? null : session;
    final authoritativeAccess = accessSnapshot ?? activeStream?.broadcastAccess;
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.watching,
      session: session,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: activeStream?.copyWith(audioEnabled: audioEnabled),
      alertsActive: _state.alertsActive,
      broadcastAccess: authoritativeAccess ?? _state.broadcastAccess,
    ));
    _scheduleBroadcastAccessTimer(authoritativeAccess);
  }

  Future<void> restartWatching({bool audioEnabled = false}) =>
      _enqueueWatch(() async {
        if (_disposed || _state.session == null) return;
        _emit(ClientRuntimeState(
          phase: ClientRuntimePhase.reconnecting,
          session: _state.session,
          networkQuality: _state.networkQuality,
          mediaProfile: _state.mediaProfile,
          activeStream: _state.activeStream,
          alertsActive: _state.alertsActive,
          broadcastAccess: _state.broadcastAccess,
        ));
        await _stopWatchingUnlocked(emitState: false, endAccess: false);
        await _startWatchingUnlocked(audioEnabled: audioEnabled);
      });

  void reportStreamFailure(Object error) {
    if (_disposed) return;
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.error,
      session: _state.session,
      error: error,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: _state.activeStream,
      alertsActive: _state.alertsActive,
      broadcastAccess: _state.broadcastAccess,
    ));
  }

  Future<void> stopWatching() => _enqueueWatch(() => _stopWatchingUnlocked());

  Future<void> _stopWatchingUnlocked({
    bool emitState = true,
    bool endAccess = true,
  }) async {
    final session = _state.session;
    final ownerSession = _activeStreamOwnerSession ?? session;
    if (session != null && _state.activeStream != null) {
      try {
        if (ownerSession != null) await _stopStream?.call(ownerSession);
      } catch (error) {
        if (!_disposed && emitState) reportStreamFailure(error);
      }
    }
    _activeStreamOwnerSession = null;
    final accessSnapshot = endAccess
        ? await _broadcastAccess?.endSession('client.watch')
        : _state.broadcastAccess;
    _cancelBroadcastAccessTimer();
    streamHealthState?.setWatchActive(false);
    if (_disposed || !emitState) {
      if (!_disposed && !emitState) {
        _emit(_copyState(
          phase: ClientRuntimePhase.reconnecting,
          clearActiveStream: true,
          broadcastAccess: accessSnapshot,
        ));
      }
      return;
    }
    _emit(ClientRuntimeState(
      phase: _state.alertsActive
          ? ClientRuntimePhase.alertOnly
          : ClientRuntimePhase.pairedIdle,
      session: session,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: null,
      alertsActive: _state.alertsActive,
      broadcastAccess: accessSnapshot ?? _state.broadcastAccess,
    ));
  }

  Future<bool> startAlertListening() async {
    if (_disposed || _state.session == null) return false;
    final session = _state.session!;
    try {
      final started = await _startAlerts?.call(session) ?? false;
      if (!started) {
        if (!_disposed) {
          _emit(ClientRuntimeState(
            phase: _state.activeStream == null
                ? ClientRuntimePhase.pairedIdle
                : ClientRuntimePhase.watching,
            session: _state.session,
            networkQuality: _state.networkQuality,
            mediaProfile: _state.mediaProfile,
            activeStream: _state.activeStream,
            alertsActive: false,
            broadcastAccess: _state.broadcastAccess,
          ));
        }
        return false;
      }
    } catch (error) {
      if (!_disposed) {
        _emit(ClientRuntimeState(
          phase: ClientRuntimePhase.error,
          session: session,
          error: error,
          networkQuality: _state.networkQuality,
          mediaProfile: _state.mediaProfile,
          activeStream: _state.activeStream,
          alertsActive: false,
          broadcastAccess: _state.broadcastAccess,
        ));
      }
      rethrow;
    }
    if (_disposed) {
      await _stopAlerts?.call();
      return false;
    }
    _emit(ClientRuntimeState(
      phase: _state.activeStream == null
          ? ClientRuntimePhase.alertOnly
          : ClientRuntimePhase.watching,
      session: _state.session,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: _state.activeStream,
      alertsActive: true,
      broadcastAccess: _state.broadcastAccess,
    ));
    return true;
  }

  Future<void> stopAlertListening() async {
    await _stopAlerts?.call();
    _setAlertTransportConnected(false);
    if (_disposed) return;
    _emit(ClientRuntimeState(
      phase: _state.activeStream == null
          ? ClientRuntimePhase.pairedIdle
          : ClientRuntimePhase.watching,
      session: _state.session,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: _state.activeStream,
      alertsActive: false,
      broadcastAccess: _state.broadcastAccess,
    ));
  }

  Future<void> clearPairing() async {
    if (_disposed) return;
    await stopWatching();
    await stopAlertListening();
    await _networkQualitySubscription?.cancel();
    _networkQualitySubscription = null;
    await _cancelEndpointResolution();
    await _clearStore?.call();
    await alertHistory.clear();
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.unpaired,
      broadcastAccess: _state.broadcastAccess,
    ));
  }

  Future<void> _handleRevokedSession(PairingSession session) async {
    await _networkQualitySubscription?.cancel();
    _networkQualitySubscription = null;
    await _cancelEndpointResolution();
    if (_state.activeStream != null) {
      try {
        await _stopStream?.call(_activeStreamOwnerSession ?? session);
      } catch (_) {}
    }
    _activeStreamOwnerSession = null;
    try {
      await _stopAlerts?.call();
    } catch (_) {}
    await _clearStore?.call();
    if (_disposed) return;
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.revoked,
      session: session,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      alertsActive: false,
      broadcastAccess: _state.broadcastAccess,
    ));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    const cleanupTimeout = Duration(seconds: 1);

    Future<void> attempt(FutureOr<void> Function() operation) async {
      try {
        await Future<void>.sync(() async {
          await operation();
        }).timeout(cleanupTimeout);
      } catch (_) {
        // Disposal must keep releasing independent transports when a platform
        // plugin or an in-flight DNS-SD/WebSocket operation does not answer.
      }
    }

    await attempt(() => _watchTail);
    await attempt(() async => _networkQualitySubscription?.cancel());
    await attempt(() async => _alertConnectionSubscription?.cancel());
    await attempt(_cancelEndpointResolution);
    final session = _state.session;
    if (session != null && _state.activeStream != null) {
      await attempt(
        () async => _stopStream?.call(_activeStreamOwnerSession ?? session),
      );
    }
    _activeStreamOwnerSession = null;
    await attempt(() async => _broadcastAccess?.endAllSessions());
    _cancelBroadcastAccessTimer();
    await attempt(() async => _stopAlerts?.call());
    await attempt(() async => roomControls?.dispose());
    await attempt(() async => serviceBrowser?.dispose());
    await attempt(alertHistory.dispose);
    await attempt(() async => _broadcastAccess?.dispose());
    await attempt(_states.close);
  }

  void _setAlertTransportConnected(bool connected) {
    if (_disposed || _alertTransportConnected == connected) return;
    _alertTransportConnected = connected;
    // Connection health is orthogonal to the user's armed preference. Emit
    // the current immutable state again so presentation can show reconnecting
    // without rewriting every runtime transition.
    if (!_states.isClosed) _states.add(_state);
  }

  void _startNetworkQuality(PairingSession session) {
    final watch = _watchNetworkQuality;
    if (watch == null) return;
    _networkQualitySubscription?.cancel();
    _networkQualitySubscription = watch(session).listen((update) {
      if (_disposed || _state.session != session) return;
      _emit(ClientRuntimeState(
        phase: _state.phase,
        session: _state.session,
        error: _state.error,
        networkQuality: update.snapshot,
        mediaProfile: update.serverProfile ?? _state.mediaProfile,
        activeStream: _state.activeStream,
        alertsActive: _state.alertsActive,
        broadcastAccess: _state.broadcastAccess,
      ));
    });
  }

  Future<void> _startEndpointResolution(PairingSession session) async {
    final watch = _watchSessionEndpoints;
    if (watch == null || _disposed) return;
    final generation = ++_endpointGeneration;
    final previous = _endpointSubscription;
    _endpointSubscription = null;
    await previous?.cancel();
    await _endpointRebindTail;
    if (_disposed || generation != _endpointGeneration) return;
    try {
      _endpointSubscription = watch(session).listen(
        (rebound) {
          final operation = _endpointRebindTail.then<void>(
            (_) => _enqueueWatch(
              () => _applyEndpointRebind(generation, rebound),
            ),
            onError: (_) => _enqueueWatch(
              () => _applyEndpointRebind(generation, rebound),
            ),
          );
          _endpointRebindTail = operation.then<void>((_) {}, onError: (_) {});
        },
        onError: (Object _) {},
      );
    } catch (_) {
      // Discovery is advisory; a watcher failure must not undo pairing.
    }
  }

  Future<void> _cancelEndpointResolution() async {
    _endpointGeneration++;
    final subscription = _endpointSubscription;
    _endpointSubscription = null;
    await subscription?.cancel();
    await _endpointRebindTail;
  }

  Future<void> _applyEndpointRebind(
    int generation,
    PairingSession rebound,
  ) async {
    if (_disposed || generation != _endpointGeneration) return;
    final current = _state.session;
    if (current == null ||
        current.deviceId != rebound.deviceId ||
        (current.host == rebound.host && current.port == rebound.port)) {
      return;
    }
    final resolved = rebound.copyWith(
      sessionToken: current.sessionToken,
      clientId: current.clientId,
      trustedClientTokenExpiresAtMs: current.trustedClientTokenExpiresAtMs,
      pairedAtMs: current.pairedAtMs,
    );
    try {
      await _persistReboundSession?.call(resolved);
    } catch (_) {
      // Reachability wins over a best-effort metadata persistence failure.
    }
    if (_disposed || generation != _endpointGeneration) return;
    final alertsWereActive = _state.alertsActive;
    _emit(ClientRuntimeState(
      phase: _state.phase,
      session: resolved,
      error: _state.error,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: _state.activeStream,
      alertsActive: alertsWereActive,
      broadcastAccess: _state.broadcastAccess,
    ));
    _startNetworkQuality(resolved);
    if (!alertsWereActive) return;
    try {
      await _stopAlerts?.call();
      if (_disposed || generation != _endpointGeneration) return;
      final started = await _startAlerts?.call(resolved) ?? false;
      if (!started && !_disposed && generation == _endpointGeneration) {
        _emit(_copyState(alertsActive: false));
      }
    } catch (error) {
      if (!_disposed && generation == _endpointGeneration) {
        _emit(_copyState(error: error, alertsActive: false));
      }
    }
  }

  void _scheduleBroadcastAccessTimer(BroadcastAccessSnapshot? snapshot) {
    _cancelBroadcastAccessTimer();
    final streamToken = _state.activeStream?.streamToken;
    if (snapshot == null ||
        snapshot.unlocked ||
        !snapshot.active ||
        snapshot.remainingMs <= 0 ||
        streamToken == null) {
      return;
    }
    _armBroadcastAccessTimer(snapshot.remaining, streamToken);
  }

  void _armBroadcastAccessTimer(Duration delay, String streamToken) {
    final generation = _broadcastAccessTimerGeneration;
    _broadcastAccessTimer = Timer(delay, () {
      unawaited(_handleBroadcastAccessExpired(generation, streamToken));
    });
  }

  void _cancelBroadcastAccessTimer() {
    _broadcastAccessTimerGeneration++;
    _broadcastAccessTimer?.cancel();
    _broadcastAccessTimer = null;
  }

  Future<void> _handleBroadcastAccessExpired(
    int generation,
    String streamToken,
  ) =>
      _enqueueWatch(() async {
        if (!_isCurrentBroadcastTimer(generation, streamToken)) return;
        final session = _state.session;
        if (session == null) return;

        BroadcastAccessSnapshot? snapshot;
        try {
          snapshot = await _broadcastAccess?.snapshot() ??
              await _refreshRemoteBroadcastAccess?.call(session);
        } catch (_) {
          if (_isCurrentBroadcastTimer(generation, streamToken)) {
            _armBroadcastAccessTimer(const Duration(seconds: 1), streamToken);
          }
          return;
        }
        if (!_isCurrentBroadcastTimer(generation, streamToken)) return;
        if (snapshot == null) {
          // A stale session-start snapshot is never sufficient authority to
          // tear down a newer stream. Retry until the room server can answer.
          _armBroadcastAccessTimer(const Duration(seconds: 1), streamToken);
          return;
        }
        if (!snapshot.isLocked) {
          _emit(_copyState(
            broadcastAccess: snapshot,
            clearError: snapshot.unlocked,
          ));
          _scheduleBroadcastAccessTimer(snapshot);
          return;
        }

        await _stopWatchingUnlocked();
        if (_disposed) return;
        _emit(_copyState(
          phase: ClientRuntimePhase.pairedIdle,
          error: BroadcastAccessLockedException(snapshot),
          broadcastAccess: snapshot,
          clearActiveStream: true,
        ));
      });

  bool _isCurrentBroadcastTimer(int generation, String streamToken) {
    return !_disposed &&
        generation == _broadcastAccessTimerGeneration &&
        _state.activeStream?.streamToken == streamToken;
  }

  ClientRuntimeState _copyState({
    ClientRuntimePhase? phase,
    PairingSession? session,
    Object? error,
    NetworkQualitySnapshot? networkQuality,
    MediaQualityProfile? mediaProfile,
    ActiveStreamSession? activeStream,
    bool? alertsActive,
    BroadcastAccessSnapshot? broadcastAccess,
    bool clearError = false,
    bool clearActiveStream = false,
  }) =>
      ClientRuntimeState(
        phase: phase ?? _state.phase,
        session: session ?? _state.session,
        error: clearError ? null : error ?? _state.error,
        networkQuality: networkQuality ?? _state.networkQuality,
        mediaProfile: mediaProfile ?? _state.mediaProfile,
        activeStream:
            clearActiveStream ? null : activeStream ?? _state.activeStream,
        alertsActive: alertsActive ?? _state.alertsActive,
        broadcastAccess: broadcastAccess ?? _state.broadcastAccess,
      );

  void _emit(ClientRuntimeState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> _enqueueWatch(Future<void> Function() operation) {
    final next = _watchTail.then<void>(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _watchTail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}
