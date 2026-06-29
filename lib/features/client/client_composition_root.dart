import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'alerts/client_alert_listener.dart';
import 'alerts/client_alert_history.dart';
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
    SecureTokenStore? secureTokens,
  }) {
    createCount++;
    const pairingClient = QRPairingClient();
    final tokenRenewal = TrustedTokenRenewalClient();
    final store = PairingSessionStore(
      preferences,
      secureTokens: secureTokens,
    );
    final streamHealth = ClientStreamHealthState();
    final streams = StreamSessionController(healthState: streamHealth);
    final networkQuality = NetworkQualityMonitor(healthState: streamHealth);
    final alertHistory = ClientAlertHistory(preferences: preferences);
    final notifications = ClientNotificationService();
    final alerts = ClientAlertListener(
      healthState: streamHealth,
      onAlert: (alert) {
        unawaited(alertHistory.add(alert).catchError((_) {}));
        unawaited(notifications.showAlert(alert).catchError((_) {}));
      },
    );
    final runtime = ClientRuntime(
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
        unawaited(
          notifications.initialize(strings: strings).catchError((_) => false),
        );
        await alerts.start(session, waitForFirstConnection: false);
        return true;
      },
      stopAlerts: alerts.stop,
      clearStore: store.clear,
      alertHistory: alertHistory,
      streamHealthState: streamHealth,
    );
    unawaited(runtime.loadAlertHistory());
    unawaited(_restoreSavedSession(runtime, store));
    return runtime;
  }

  static Future<void> _restoreSavedSession(
    ClientRuntime runtime,
    PairingSessionStore store,
  ) async {
    final session = await store.load();
    if (session == null) return;
    await runtime.restoreSession(session);
    if (runtime.currentState.phase == ClientRuntimePhase.revoked ||
        runtime.currentState.session == null) {
      return;
    }
    unawaited(runtime.startAlertListening().catchError((_) => false));
  }
}
