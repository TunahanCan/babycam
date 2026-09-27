import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/broadcast_purchase_coordinator.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/presentation/client_broadcast_access_card.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/l10n/src/app_purchase_text_catalog.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';

void main() {
  if (const bool.fromEnvironment('MIUCAM_CAPTURE_PURCHASE_UI')) {
    testWidgets('render Turkish parent purchase states', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const fontRoot = String.fromEnvironment('MIUCAM_SCREENSHOT_FONT_DIR');
      await tester.runAsync(() async {
        for (final font in [
          ('MaterialIcons', 'MaterialIcons-Regular.otf'),
          ('ReviewText', 'Roboto-Regular.ttf'),
        ]) {
          final loader = FontLoader(font.$1)
            ..addFont(File('$fontRoot/${font.$2}')
                .readAsBytes()
                .then(ByteData.sublistView));
          await loader.load();
        }
        await Directory('build/purchase_ui').create(recursive: true);
      });
      for (final state in [
        ('ready', ParentPurchasePhase.ready),
        ('pending', ParentPurchasePhase.purchasePending),
        ('activation_pending', ParentPurchasePhase.activationPending),
        ('active', ParentPurchasePhase.activated),
      ]) {
        final runtime = _UiRuntime(phase: state.$2);
        final key = GlobalKey();
        final theme = MiuCamTheme.clientTheme();
        ButtonStyle withRealFont(ButtonStyle style) => style.copyWith(
              textStyle: WidgetStatePropertyAll(
                style.textStyle!
                    .resolve({})!.copyWith(fontFamily: 'ReviewText'),
              ),
            );
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('tr'),
          supportedLocales: AppStrings.supportedLocales,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'ReviewText'),
            filledButtonTheme: FilledButtonThemeData(
                style: withRealFont(theme.filledButtonTheme.style!)),
            outlinedButtonTheme: OutlinedButtonThemeData(
                style: withRealFont(theme.outlinedButtonTheme.style!)),
          ),
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ClientBroadcastAccessCard(runtime: runtime),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/purchase_ui/${state.$1}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
        runtime.revision.dispose();
      }
    });
  }

  test('purchase messages cover every locale and preserve template fields', () {
    for (final entry in appPurchaseTextCatalog.entries) {
      final expected = RegExp(r'\{[^}]+\}')
          .allMatches(entry.value['en']!)
          .map((m) => m.group(0))
          .toSet();
      for (final locale in AppStrings.supportedLocales) {
        expect(entry.value.containsKey(locale.languageCode), isTrue);
        final text = AppStrings(locale).ui(entry.key);
        expect(
            RegExp(r'\{[^}]+\}')
                .allMatches(text)
                .map((m) => m.group(0))
                .toSet(),
            expected,
            reason: '${entry.key} $locale');
      }
    }
  });

  for (final locale in AppStrings.supportedLocales) {
    for (final layout in [
      (size: const Size(320, 568), scale: 2.0),
      (size: const Size(640, 360), scale: 1.3),
    ]) {
      testWidgets('parent checkout ${locale.toLanguageTag()} ${layout.size}',
          (tester) async {
        await tester.binding.setSurfaceSize(layout.size);
        final runtime = _UiRuntime();
        try {
          await tester.pumpWidget(MaterialApp(
            locale: locale,
            supportedLocales: AppStrings.supportedLocales,
            theme: MiuCamTheme.clientTheme(),
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(layout.scale)),
                child: child!),
            home: Scaffold(
                body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<int>(
                valueListenable: runtime.revision,
                builder: (context, value, child) =>
                    ClientBroadcastAccessCard(runtime: runtime),
              ),
            )),
          ));
          await tester.pumpAndSettle();
          final strings = AppStrings(locale);
          expect(
              find.text(
                  strings.uiFormat('familyPurchasePrice', {'price': '£7.99'})),
              findsOneWidget);
          final buy = find.byKey(const ValueKey('parent-license-purchase'));
          await tester.ensureVisible(buy);
          await tester.tap(buy);
          await tester.pumpAndSettle();
          expect(runtime.purchaseCalls, 1);
          expect(
              find.text(strings.ui('familyPurchasePending')), findsOneWidget);
          expect(buy, findsNothing,
              reason: 'Pending payment cannot buy twice.');
          final restore = find.byKey(const ValueKey('parent-license-restore'));
          await tester.ensureVisible(restore);
          await tester.tap(restore);
          await tester.pumpAndSettle();
          expect(runtime.restoreCalls, 1);
          expect(find.text(strings.ui('familyVerificationPending')),
              findsOneWidget);
          runtime.setPhase(ParentPurchasePhase.activationPending);
          await tester.pumpAndSettle();
          expect(
              find.text(strings.ui('familyActivationPending')), findsOneWidget);
          expect(find.text(strings.ui('familyActivateRoom')), findsOneWidget);
          runtime.setPhase(ParentPurchasePhase.activated);
          await tester.pumpAndSettle();
          expect(find.text(strings.ui('familyLicenseActive')), findsOneWidget);
          expect(buy, findsNothing);
          expect(restore, findsNothing);
          runtime.setPhase(ParentPurchasePhase.noPurchaseFound);
          await tester.pumpAndSettle();
          expect(
              find.text(strings.ui('familyNoPurchaseFound')), findsOneWidget);
          runtime.setPhase(ParentPurchasePhase.revoked);
          await tester.pumpAndSettle();
          expect(find.text(strings.ui('familyLicenseRevoked')), findsOneWidget);
          await tester.drag(
              find.byType(SingleChildScrollView), const Offset(0, -1000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          runtime.revision.dispose();
          await tester.binding.setSurfaceSize(null);
        }
      });
    }
  }
}

