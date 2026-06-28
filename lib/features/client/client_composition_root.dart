import 'package:shared_preferences/shared_preferences.dart';

import 'alerts/client_alert_listener.dart';
import 'alerts/client_notification_service.dart';
import 'client_runtime.dart';
import 'media/client_stream_health_state.dart';
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
    final streamHealth = ClientStreamHealthState();
    final streams = StreamSessionController(healthState: streamHealth);
    final networkQuality = NetworkQualityMonitor(healthState: streamHealth);
    final notifications = ClientNotificationService();
    final alerts = ClientAlertListener(
      healthState: streamHealth,
      onAlert: (alert) => notifications.showAlert(alert),
    );
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
        final notificationsEnabled =
            await notifications.initialize(strings: strings);
        if (!notificationsEnabled) return false;
        await alerts.start(session);
        return true;
      },
      stopAlerts: alerts.stop,
      clearStore: store.clear,
      streamHealthState: streamHealth,
    );
  }
}
