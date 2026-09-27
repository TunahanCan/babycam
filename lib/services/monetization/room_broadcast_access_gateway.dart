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

/// Optional transport capability for releasing a parent role's active sockets.
/// The gateway remains reusable when that role is entered again.
abstract interface class CancelableRoomBroadcastAccessGateway {
  void cancelPendingRequests();
}
