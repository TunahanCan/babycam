import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/alerts/client_alert_listener.dart';
import 'package:miucam/features/client/client_home_screen.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';

void main() {
  testWidgets(
      'parent home explains the room trial lock in every supported locale',
      (tester) async {
    final connections = StreamController<bool>.broadcast();
    final session = _session(1001);
    final runtime = ClientRuntime(
      pair: (_) async => session,
      startAlerts: (_) async => true,
      stopAlerts: () async {},
      alertConnectionStates: connections.stream,
    );
    addTearDown(runtime.dispose);
    addTearDown(connections.close);
    await runtime.pairWithServer(session.payload);
    await runtime.startAlertListening();
    connections.addError(
        ClientAlertAccessLockedException(session: session, snapshot: _locked));
    await tester.pump();
    for (final locale in AppStrings.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      final strings = AppStrings(locale);
      expect(
          find.text(strings.ui('broadcastAccessLockedTitle')), findsOneWidget);
      expect(find.text(strings.ui('broadcastAccessRemoteLockedBody')),
          findsOneWidget);
      expect(find.text(strings.ui('clientTitleReconnecting')), findsNothing);
      expect(tester.takeException(), isNull, reason: locale.toLanguageTag());
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

const _locked = BroadcastAccessSnapshot(
  unlocked: false,
  active: false,
  freeLimitMs: 7200000,
  usedMs: 7200000,
  remainingMs: 0,
  priceLabel: '350 TL',
  productId: BroadcastAccessConfig.productId,
);

PairingSession _session(int port) => PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        deviceId: 'room-$port',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        capabilities: const {'transport': 'http'},
      ),
      sessionToken: 'trusted-token',
      clientId: 'parent',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 60)).millisecondsSinceEpoch,
    );