// Store delivery, durable grants and role changes are covered with the real
// coordinator/service in broadcast_purchase_coordinator_test. This fixture owns
// only the state presented by the card, so viewport tests need no store plugin.
class _UiRuntime implements ClientRuntime {
  _UiRuntime({ParentPurchasePhase phase = ParentPurchasePhase.ready}) {
    _purchases.state = ParentPurchaseState(roomId: 'A', phase: phase);
  }
  final revision = ValueNotifier(0);
  final _UiPurchases _purchases = _UiPurchases();
  int purchaseCalls = 0;
  int restoreCalls = 0;

  @override
  BroadcastPurchaseCoordinator get purchases => _purchases;
  @override
  ParentPurchaseState get purchaseState => _purchases.state;
  @override
  ClientRuntimeState get currentState => ClientRuntimeState(
        phase: ClientRuntimePhase.pairedIdle,
        session: PairingSession(payload: _payload, sessionToken: 'token'),
        broadcastAccess: BroadcastAccessSnapshot(
            unlocked: purchaseState.phase == ParentPurchasePhase.activated,
            active: false,
            freeLimitMs: 7200000,
            usedMs: 7200000,
            remainingMs: 0,
            priceLabel: '€4,99',
            hasStorePrice: true,
            productId: BroadcastAccessConfig.productId),
      );
  void setPhase(ParentPurchasePhase phase) {
    _purchases.state = ParentPurchaseState(roomId: 'A', phase: phase);
    revision.value++;
  }

  @override
  Future<void> unlockBroadcastAccess() async {
    purchaseCalls++;
    _purchases.state = const ParentPurchaseState(
        roomId: 'A', phase: ParentPurchasePhase.purchasePending);
    revision.value++;
  }

  @override
  Future<void> restoreBroadcastAccessPurchase() async {
    restoreCalls++;
    _purchases.state = const ParentPurchaseState(
        roomId: 'A', phase: ParentPurchasePhase.verificationPending);
    revision.value++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UiPurchases implements BroadcastPurchaseCoordinator {
  ParentPurchaseState state = const ParentPurchaseState(roomId: 'A');
  @override
  bool get checkoutConfigured => true;
  @override
  bool get activationConfigured => true;
  @override
  bool get operationInProgress => false;
  @override
  bool get hasLicense =>
      state.phase == ParentPurchasePhase.activationPending ||
      state.phase == ParentPurchasePhase.activated;
  @override
  bool get requiresRestore => false;
  @override
  String? get localPrice => '£7.99';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _payload = PairingPayload(
    schemaVersion: 2,
    host: '127.0.0.1',
    port: 1,
    deviceId: 'A',
    deviceName: 'Bebek Odası',
    pairingNonce: 'nonce',
    expiresAtMs:
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    capabilities: const {});
