import 'dart:async';

import '../../core/media/adaptive_media_profile.dart';
import '../../core/protocol/pairing_payload.dart';
import '../../core/protocol/pairing_session.dart';
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
  });

  final ClientRuntimePhase phase;
  final PairingSession? session;
  final Object? error;
  final NetworkQualitySnapshot? networkQuality;
  final MediaQualityProfile? mediaProfile;
  final ActiveStreamSession? activeStream;
  final bool alertsActive;
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
    this.streamHealthState,
  })  : _pair = pair,
        _renew = renew,
        _startStream = startStream,
        _stopStream = stopStream,
        _watchNetworkQuality = watchNetworkQuality,
        _startAlerts = startAlerts,
        _stopAlerts = stopAlerts,
        _clearStore = clearStore;

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
  final ClientStreamHealthState? streamHealthState;
  final _states = StreamController<ClientRuntimeState>.broadcast();
  ClientRuntimeState _state =
      const ClientRuntimeState(phase: ClientRuntimePhase.unpaired);
  StreamSubscription<NetworkQualityUpdate>? _networkQualitySubscription;
  bool _disposed = false;

  ClientRuntimeState get currentState => _state;
  Stream<ClientRuntimeState> get states => _states.stream;

  Future<void> pairWithServer(PairingPayload payload) async {
    if (_disposed) return;
    final previousSession = _state.session;
    _emit(ClientRuntimeState(
        phase: ClientRuntimePhase.pairing, session: previousSession));
    late final PairingSession session;
    try {
      session = await _pair(payload);
    } catch (error) {
      if (!_disposed) {
        _emit(ClientRuntimeState(
          phase: ClientRuntimePhase.error,
          session: previousSession,
          error: error,
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
    ));
    _startNetworkQuality(session);
  }

  Future<void> renewTokenIfNeeded({DateTime? now}) async {
    if (_disposed) return;
    final session = _state.session;
    if (session == null || !session.shouldRenew(now ?? DateTime.now())) return;
    _emit(ClientRuntimeState(
        phase: ClientRuntimePhase.renewingToken, session: session));
    final renewed = await _renew?.call(session);
    if (_disposed) return;
    final nextSession = renewed ?? session;
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.pairedIdle,
      session: nextSession,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: _state.activeStream,
      alertsActive: _state.alertsActive,
    ));
    _startNetworkQuality(nextSession);
  }

  Future<void> startWatching({bool audioEnabled = false}) async {
    if (_disposed || _state.session == null) return;
    final session = _state.session!;
    late final ActiveStreamSession? activeStream;
    try {
      activeStream = await _startStream?.call(
        session,
        audioEnabled: audioEnabled,
      );
    } catch (error) {
      if (!_disposed) {
        _emit(ClientRuntimeState(
          phase: ClientRuntimePhase.error,
          session: session,
          error: error,
          networkQuality: _state.networkQuality,
          mediaProfile: _state.mediaProfile,
          alertsActive: _state.alertsActive,
        ));
      }
      rethrow;
    }
    if (_disposed) {
      await _stopStream?.call(session);
      return;
    }
    _emit(ClientRuntimeState(
      phase: ClientRuntimePhase.watching,
      session: session,
      networkQuality: _state.networkQuality,
      mediaProfile: _state.mediaProfile,
      activeStream: activeStream?.copyWith(audioEnabled: audioEnabled),
      alertsActive: _state.alertsActive,
    ));
  }

  Future<void> stopWatching() async {
    final session = _state.session;
    if (session != null) await _stopStream?.call(session);
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
    ));
  }

  Future<void> clearPairing() async {
    if (_disposed) return;
    await stopWatching();
    await stopAlertListening();
    await _networkQualitySubscription?.cancel();
    _networkQualitySubscription = null;
    await _clearStore?.call();
    _emit(const ClientRuntimeState(phase: ClientRuntimePhase.unpaired));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _networkQualitySubscription?.cancel();
    final session = _state.session;
    if (session != null) await _stopStream?.call(session);
    await _stopAlerts?.call();
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
      ));
    });
  }

  void _emit(ClientRuntimeState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
