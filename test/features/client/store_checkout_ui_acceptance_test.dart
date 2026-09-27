import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/broadcast_purchase_coordinator.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/presentation/client_broadcast_access_card.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:miucam/services/monetization/license_grant.dart';
import 'package:miucam/services/monetization/room_broadcast_access_gateway.dart';
import 'package:miucam/services/monetization/shared_preferences_pending_room_activation_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/license_token_fixture.dart';
import '../../support/runtime_widget_cleanup.dart';

/// UI actions flow through the real runtime, coordinator and durable access
/// service. Only the native store boundary and remote room are substitutes.
void main() {
  testWidgets('pending approval then offline room retries without a new charge',
      (tester) async {
    final rig = await _CheckoutRig.create();
    try {
      rig.store.purchaseResult = const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.pending,
      );
      await rig.show(tester);
      expect(
          find.text(
              _strings.uiFormat('familyPurchasePrice', {'price': '£7.99'})),
          findsOneWidget);
      await _tap(tester, _buy);
      await _pumpUntil(
          tester,
          () =>
              rig.runtime.purchaseState.phase ==
              ParentPurchasePhase.purchasePending);
      expect(find.text(_strings.ui('familyPurchasePending')), findsOneWidget);
      expect(_buy, findsNothing,
          reason: 'A pending store approval cannot be bought twice.');
      expect(rig.store.purchases, 1);
      expect(rig.preferences.getStringList('broadcast_purchase.pending_rooms'),
          ['A']);
      expect(rig.access.licenseToken, isNull);
      expect(rig.room.activated, isEmpty);

      rig.room.offline = true;
      rig.store.publish(rig.store.approved);
      await _pumpUntil(
          tester,
          () =>
              rig.runtime.purchaseState.phase ==
                  ParentPurchasePhase.activationPending &&
              !rig.coordinator.operationInProgress);
      expect(find.text(_strings.ui('familyActivationPending')), findsOneWidget);
      expect(find.text(_strings.ui('familyActivateRoom')), findsOneWidget);
      expect(rig.access.licenseToken, rig.token);
      expect(rig.runtime.currentState.broadcastAccess?.unlocked, isFalse);
      expect(rig.store.purchases, 1);

      rig.room.offline = false;
      await _tap(tester, _buy);
      await _pumpUntil(tester,
          () => rig.runtime.currentState.broadcastAccess?.unlocked == true);
      expect(find.text(_strings.ui('familyLicenseActive')), findsOneWidget);
      expect(_buy, findsNothing);
      expect(_restore, findsNothing);
      expect(rig.room.activated, ['A']);
      expect(rig.store.purchases, 1);
      expect(rig.store.restores, 0);
      expect(rig.activatedCallbacks, 1);
      expect(rig.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);
      expect((await rig.access.snapshot()).usedMs, 0,
          reason: 'The parent does not start a separate trial ledger.');
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets(
      'restore explains an empty store and then delivers an owned license',
      (tester) async {
    final rig = await _CheckoutRig.create();
    try {
      rig.store.restoreResult = const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.noPurchaseFound,
      );
      await rig.show(tester);
      await _tap(tester, _restore);
      await _pumpUntil(
          tester,
          () =>
              rig.runtime.purchaseState.phase ==
              ParentPurchasePhase.noPurchaseFound);
      expect(find.text(_strings.ui('familyNoPurchaseFound')), findsOneWidget);
      expect(_buy, findsOneWidget);
      expect(rig.room.activated, isEmpty);
      expect(rig.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);

      rig.store.restoreResult = rig.store.approved;
      await _tap(tester, _restore);
      await _pumpUntil(tester,
          () => rig.runtime.currentState.broadcastAccess?.unlocked == true);
      expect(find.text(_strings.ui('familyLicenseActive')), findsOneWidget);
      expect(rig.store.purchases, 0);
      expect(rig.store.restores, 2);
      expect(rig.room.activated, ['A']);
      expect(rig.access.licenseToken, rig.token);
      expect(rig.activatedCallbacks, 1);
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets('A checkout cannot activate the visible B card or its callback',
      (tester) async {
    final rig = await _CheckoutRig.create();
    try {
      rig.store.heldPurchase = Completer<BroadcastPurchaseResult>();
      await rig.show(tester);
      await _tap(tester, _buy);
      await _pumpUntil(tester, () => rig.store.purchases == 1);
      expect(
          find.text(_strings.ui('familyPurchaseProcessing')), findsOneWidget);
      expect(tester.widget<FilledButton>(_buy).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(_restore).onPressed, isNull);

      await rig.runtime.pairWithServer(_session('B').payload);
      await rig.runtime.refreshBroadcastAccess();
      await tester.pump();
      rig.store.heldPurchase!.complete(rig.store.approved);
      await _pumpUntil(
          tester,
          () =>
              rig.coordinator.stateFor('A').phase ==
                  ParentPurchasePhase.activated &&
              !rig.coordinator.operationInProgress);

      expect(
          find.text(_strings.uiFormat('familyLicenseRoom', {'room': 'Room B'})),
          findsOneWidget);
      expect(find.text(_strings.ui('familyLicenseActive')), findsNothing);
      expect(rig.runtime.currentState.session!.deviceId, 'B');
      expect(rig.runtime.currentState.broadcastAccess?.unlocked, isFalse);
      expect(rig.room.activated, ['A']);
      expect(rig.activatedCallbacks, 0,
          reason:
              'A late completion must not start watching the newly selected room.');
      expect(rig.store.purchases, 1);
      expect(find.text(_strings.ui('familyActivateRoom')), findsOneWidget);

      await _tap(tester, _buy);
      await _pumpUntil(tester,
          () => rig.runtime.currentState.broadcastAccess?.unlocked == true);
      expect(rig.room.activated, ['A', 'B']);
      expect(rig.store.purchases, 1,
          reason: 'The same family license can activate another paired room.');
      expect(rig.activatedCallbacks, 1);
    } finally {
      if (rig.store.heldPurchase?.isCompleted == false) {
        rig.store.heldPurchase!.complete(const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.canceled,
        ));
        await tester.pump();
      }
      await rig.close(tester);
    }
  });

  testWidgets(
      'canceling checkout clears its destination and allows a new attempt',
      (tester) async {
    final rig = await _CheckoutRig.create();
    try {
      rig.store.purchaseResult = const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.canceled,
      );
      await rig.show(tester);
      await _tap(tester, _buy);
      await _pumpUntil(
          tester,
          () =>
              rig.runtime.purchaseState.phase == ParentPurchasePhase.canceled);
      expect(find.text(_strings.ui('purchaseCanceled')), findsOneWidget);
      expect(tester.widget<FilledButton>(_buy).onPressed, isNotNull);
      expect(rig.preferences.getStringList('broadcast_purchase.pending_rooms'),
          isEmpty);
      expect(rig.access.licenseToken, isNull);
      expect(rig.room.activated, isEmpty);

      rig.store.purchaseResult = rig.store.approved;
      await _tap(tester, _buy);
      await _pumpUntil(tester,
          () => rig.runtime.currentState.broadcastAccess?.unlocked == true);
      expect(rig.store.purchases, 2);
      expect(rig.room.activated, ['A']);
      expect(rig.activatedCallbacks, 1);
    } finally {
      await rig.close(tester);
    }
  });
}

class _CheckoutRig {
  _CheckoutRig(this.preferences, this.token, LicenseGrantVerifier verifier) {
    store = _StoreBoundary(token);
    access = BroadcastAccessService(preferences,
        purchaseGateway: store, licenseGrantVerifier: verifier);
    coordinator = BroadcastPurchaseCoordinator(
      pendingActivations:
          SharedPreferencesPendingRoomActivationRepository(preferences),
      access: access,
      remote: room,
      licenseVerifier: verifier,
    );
    runtime = ClientRuntime(
      pair: (payload) async => PairingSession(
          payload: payload, sessionToken: 'trusted-${payload.deviceId}'),
      purchases: coordinator,
      refreshRemoteBroadcastAccess: room.snapshot,
    );
  }

  static Future<_CheckoutRig> create() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final fixture = await LicenseTokenFixture.create();
    return _CheckoutRig(preferences, await fixture.token(),
        LicenseGrantVerifier(publicKey: fixture.publicKey));
  }

  final SharedPreferences preferences;
  final String token;
  final room = _RoomBoundary();
  late final _StoreBoundary store;
  late final BroadcastAccessService access;
  late final BroadcastPurchaseCoordinator coordinator;
  late final ClientRuntime runtime;
  int activatedCallbacks = 0;

  Future<void> show(WidgetTester tester) async {
    await access.snapshot();
    await runtime.pairWithServer(_session('A').payload);
    await runtime.refreshBroadcastAccess();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('tr'),
      supportedLocales: AppStrings.supportedLocales,
      theme: MiuCamTheme.clientTheme(),
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: StreamBuilder<ClientRuntimeState>(
            stream: runtime.states,
            initialData: runtime.currentState,
            builder: (context, snapshot) => ClientBroadcastAccessCard(
              runtime: runtime,
              onActivated: () async => activatedCallbacks++,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await disposeClientRuntime(tester, runtime);
    var closed = false;
    final closing = coordinator.dispose().whenComplete(() => closed = true);
    await _pumpUntil(tester, () => closed, flushExternalCallbacks: true);
    await closing;
    expect(tester.takeException(), isNull);
  }
}

class _StoreBoundary extends BroadcastPurchaseGateway
    implements BroadcastProductOfferGateway, BroadcastPurchaseUpdateSource {
  _StoreBoundary(this.token);
  final String token;
  final _updates = StreamController<BroadcastPurchaseResult>.broadcast();
  BroadcastPurchaseResult? purchaseResult;
  BroadcastPurchaseResult? restoreResult;
  Completer<BroadcastPurchaseResult>? heldPurchase;
  int purchases = 0;
  int restores = 0;

  BroadcastPurchaseResult get approved => BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.purchased,
        verified: true,
        verificationSource: 'google_play',
        verificationFingerprint: 'a' * 64,
        entitlementId: 'household_test',
        licenseToken: token,
      );

  @override
  Stream<BroadcastPurchaseResult> get updates => _updates.stream;
  void publish(BroadcastPurchaseResult result) => _updates.add(result);

  @override
  BroadcastProductOffer get cachedOffer => const BroadcastProductOffer(
        productId: BroadcastAccessConfig.productId,
        localizedPrice: '£7.99',
        rawPrice: 7.99,
        currencyCode: 'GBP',
      );

  @override
  Future<BroadcastProductOffer?> loadOffer({required String productId}) async =>
      cachedOffer;

  @override
  Future<BroadcastPurchaseResult> purchase(
      {required String productId, required String priceLabel}) async {
    purchases++;
    return await heldPurchase?.future ?? purchaseResult ?? approved;
  }

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async {
    restores++;
    return restoreResult ?? approved;
  }

  @override
  Future<void> dispose() => _updates.close();
}

class _RoomBoundary implements RoomBroadcastAccessGateway {
  bool offline = false;
  final activated = <String>[];
  final _snapshots = <String, BroadcastAccessSnapshot>{};

  @override
  Future<BroadcastAccessSnapshot> snapshot(PairingSession session) async =>
      _snapshots[session.deviceId] ?? _locked;
  @override
  Future<bool> supportsActivation(PairingSession session) async => true;
  @override
  Future<String?> readLicense(PairingSession session) async => null;
  @override
  Future<BroadcastAccessSnapshot> activate(
      PairingSession session, String licenseToken) async {
    if (offline) throw StateError('Room disconnected after store approval');
    activated.add(session.deviceId);
    return _snapshots[session.deviceId] = _locked.copyWith(unlocked: true);
  }
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target, warnIfMissed: true);
  await tester.pump();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition,
    {bool flushExternalCallbacks = false}) async {
  for (var attempt = 0; attempt < 40 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (flushExternalCallbacks) {
      // Stream cancellation can complete in the outer test zone. Pump both
      // queues while retaining and awaiting the original shutdown future.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  }
  expect(condition(), isTrue,
      reason: 'Checkout must settle without a hidden store operation.');
  await tester.pump();
}

final _buy = find.byKey(const ValueKey('parent-license-purchase'));
final _restore = find.byKey(const ValueKey('parent-license-restore'));
final _strings = AppStrings(const Locale('tr'));

PairingSession _session(String room) => PairingSession(
      payload: PairingPayload(
        schemaVersion: 2,
        host: '127.0.0.1',
        port: 1,
        deviceId: room,
        deviceName: 'Room $room',
        pairingNonce: 'nonce',
        expiresAtMs:
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: 'trusted-$room',
    );

const _locked = BroadcastAccessSnapshot(
  unlocked: false,
  active: false,
  freeLimitMs: 7200000,
  usedMs: 7200000,
  remainingMs: 0,
  priceLabel: '€4,99',
  hasStorePrice: true,
  productId: BroadcastAccessConfig.productId,
);
