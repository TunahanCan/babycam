import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/media/watch_screen.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/presentation/server_preview_section.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';

const locked = BroadcastAccessSnapshot(
    unlocked: false,
    active: false,
    freeLimitMs: 7200000,
    usedMs: 7200000,
    remainingMs: 0,
    priceLabel: '€4,99',
    hasStorePrice: true,
    productId: BroadcastAccessConfig.productId);

void main() {
  for (final language in ['tr', 'en', 'zh', 'hi', 'es', 'fr', 'de', 'ar']) {
    testWidgets(
        'lifetime price and fallback are clear on a narrow $language screen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final strings = AppStrings(Locale(language));
      final runtime = ServerRuntime(mediaRuntime: MediaRuntimeController());
      Widget card(BroadcastAccessSnapshot value) => _app(
          language,
          SingleChildScrollView(
              child: ServerBroadcastAccessCard(
                  snapshot: value, runtime: runtime, onUnlocked: () {})));
      await tester.pumpWidget(card(locked));
      await tester.pumpAndSettle();
      expect(
          find.text(strings
              .uiFormat('broadcastAccessLockedBody', {'price': '€4,99'})),
          findsOneWidget);
      expect(
          find.text(
              strings.uiFormat('unlockLifetimePrice', {'price': '€4,99'})),
          findsOneWidget);
      expect(find.textContaining('350'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(card(locked.copyWith(hasStorePrice: false)));
      await tester.pumpAndSettle();
      expect(find.textContaining('€4,99'), findsNothing);
      expect(find.text(strings.ui('unlockLifetime')), findsOneWidget);
      final fallback = strings.uiFormat('broadcastAccessPriceFallback', {
        'price':
            strings.formatCurrency(350, currencyCode: 'TRY', decimalDigits: 0)
      });
      if (language == 'tr') expect(fallback, contains('350 TL'));
      expect(find.textContaining(fallback), findsOneWidget);
      expect(tester.takeException(), isNull);
      // A still-usable final half minute must not read as an expired zero.
      await tester.pumpWidget(
          card(locked.copyWith(usedMs: 7170000, remainingMs: 30000)));
      await tester.pumpAndSettle();
      expect(
          find.text(strings.ui('broadcastAccessTrialTitle')), findsOneWidget);
      expect(
          find.textContaining(
              strings.uiFormat('durationMinutesShort', {'minutes': 1})),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.dispose();
    });
  }

  testWidgets('parent sees room payment instructions without its own checkout',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    messenger.setMockMessageHandler(
        channel,
        (_) async =>
            const StandardMessageCodec().encodeMessage(<Object?>[null]));
    final payload = PairingPayload(
        schemaVersion: 2,
        host: '127.0.0.1',
        port: 1,
        deviceId: 'room',
        deviceName: 'Room',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        capabilities: const {});
    final runtime = ClientRuntime(
        pair: (p) async => PairingSession(payload: p, sessionToken: 'token'),
        startStream: (_, {bool audioEnabled = false}) async =>
            throw const BroadcastAccessLockedException(locked));
    await runtime.pairWithServer(payload);
    await tester.pumpWidget(
        _app('tr', WatchScreen(runtime: runtime, keepScreenAwake: false)));
    await tester.pumpAndSettle();
    final strings = AppStrings(const Locale('tr'));
    expect(find.text(strings.ui('broadcastAccessRemoteLockedBody')),
        findsOneWidget);
    expect(find.text(strings.ui('unlockLifetime')), findsNothing);
    expect(
        find.text(strings
            .uiFormat('unlockLifetimePrice', {'price': locked.priceLabel})),
        findsNothing);
    expect(find.text(strings.ui('restorePurchase')), findsNothing);
    expect(find.textContaining('€4,99'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.dispose();
    messenger.setMockMessageHandler(channel, null);
  });

  test('trial checkpoints and late lifetime grants reach server presentation',
      () async {
    final changes = StreamController<BroadcastAccessSnapshot>.broadcast();
    final runtime = ServerRuntime(
        mediaRuntime: MediaRuntimeController(),
        broadcastAccessChanges: changes.stream);
    final trial = locked.copyWith(usedMs: 60000, remainingMs: 7140000);
    final updated = runtime.states.first;
    changes.add(trial);
    expect((await updated).broadcastAccess?.remainingMs, 7140000);
    final purchased = runtime.states.first;
    changes.add(trial.copyWith(unlocked: true));
    expect((await purchased).broadcastAccess?.unlocked, isTrue);
    await runtime.dispose();
    await changes.close();
  });
}

Widget _app(String language, Widget child) => MaterialApp(
    locale: Locale(language),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate
    ],
    home: Scaffold(body: child));
