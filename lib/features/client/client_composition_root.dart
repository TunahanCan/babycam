import 'package:shared_preferences/shared_preferences.dart';

import 'alerts/client_alert_listener.dart';
import 'alerts/client_notification_service.dart';
import 'client_runtime.dart';
import 'media/stream_session_controller.dart';
import 'pairing/pairing_session_store.dart';
import 'pairing/qr_pairing_client.dart';
import '../../l10n/app_strings.dart';

class ClientCompositionRoot {
  static int createCount = 0;
  static ClientRuntime create({
    required SharedPreferences preferences,
    required AppStrings strings,
  }) {
    createCount++;
    final pairingClient = QRPairingClient();
    final store = PairingSessionStore(preferences);
    final streams = StreamSessionController();
    final alerts = ClientAlertListener();
    final notifications = ClientNotificationService();
    return ClientRuntime(
      pair: (payload) async {
        final session = await pairingClient.pair(payload);
        await store.save(session);
        return session;
      },
      startStream: streams.start,
      stopStream: streams.stop,
      startAlerts: () async {
        await notifications.initialize(strings: strings);
        await alerts.start();
      },
      stopAlerts: alerts.stop,
      clearStore: store.clear,
    );
  }
}
