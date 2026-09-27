import '../../core/protocol/pairing_session.dart';
import 'broadcast_access_models.dart';

/// Room control operations used by purchase delivery, independent of HTTP/UI.
abstract interface class RoomBroadcastAccessGateway {
  Future<BroadcastAccessSnapshot?> snapshot(PairingSession session);
  Future<bool> supportsActivation(PairingSession session);
  Future<String?> readLicense(PairingSession session);
  Future<BroadcastAccessSnapshot> activate(
      PairingSession session, String licenseToken);
}
