import 'package:shared_preferences/shared_preferences.dart';

import 'alerts/client_alert_listener.dart';
import 'alerts/client_notification_service.dart';
import 'client_runtime.dart';
import 'media/network_quality_monitor.dart';
import 'media/stream_session_controller.dart';
import 'pairing/pairing_session_store.dart';
import 'pairing/qr_pairing_client.dart';
import 'pairing/trusted_token_renewal_client.dart';
import '../../l10n/app_strings.dart';

class ClientCompositionRoot {
  static int createCount = 0;
  static ClientRuntime create({
    required SharedPreferences preferences,
    required AppStrings strings,
  }) {
    createCount++;
    const pairingClient = QRPairingClient();
    final tokenRenewal = TrustedTokenRenewalClient();
    final store = PairingSessionStore(preferences);
    final streams = StreamSessionController();
    final networkQuality = NetworkQualityMonitor();
    final alerts = ClientAlertListener();
    final notifications = ClientNotificationService();
    return ClientRuntime(
      pair: (payload) async {
        final session = await pairingClient.pair(payload);
        await store.save(session);
        return session;
      },
      renew: (session) async {
        final renewed = await tokenRenewal.renew(session);
        if (renewed != null) await store.save(renewed);
        return renewed;
      },
      startStream: streams.start,
      stopStream: streams.stop,
      watchNetworkQuality: networkQuality.watch,
      startAlerts: (session) async {
        await notifications.initialize(strings: strings);
        await alerts.start(session);
      },
      stopAlerts: alerts.stop,
      clearStore: store.clear,
    );
  }
}
