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
  ClientRuntimeState _state = const ClientRuntimeState(phase: ClientRuntimePhase.unpaired);

  ClientRuntimeState get currentState => _state;
  Stream<ClientRuntimeState> get states => _states.stream;

  Future<void> pairWithServer(PairingPayload payload) async {
    _emit(ClientRuntimeState(phase: ClientRuntimePhase.pairing, session: _state.session));
    final session = await _pair(payload);
    _emit(ClientRuntimeState(phase: ClientRuntimePhase.pairedIdle, session: session));
  }

  Future<void> renewTokenIfNeeded({DateTime? now}) async {
    final session = _state.session;
    if (session == null || !session.shouldRenew(now ?? DateTime.now())) return;
    _emit(ClientRuntimeState(phase: ClientRuntimePhase.renewingToken, session: session));
    final renewed = await _renew?.call(session);
    _emit(ClientRuntimeState(phase: ClientRuntimePhase.pairedIdle, session: renewed ?? session));
  }

  Future<void> startWatching({bool audioEnabled = false}) async {
    await _startStream?.call();
    _emit(ClientRuntimeState(phase: ClientRuntimePhase.watching, session: _state.session));
  }

  Future<void> stopWatching() async {
    await _stopStream?.call();
    _emit(ClientRuntimeState(phase: ClientRuntimePhase.pairedIdle, session: _state.session));
  }

  Future<void> startAlertListening() async {
    await _startAlerts?.call();
    _emit(ClientRuntimeState(phase: ClientRuntimePhase.alertOnly, session: _state.session));
  }

  Future<void> stopAlertListening() async {
    await _stopAlerts?.call();
    _emit(ClientRuntimeState(phase: ClientRuntimePhase.pairedIdle, session: _state.session));
  }

  Future<void> clearPairing() async {
    await stopWatching();
    await stopAlertListening();
    await _clearStore?.call();
    _emit(const ClientRuntimeState(phase: ClientRuntimePhase.unpaired));
  }

  Future<void> dispose() async {
    await stopWatching();
    await stopAlertListening();
    await _states.close();
  }

  void _emit(ClientRuntimeState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
