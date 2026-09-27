import 'package:shared_preferences/shared_preferences.dart';

import '../features/client/media/remote_broadcast_access_client.dart';
import '../services/monetization/broadcast_access_service.dart';
import '../services/monetization/shared_preferences_pending_room_activation_repository.dart';
import 'broadcast_purchase_coordinator.dart';

/// The application owns one billing graph across room/parent role changes.
class BroadcastPurchaseCompositionRoot {
  const BroadcastPurchaseCompositionRoot._();

  static BroadcastPurchaseCoordinator create(SharedPreferences preferences) =>
      BroadcastPurchaseCoordinator(
        pendingActivations:
            SharedPreferencesPendingRoomActivationRepository(preferences),
        remote: RemoteBroadcastAccessClient(),
        access: BroadcastAccessService(preferences),
        clientActive: false,
      );
}
