import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/client/client_home_screen.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/active_stream_session.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';

void main() {
  testWidgets('room A lock is removed before room B appears in the parent card',
      (tester) async {
    final runtime = ClientRuntime(
      pair: (payload) async =>
          PairingSession(payload: payload, sessionToken: payload.deviceId),
      startStream: (session, {bool audioEnabled = false}) async {
        if (session.deviceId == 'A') {
          throw const BroadcastAccessLockedException(_locked);
        }
        return ActiveStreamSession(
            streamToken: 'B-stream',
            broadcastAccess: _locked.copyWith(unlocked: true));
      },
      stopStream: (_) async {},
    );
    try {
      await runtime.pairWithServer(_session('A').payload);
      await expectLater(runtime.startWatching(),
          throwsA(isA<BroadcastAccessLockedException>()));
      await runtime.pairWithServer(_session('B').payload);
      expect(runtime.currentState.broadcastAccess, isNull);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('tr'),
        theme: MiuCamTheme.clientTheme(),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        home: ClientHomeScreen(
            runtime: runtime,
            activeRole: AppRole.client,
            onRoleSelected: (_) {}),
      ));
      await tester.pumpAndSettle();
      final strings = AppStrings(const Locale('tr'));
      expect(find.text('Room B'), findsOneWidget);
      expect(find.text(strings.ui('broadcastAccessLockedTitle')), findsNothing);
      expect(find.text(strings.ui('broadcastAccessRemoteLockedBody')),
          findsNothing);
      await runtime.startWatching();
      expect(runtime.currentState.activeStream!.streamToken, 'B-stream');
      expect(runtime.currentState.broadcastAccess!.unlocked, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.dispose();
    }
  });

  test('delayed status from A never overwrites room B remote authority',
      () async {
    final aStatus = Completer<BroadcastAccessSnapshot?>();
    final runtime = ClientRuntime(
      pair: (payload) async =>
          PairingSession(payload: payload, sessionToken: payload.deviceId),
      refreshRemoteBroadcastAccess: (session) => session.deviceId == 'A'
          ? aStatus.future
          : Future.value(_locked.copyWith(unlocked: true)),
    );
    try {
      await runtime.pairWithServer(_session('A').payload);
      await runtime.pairWithServer(_session('B').payload);
      await runtime.refreshBroadcastAccess();
      aStatus.complete(_locked);
      await Future<void>.delayed(Duration.zero);
      expect(runtime.currentState.session!.deviceId, 'B');
      expect(runtime.currentState.broadcastAccess!.unlocked, isTrue);
      await runtime.clearPairing();
      expect(runtime.currentState.broadcastAccess, isNull);
      await runtime.restoreSession(_session('C'));
      await runtime.refreshBroadcastAccess();
      expect(runtime.currentState.session!.deviceId, 'C');
      expect(runtime.currentState.broadcastAccess!.unlocked, isTrue);
    } finally {
      await runtime.dispose();
    }
  });
}

PairingSession _session(String id) => PairingSession(
      payload: PairingPayload(
          schemaVersion: 2,
          host: '127.0.0.1',
          port: 1,
          deviceId: id,
          deviceName: 'Room $id',
          pairingNonce: 'nonce',
          expiresAtMs: DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          capabilities: const {}),
      sessionToken: 'token-$id',
    );

const _locked = BroadcastAccessSnapshot(
    unlocked: false,
    active: false,
    freeLimitMs: 7200000,
    usedMs: 7200000,
    remainingMs: 0,
    priceLabel: '€4,99',
    productId: BroadcastAccessConfig.productId);
