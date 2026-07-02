import 'dart:async';

import '../../core/media/adaptive_media_profile.dart';
import '../../core/protocol/alert_event_dto.dart';
import '../../core/protocol/pairing_payload.dart';
import '../../core/protocol/pairing_session.dart';
import '../../services/monetization/broadcast_access_service.dart';
import 'alerts/client_alert_history.dart';
import 'media/active_stream_session.dart';
import 'media/client_stream_health_state.dart';

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
    Future<void> Function()? clearStore,
    ClientAlertHistory? alertHistory,
    this.streamHealthState,
    BroadcastAccessService? broadcastAccess,
  })  : _pair = pair,
        _renew = renew,
        _startStream = startStream,
        _stopStream = stopStream,
        _watchNetworkQuality = watchNetworkQuality,
        _startAlerts = startAlerts,
        _stopAlerts = stopAlerts,
        _clearStore = clearStore,
        _broadcastAccess = broadcastAccess,
        alertHistory = alertHistory ?? ClientAlertHistory();

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
  final BroadcastAccessService? _broadcastAccess;
  final ClientAlertHistory alertHistory;
  final ClientStreamHealthState? streamHealthState;
  final _states = StreamController<ClientRuntimeState>.broadcast();
  ClientRuntimeState _state =
      const ClientRuntimeState(phase: ClientRuntimePhase.unpaired);
  StreamSubscription<NetworkQualityUpdate>? _networkQualitySubscription;
  Timer? _broadcastAccessTimer;
  bool _disposed = false;

  ClientRuntimeState get currentState => _state;
  Stream<ClientRuntimeState> get states => _states.stream;
  List<AlertEventDto> get alerts => alertHistory.alerts;
  Stream<List<AlertEventDto>> get alertUpdates => alertHistory.changes;

  Future<void> recordAlert(AlertEventDto alert) => alertHistory.add(alert);
  Future<void> loadAlertHistory() => alertHistory.load();
  Future<void> clearAlertHistory() => alertHistory.clear();

  Future<void> refreshBroadcastAccess() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    _emit(_copyState(broadcastAccess: await access.snapshot()));
  }

  Future<void> unlockBroadcastAccess() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    final snapshot = await access.unlockWithOneTimePurchase();
    _emit(_copyState(broadcastAccess: snapshot, clearError: true));
  }

  Future<void> restoreBroadcastAccessPurchase() async {
    final access = _broadcastAccess;
    if (access == null || _disposed) return;
    final snapshot = await access.restorePurchase();
    _emit(_copyState(broadcastAccess: snapshot, clearError: true));
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
    if (session.shouldRenew(DateTime.now())) {
      await renewTokenIfNeeded();
    }
  }

  Future<void> pairWithServer(PairingPayload payload) async {
    if (_disposed) return;
    final previousSession = _state.session;
    _emit(_copyState(
      phase: ClientRuntimePhase.pairing,
      session: previousSession,
      clearActiveStream: true,
    ));
    late final PairingSession session;
    try {
      session = await _pair(payload);
    } catch (error) {
      if (!_disposed) {
        _emit(ClientRuntimeState(
          phase: ClientRuntimePhase.error,
          session: previousSession,
          error: error,
          broadcastAccess: _state.broadcastAccess,
        ));
      }
      rethrow;
    }
    if (_disposed) return;
    final mediaProfile = MediaQualityProfile.fromJson(
        session.payload.capabilities['mediaProfile']);
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.pairedIdle,
      session: session,
      mediaProfile: mediaProfile,
      broadcastAccess: _state.broadcastAccess,
    ));
    _startNetworkQuality(session);
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
  }

  Future<void> startWatching({bool audioEnabled = false}) async {
    if (_disposed || _state.session == null) return;
    final session = _state.session!;
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
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.watching,
      session: session,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: activeStream?.copyWith(audioEnabled: audioEnabled),
      alertsActive: _state.alertsActive,
      broadcastAccess: accessSnapshot ?? _state.broadcastAccess,
    ));
    _scheduleBroadcastAccessTimer(accessSnapshot);
  }

  Future<void> restartWatching({bool audioEnabled = false}) async {
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
    await startWatching(audioEnabled: audioEnabled);
  }

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

  Future<void> stopWatching() async {
    final session = _state.session;
    if (session != null && _state.activeStream != null) {
      await _stopStream?.call(session);
    }
    final accessSnapshot = await _broadcastAccess?.endSession('client.watch');
    _broadcastAccessTimer?.cancel();
    if (_disposed) return;
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
    if (_state.activeStream != null) {
      try {
        await _stopStream?.call(session);
      } catch (_) {}
    }
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
    await _networkQualitySubscription?.cancel();
    final session = _state.session;
    if (session != null && _state.activeStream != null) {
      await _stopStream?.call(session);
    }
    await _broadcastAccess?.endAllSessions();
    _broadcastAccessTimer?.cancel();
    await _stopAlerts?.call();
    await alertHistory.dispose();
    await _broadcastAccess?.dispose();
    await _states.close();
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
    if (_disposed || _state.activeStream == null) return;
    await stopWatching();
    final snapshot = await _broadcastAccess?.snapshot();
    if (_disposed || snapshot == null || !snapshot.isLocked) return;
    _emit(_copyState(
      phase: ClientRuntimePhase.pairedIdle,
      error: BroadcastAccessLockedException(snapshot),
      broadcastAccess: snapshot,
      clearActiveStream: true,
    ));
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
}
