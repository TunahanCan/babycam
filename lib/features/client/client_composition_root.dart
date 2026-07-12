import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'alerts/client_alert_background_service.dart';
import 'alerts/client_alert_listener.dart';
import 'alerts/client_alert_history.dart';
import 'alerts/client_notification_service.dart';
import 'client_runtime.dart';
import 'controls/client_room_controls.dart';
import 'discovery/trusted_session_endpoint_resolver.dart';
import 'media/client_stream_health_state.dart';
import 'media/network_quality_monitor.dart';
import 'media/remote_broadcast_access_client.dart';
import 'media/stream_session_controller.dart';
import 'media/webrtc/flutter_webrtc_client_connector.dart';
import 'pairing/client_identity_store.dart';
import 'pairing/pairing_failure.dart';
import 'pairing/pairing_session_store.dart';
import 'pairing/qr_pairing_client.dart';
import 'pairing/trusted_token_renewal_client.dart';
import '../../l10n/app_strings.dart';
import '../../services/discovery/mimicam_service_discovery.dart';

class ClientCompositionRoot {
  static int createCount = 0;
  static ClientRuntime create({
    required SharedPreferences preferences,
    required AppStrings strings,
    SecureTokenStore? secureTokens,
    ClientNotificationService? notificationService,
    ClientAlertListener? alertListener,
  }) {
    createCount++;
    final identity = ClientIdentityStore(secureTokens: secureTokens);
    final pairingClient = QRPairingClient(
      clientIdProvider: identity.clientId,
      // When this phone has previously acted as Server, its discovery id is
      // retained locally. Send it only to prevent the phone from pairing with
      // its own QR code after a role switch.
      localServerDeviceIdProvider: () async =>
          preferences.getString('discovery.server_device_id'),
    );
    final tokenRenewal = TrustedTokenRenewalClient();
    final store = PairingSessionStore(
      preferences,
      secureTokens: secureTokens,
    );
    final streamHealth = ClientStreamHealthState();
    final streams = StreamSessionController(
      healthState: streamHealth,
      webRtcConnector: FlutterWebRtcClientConnector(),
    );
    final networkQuality = NetworkQualityMonitor(healthState: streamHealth);
    final remoteBroadcastAccess = RemoteBroadcastAccessClient();
    final alertHistory = ClientAlertHistory(preferences: preferences);
    final notifications = notificationService ?? ClientNotificationService();
    const alertBackground = ClientAlertBackgroundService();
    final roomControls = ClientRoomControls();
    final serviceBrowser = MimiCamServiceBrowser();
    final endpointResolver = TrustedSessionEndpointResolver(
      browser: serviceBrowser,
    );
    var alertDeliveryTail = Future<void>.value();
    final alerts = alertListener ??
        ClientAlertListener(
          healthState: streamHealth,
          onAlert: (alert) {
            alertDeliveryTail = alertDeliveryTail.then<void>((_) async {
              try {
                await alertHistory.add(alert);
              } catch (_) {
                // A storage failure must not suppress the phone notification.
              }
              await notifications.showAlert(alert);
            }).catchError((_) {
              // Keep processing later alerts if the platform rejects one post.
            });
          },
        );

    Future<void> stopAlerts() async {
      try {
        await alerts.stop();
      } finally {
        await alertBackground.stop();
      }
      await alertDeliveryTail;
    }

    final runtime = ClientRuntime(
      pair: (payload) async {
        try {
          // A new room would otherwise consume a trusted-client slot on the
          // Server and only then discover that this phone cannot retain it.
          await store.ensureCanSavePayload(payload);
          final session = await pairingClient.pair(payload);
          await store.save(session);
          return session;
        } on ChildProfileLimitException {
          throw const PairingFailure(
            PairingFailureCode.maxChildProfilesReached,
          );
        }
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
        // System banner permission and LAN event transport are separate
        // concerns. Even when iOS notifications are disabled, keep the socket
        // armed so alerts reach the in-app history and begin server analysis.
        await notifications.initialize(strings: strings);
        try {
          await alertBackground.start();
          await alerts.start(session, waitForFirstConnection: false);
          return alerts.isListening;
        } catch (_) {
          await stopAlerts();
          rethrow;
        }
      },
      stopAlerts: stopAlerts,
      alertConnectionStates: alerts.connectionStates,
      clearStore: store.clear,
      watchSessionEndpoints: endpointResolver.watch,
      persistReboundSession: store.save,
      refreshRemoteBroadcastAccess: remoteBroadcastAccess.snapshot,
      alertHistory: alertHistory,
      streamHealthState: streamHealth,
      roomControls: roomControls,
      serviceBrowser: serviceBrowser,
    );
    unawaited(runtime.loadAlertHistory());
    unawaited(runtime.startDiscovery().catchError((_) {}));
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
