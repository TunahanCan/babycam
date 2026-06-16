import '../../../core/protocol/pairing_payload.dart';
import '../client_runtime.dart';

class ClientPairingFlow {
  const ClientPairingFlow(this._runtime);

  final ClientRuntime _runtime;

  Future<void> pairAndArmAlerts(PairingPayload payload) async {
    await _runtime.pairWithServer(payload);
    await _runtime.startAlertListening();
  }
}
