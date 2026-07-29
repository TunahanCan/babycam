import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/alerts/client_alert_listener.dart';
import 'package:miucam/features/client/alerts/client_notification_service.dart';
import 'package:miucam/features/client/client_composition_root.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/pairing/pairing_session_store.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saved pairing session client runtime icine restore edilir', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final payload = _payload();
    SharedPreferences.setMockInitialValues({
      'pairing_session': jsonEncode({
        'payload': payload.toJson(),
        'clientId': 'client-1',
        'trustedClientTokenExpiresAtMs':
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
        'pairedAtMs': 1000,
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureTokenStore()
      ..values['pairing_session_token'] = 'restored-token';

    final runtime = ClientCompositionRoot.create(
      preferences: preferences,
      strings: AppStrings(const Locale('tr')),
      secureTokens: secure,
    );

    await expectLater(
      runtime.states.firstWhere((state) => state.session != null),
      completion(
        isA<ClientRuntimeState>()
            .having(
              (state) => state.phase,
              'phase',
              anyOf(
                ClientRuntimePhase.pairedIdle,
                ClientRuntimePhase.alertOnly,
              ),
            )
            .having((state) => state.session?.sessionToken, 'token',
                'restored-token')
            .having((state) => state.session?.payload.deviceName, 'room',
                'Bebek Odası'),
      ),
    );
    await expectLater(
      runtime.states.firstWhere((state) => state.alertsActive),
      completion(
        isA<ClientRuntimeState>()
            .having((state) => state.alertsActive, 'alertsActive', isTrue)
            .having(
              (state) => state.phase,
              'phase',
              ClientRuntimePhase.alertOnly,
            ),
      ),
    );
    expect(
      runtime.currentState.broadcastAccess,
      isNull,
      reason: 'The room/server is the only entitlement authority.',
    );
    await runtime.dispose().timeout(const Duration(seconds: 5));
  });

  test('iOS banner izni kapalı olsa da LAN alert transportu başlatılır',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final payload = _payload();
    SharedPreferences.setMockInitialValues({
      'pairing_session': jsonEncode({
        'payload': payload.toJson(),
        'clientId': 'client-ios',
        'trustedClientTokenExpiresAtMs':
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
        'pairedAtMs': 1000,
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureTokenStore()
      ..values['pairing_session_token'] = 'restored-token';
    final notifications = _DeniedNotificationService();
    final listener = _RecordingAlertListener();

    final runtime = ClientCompositionRoot.create(
      preferences: preferences,
      strings: AppStrings(const Locale('tr')),
      secureTokens: secure,
      notificationService: notifications,
      alertListener: listener,
    );
    addTearDown(runtime.dispose);

    await runtime.states.firstWhere((state) => state.alertsActive);

    expect(notifications.initializeCalls, 1);
    expect(listener.startCalls, 1);
    expect(runtime.currentState.alertsActive, isTrue);
    expect(runtime.systemNotificationsEnabled, isFalse);
  });

  test('locale değişimi alert transport yeniden başlayınca geri alınmaz',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final payload = _payload();
    SharedPreferences.setMockInitialValues({
      'pairing_session': jsonEncode({
        'payload': payload.toJson(),
        'clientId': 'client-locale',
        'trustedClientTokenExpiresAtMs':
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
        'pairedAtMs': 1000,
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureTokenStore()
      ..values['pairing_session_token'] = 'restored-token';
    final notifications = _RecordingNotificationService();
    final listener = _RecordingAlertListener();
    final runtime = ClientCompositionRoot.create(
      preferences: preferences,
      strings: AppStrings(const Locale('tr')),
      secureTokens: secure,
      notificationService: notifications,
      alertListener: listener,
    );
    addTearDown(runtime.dispose);
    await runtime.states.firstWhere((state) => state.alertsActive);

    runtime.updateAlertStrings(AppStrings(const Locale('en', 'US')));
    await runtime.stopAlertListening();
    await runtime.startAlertListening();

    expect(notifications.currentLocale, 'en-US');
    expect(notifications.localeUpdates, ['tr', 'en-US']);
    expect(notifications.initializeCalls, 2);
  });
}

PairingPayload _payload() => PairingPayload(
      schemaVersion: MiuCamProtocolV2.schemaVersion,
      host: '127.0.0.1',
      port: 9,
      deviceId: 'server',
      deviceName: 'Bebek Odası',
      pairingNonce: 'nonce',
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      capabilities: const {'transport': 'http_ws'},
    );

class _FakeSecureTokenStore implements SecureTokenStore {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _DeniedNotificationService extends ClientNotificationService {
  int initializeCalls = 0;

  @override
  Future<bool> initialize({AppStrings? strings}) async {
    initializeCalls++;
    return false;
  }
}

class _RecordingNotificationService extends ClientNotificationService {
  int initializeCalls = 0;
  String? currentLocale;
  final localeUpdates = <String>[];

  @override
  void updateStrings(AppStrings strings) {
    currentLocale = strings.locale.toLanguageTag();
    localeUpdates.add(currentLocale!);
  }

  @override
  Future<bool> initialize({AppStrings? strings}) async {
    initializeCalls++;
    if (strings != null) updateStrings(strings);
    return true;
  }
}

class _RecordingAlertListener extends ClientAlertListener {
  int startCalls = 0;

  @override
  Future<void> start(
    PairingSession session, {
    bool waitForFirstConnection = true,
  }) async {
    startCalls++;
    isListening = true;
    isConnected = true;
  }

  @override
  Future<void> stop() async {
    isListening = false;
    isConnected = false;
  }
}
