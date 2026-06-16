import 'dart:async';

import '../../core/protocol/pairing_payload.dart';
import '../../core/protocol/pairing_session.dart';

class ClientRuntimeState {
  const ClientRuntimeState({required this.phase, this.session, this.error});
  final ClientRuntimePhase phase;
  final PairingSession? session;
  final Object? error;
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
    Future<void> Function()? startStream,
    Future<void> Function()? stopStream,
    Future<void> Function()? startAlerts,
    Future<void> Function()? stopAlerts,
    Future<void> Function()? clearStore,
  })  : _pair = pair,
        _renew = renew,
        _startStream = startStream,
        _stopStream = stopStream,
        _startAlerts = startAlerts,
        _stopAlerts = stopAlerts,
        _clearStore = clearStore;

  final Future<PairingSession> Function(PairingPayload payload) _pair;
  final Future<PairingSession?> Function(PairingSession session)? _renew;
  final Future<void> Function()? _startStream;
  final Future<void> Function()? _stopStream;
  final Future<void> Function()? _startAlerts;
  final Future<void> Function()? _stopAlerts;
  final Future<void> Function()? _clearStore;
  final _states = StreamController<ClientRuntimeState>.broadcast();
  ClientRuntimeState _state =
      const ClientRuntimeState(phase: ClientRuntimePhase.unpaired);
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
    _emit(ClientRuntimeState(
        phase: ClientRuntimePhase.pairedIdle, session: session));
  }

  Future<void> renewTokenIfNeeded({DateTime? now}) async {
    if (_disposed) return;
    final session = _state.session;
    if (session == null || !session.shouldRenew(now ?? DateTime.now())) return;
    _emit(ClientRuntimeState(
        phase: ClientRuntimePhase.renewingToken, session: session));
    final renewed = await _renew?.call(session);
    if (_disposed) return;
    _emit(ClientRuntimeState(
        phase: ClientRuntimePhase.pairedIdle, session: renewed ?? session));
  }

  Future<void> startWatching({bool audioEnabled = false}) async {
    if (_disposed || _state.session == null) return;
    await _startStream?.call();
    if (_disposed) {
      await _stopStream?.call();
      return;
    }
    _emit(ClientRuntimeState(
        phase: ClientRuntimePhase.watching, session: _state.session));
  }

  Future<void> stopWatching() async {
    await _stopStream?.call();
    if (_disposed) return;
    _emit(ClientRuntimeState(
        phase: ClientRuntimePhase.pairedIdle, session: _state.session));
  }

  Future<void> startAlertListening() async {
    if (_disposed || _state.session == null) return;
    await _startAlerts?.call();
    if (_disposed) {
      await _stopAlerts?.call();
      return;
    }
    _emit(ClientRuntimeState(
        phase: ClientRuntimePhase.alertOnly, session: _state.session));
  }

  Future<void> stopAlertListening() async {
    await _stopAlerts?.call();
    if (_disposed) return;
    _emit(ClientRuntimeState(
        phase: ClientRuntimePhase.pairedIdle, session: _state.session));
  }

  Future<void> clearPairing() async {
    if (_disposed) return;
    await stopWatching();
    await stopAlertListening();
    await _clearStore?.call();
    _emit(const ClientRuntimeState(phase: ClientRuntimePhase.unpaired));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopStream?.call();
    await _stopAlerts?.call();
    await _states.close();
  }

  void _emit(ClientRuntimeState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
