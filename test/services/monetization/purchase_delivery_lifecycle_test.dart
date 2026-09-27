import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:miucam/services/monetization/license_grant.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/license_token_fixture.dart';

void main() {
  for (final purchaseBeforeForeground in [false, true]) {
    test(
        'missed owned purchase recovers before ${purchaseBeforeForeground ? 'checkout' : 'foreground'}',
        () async {
      SharedPreferences.setMockInitialValues({});
      final fixture = await LicenseTokenFixture.create();
      final token = await fixture.token(claims: {
        'entitlementId': 'household-42',
        'transactionFingerprint': 'f' * 64
      });
      final store = _OwnedStore()
        ..owned = [
          _purchase(status: PurchaseStatus.purchased, pendingComplete: true)
        ];
      final verifier = _ControlledVerifier()..licenseToken = token;
      final gateway =
          InAppBroadcastPurchaseGateway(store: store, verifier: verifier);
      final service = BroadcastAccessService(
          await SharedPreferences.getInstance(),
          purchaseGateway: gateway,
          licenseGrantVerifier:
              LicenseGrantVerifier(publicKey: fixture.publicKey));
      expect((await service.snapshot()).unlocked, isFalse);
      final snapshot = purchaseBeforeForeground
          ? await service.unlockWithOneTimePurchase()
          : await service.reconcilePurchases();
      expect(snapshot.unlocked, isTrue);
      expect(service.licenseToken, token);
      expect(store.completedPurchases, 1);
      expect(store.buyCalls, 0);
      expect(store.restoreCalls, 0);
      expect(store.ownedQueries, 1);
      await service.reconcilePurchases();
      expect(store.ownedQueries, 1);
      await service.dispose();
      await store.dispose();
    });
  }

  test('owned pending state blocks checkout and reconciles after approval',
      () async {
    final store = _OwnedStore()
      ..owned = [_purchase(status: PurchaseStatus.pending)];
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _ControlledVerifier(),
        deliverPurchase: (_) async {});
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    final result = await gateway.purchase(
        productId: BroadcastAccessConfig.productId, priceLabel: '350 TL');
    expect(result.status, BroadcastPurchaseStatus.pending);
    expect(store.buyCalls, 0);
    store.owned = [
      _purchase(status: PurchaseStatus.purchased, pendingComplete: true)
    ];
    final approved = gateway.updates.first;
    await gateway.reconcilePurchases();
    expect((await approved).unlocksAccess, isTrue);
    expect(store.ownedQueries, 2,
        reason:
            'Pending approvals must not wait for the ordinary foreground throttle.');
  });

  test(
      'owned query failure blocks payment and empty restore has a typed result',
      () async {
    final store = _OwnedStore()..queryError = StateError('store offline');
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _ControlledVerifier(),
        deliverPurchase: (_) async {});
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    expect(
        (await gateway.purchase(
                productId: BroadcastAccessConfig.productId,
                priceLabel: '350 TL'))
            .status,
        BroadcastPurchaseStatus.error);
    expect(store.buyCalls, 0);
    store.queryError = null;
    expect(
        (await gateway.restore(productId: BroadcastAccessConfig.productId))
            .status,
        BroadcastPurchaseStatus.noPurchaseFound);
    expect(store.restoreCalls, 0);
  });

  test('checkout force-queries ownership even after an empty foreground query',
      () async {
    final store = _OwnedStore();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _ControlledVerifier(),
        deliverPurchase: (_) async {});
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    await gateway.reconcilePurchases();
    store.owned = [_purchase(status: PurchaseStatus.purchased)];
    expect(
        (await gateway.purchase(
                productId: BroadcastAccessConfig.productId,
                priceLabel: '350 TL'))
            .unlocksAccess,
        isTrue);
    expect(store.ownedQueries, 2);
    expect(store.buyCalls, 0);
  });

  test('foreground queries coalesce and throttle with monotonic time',
      () async {
    var elapsedMs = 0;
    final store = _OwnedStore()..queryGate = Completer<void>();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _ControlledVerifier(),
        deliverPurchase: (_) async {},
        monotonicNowMs: () => elapsedMs);
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    final first = gateway.reconcilePurchases();
    final second = gateway.reconcilePurchases();
    expect(store.ownedQueries, 1);
    store.queryGate!.complete();
    await Future.wait([first, second]);
    await gateway.reconcilePurchases();
    expect(store.ownedQueries, 1);
    elapsedMs += const Duration(minutes: 1).inMilliseconds;
    await gateway.reconcilePurchases();
    expect(store.ownedQueries, 2);
  });

  test('late owned-query completion cannot deliver after disposal', () async {
    final store = _OwnedStore()
      ..queryGate = Completer<void>()
      ..owned = [
        _purchase(status: PurchaseStatus.purchased, pendingComplete: true)
      ];
    final verifier = _ControlledVerifier();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store, verifier: verifier, deliverPurchase: (_) async {});
    final query = expectLater(gateway.reconcilePurchases(), throwsStateError);
    await gateway.dispose().timeout(const Duration(milliseconds: 200));
    await query;
    store.queryGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(verifier.calls, 0);
    expect(store.completedPurchases, 0);
    await store.dispose();
  });

  test('launched checkout stays exclusive until a terminal store result',
      () async {
    final store = _FakeInAppPurchaseStore();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _ControlledVerifier(),
        deliverPurchase: (_) async {},
        timeout: const Duration(milliseconds: 15));
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    Future<BroadcastPurchaseResult> buy() => gateway.purchase(
        productId: BroadcastAccessConfig.productId, priceLabel: '350 TL');
    expect((await buy()).status, BroadcastPurchaseStatus.pending);
    expect((await buy()).status, BroadcastPurchaseStatus.pending);
    expect(store.buyCalls, 1);
    final canceled = gateway.updates.first;
    store.emit([_purchase(status: PurchaseStatus.canceled)]);
    await canceled;
    expect((await buy()).status, BroadcastPurchaseStatus.pending);
    expect(store.buyCalls, 2);
  });

  test('a store sheet still open after timeout remains the only checkout',
      () async {
    final store = _FakeInAppPurchaseStore()..buyGate = Completer<bool>();
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: _ControlledVerifier(),
      deliverPurchase: (_) async {},
      timeout: const Duration(milliseconds: 15),
    );
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    Future<BroadcastPurchaseResult> buy() => gateway.purchase(
        productId: BroadcastAccessConfig.productId, priceLabel: '350 TL');

    expect((await buy()).status, BroadcastPurchaseStatus.pending);
    expect((await buy()).status, BroadcastPurchaseStatus.pending);
    expect(store.buyCalls, 1);

    final completed = gateway.updates.first;
    store.emit(
        [_purchase(status: PurchaseStatus.purchased, pendingComplete: true)]);
    expect((await completed).unlocksAccess, isTrue);
    store.buyGate!.complete(true);
    expect(store.completedPurchases, 1);
  });

  for (final failedWithException in [false, true]) {
    test('late store launch failure releases checkout: $failedWithException',
        () async {
      final store = _FakeInAppPurchaseStore()..buyGate = Completer<bool>();
      final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _ControlledVerifier(),
        deliverPurchase: (_) async {},
        timeout: const Duration(milliseconds: 15),
      );
      addTearDown(store.dispose);
      addTearDown(gateway.dispose);
      Future<BroadcastPurchaseResult> buy() => gateway.purchase(
          productId: BroadcastAccessConfig.productId, priceLabel: '350 TL');
      expect((await buy()).status, BroadcastPurchaseStatus.pending);
      final failed = gateway.updates.first;
      if (failedWithException) {
        store.buyGate!.completeError(StateError('store declined checkout'));
      } else {
        store.buyGate!.complete(false);
      }
      expect((await failed).status, BroadcastPurchaseStatus.error);
      store.buyGate = null;
      expect((await buy()).status, BroadcastPurchaseStatus.pending);
      expect(store.buyCalls, 2);
    });
  }

  test('late launch result from a canceled sheet cannot cancel a new sheet',
      () async {
    final firstSheet = Completer<bool>();
    final store = _FakeInAppPurchaseStore()..buyGate = firstSheet;
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: _ControlledVerifier(),
      deliverPurchase: (_) async {},
      timeout: const Duration(milliseconds: 15),
    );
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    Future<BroadcastPurchaseResult> buy() => gateway.purchase(
        productId: BroadcastAccessConfig.productId, priceLabel: '350 TL');
    expect((await buy()).status, BroadcastPurchaseStatus.pending);
    final canceled = gateway.updates.first;
    store.emit([_purchase(status: PurchaseStatus.canceled)]);
    expect((await canceled).status, BroadcastPurchaseStatus.canceled);

    store.buyGate = null;
    expect((await buy()).status, BroadcastPurchaseStatus.pending);
    firstSheet.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect((await buy()).status, BroadcastPurchaseStatus.pending);
    expect(store.buyCalls, 2);
  });

  for (final includesPending in [false, true]) {
    test(
        'open native sheet survives empty foreground and restore queries: '
        'pending query=$includesPending', () async {
      final store = _OwnedStore()
        ..includesPending = includesPending
        ..buyGate = Completer<bool>();
      final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _ControlledVerifier(),
        deliverPurchase: (_) async {},
        timeout: const Duration(milliseconds: 15),
      );
      addTearDown(store.dispose);
      addTearDown(gateway.dispose);
      Future<BroadcastPurchaseResult> buy() => gateway.purchase(
          productId: BroadcastAccessConfig.productId, priceLabel: '350 TL');
      expect((await buy()).status, BroadcastPurchaseStatus.pending);
      await gateway.reconcilePurchases(force: true);
      expect(
          (await gateway.restore(productId: BroadcastAccessConfig.productId))
              .status,
          BroadcastPurchaseStatus.pending);
      expect((await buy()).status, BroadcastPurchaseStatus.pending);
      expect(store.buyCalls, 1);
      final declined = gateway.updates.first;
      store.emit([_purchase(status: PurchaseStatus.error)]);
      expect((await declined).status, BroadcastPurchaseStatus.error);
      store.buyGate!.complete(false);
      store.buyGate = null;
      expect((await buy()).status, BroadcastPurchaseStatus.pending);
      expect(store.buyCalls, 2);
    });
  }

  test('unowned store transaction is never acknowledged', () async {
    final store = _FakeInAppPurchaseStore();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store, verifier: _ControlledVerifier());
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    final checkout = await gateway.purchase(
        productId: BroadcastAccessConfig.productId, priceLabel: '350 TL');
    expect(checkout.status, BroadcastPurchaseStatus.unavailable);
    expect(store.buyCalls, 0);
    final result = gateway.updates.first;
    store.emit(
        [_purchase(status: PurchaseStatus.purchased, pendingComplete: true)]);
    expect((await result).status, BroadcastPurchaseStatus.verificationFailed);
    expect(store.completedPurchases, 0);
  });

  test('native acknowledgement starts only after durable delivery', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = _FakeInAppPurchaseStore()..completeGate = Completer<void>();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store, verifier: _ControlledVerifier());
    final service = BroadcastAccessService(prefs, purchaseGateway: gateway);
    await service.snapshot();
    store.emit(
        [_purchase(status: PurchaseStatus.purchased, pendingComplete: true)]);
    await store.completeStarted.future;
    expect(
        (jsonDecode(prefs.getString('broadcast_access.entitlement_v1')!)
            as Map)['unlocked'],
        isTrue);
    expect((await service.snapshot()).unlocked, isTrue);
    await service.dispose().timeout(const Duration(milliseconds: 200));
    store.completeGate!.complete();
    await store.dispose();
  });

  test('duplicate paid store events deliver and acknowledge only once',
      () async {
    final store = _FakeInAppPurchaseStore();
    final verifier = _ControlledVerifier();
    var deliveries = 0;
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: verifier,
      deliverPurchase: (_) async {
        deliveries++;
      },
    );
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    final updates = gateway.updates.take(3).toList();
    store.emit(List.generate(
        3,
        (_) => _purchase(
            status: PurchaseStatus.purchased, pendingComplete: true)));
    expect((await updates).every((result) => result.unlocksAccess), isTrue);
    expect(deliveries, 1);
    expect(verifier.calls, 1);
    expect(store.completedPurchases, 1);
  });

  test('stalled acknowledgement cannot block gateway disposal', () async {
    final store = _FakeInAppPurchaseStore()..completeGate = Completer<void>();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _ControlledVerifier(),
        deliverPurchase: (_) async {});
    store.emit(
        [_purchase(status: PurchaseStatus.purchased, pendingComplete: true)]);
    await store.completeStarted.future;
    await gateway.dispose().timeout(const Duration(milliseconds: 200));
    store.completeGate!.complete();
    await store.dispose();
  });

  test('stalled verification disposal leaves transaction recoverable',
      () async {
    final store = _FakeInAppPurchaseStore();
    final verifier = _ControlledVerifier()..gate = Completer<void>();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store, verifier: verifier, deliverPurchase: (_) async {});
    store.emit(
        [_purchase(status: PurchaseStatus.purchased, pendingComplete: true)]);
    await verifier.entered.future;
    await gateway.dispose().timeout(const Duration(milliseconds: 200));
    verifier.gate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(store.completedPurchases, 0);
    await store.dispose();
  });

  test('timed out verification leaves queued store events usable', () async {
    final store = _FakeInAppPurchaseStore();
    final verifier = _ControlledVerifier()..gate = Completer<void>();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: verifier,
        verificationTimeout: const Duration(milliseconds: 20),
        deliverPurchase: (_) async {});
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    final failed = gateway.updates.first;
    store.emit(
        [_purchase(status: PurchaseStatus.purchased, pendingComplete: true)]);
    expect(
        (await failed).failureReason, BroadcastPurchaseFailureReason.transient);
    verifier.gate!.complete();
    verifier.gate = null;
    final retried = gateway.updates.first;
    store.emit(
        [_purchase(status: PurchaseStatus.purchased, pendingComplete: true)]);
    expect((await retried).unlocksAccess, isTrue);
    expect(store.completedPurchases, 1);
  });

  test('explicit restore revalidates formerly accepted evidence', () async {
    final store = _FakeInAppPurchaseStore();
    final verifier = _ControlledVerifier();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: verifier,
        deliverPurchase: (_) async {},
        timeout: const Duration(milliseconds: 60));
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    final first = gateway.updates.first;
    store.emit([_purchase(status: PurchaseStatus.purchased)]);
    expect((await first).unlocksAccess, isTrue);
    verifier.revoked = true;
    final restore = gateway.restore(productId: BroadcastAccessConfig.productId);
    store.emit([_purchase(status: PurchaseStatus.restored)]);
    expect((await restore).unlocksAccess, isFalse);
    expect(verifier.calls, 2);
  });

  for (final status in [PurchaseStatus.canceled, PurchaseStatus.error]) {
    test(
        '$status completes pending terminal transaction without granting access',
        () async {
      final store = _FakeInAppPurchaseStore();
      final verifier = _ControlledVerifier();
      final gateway =
          InAppBroadcastPurchaseGateway(store: store, verifier: verifier);
      addTearDown(store.dispose);
      addTearDown(gateway.dispose);
      final update = gateway.updates.first;
      store.emit([_purchase(status: status, pendingComplete: true)]);
      expect((await update).unlocksAccess, isFalse);
      expect(store.completedPurchases, 1);
      expect(verifier.calls, 0);
    });
  }

  test('pending approval survives UI timeout and prevents a second checkout',
      () async {
    final store = _FakeInAppPurchaseStore();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _ControlledVerifier(),
        deliverPurchase: (_) async {},
        timeout: const Duration(milliseconds: 15));
    addTearDown(store.dispose);
    addTearDown(gateway.dispose);
    final first = gateway.purchase(
        productId: BroadcastAccessConfig.productId, priceLabel: '350 TL');
    await store.buyStarted.future;
    store.emit([_purchase(status: PurchaseStatus.pending)]);
    expect((await first).status, BroadcastPurchaseStatus.pending);
    expect(
        (await gateway.purchase(
                productId: BroadcastAccessConfig.productId,
                priceLabel: '350 TL'))
            .status,
        BroadcastPurchaseStatus.pending);
    expect(store.buyCalls, 1);
    final late = gateway.updates.first;
    store.emit(
        [_purchase(status: PurchaseStatus.purchased, pendingComplete: true)]);
    expect((await late).unlocksAccess, isTrue);
    expect(store.completedPurchases, 1);
  });
}

class _ControlledVerifier implements BroadcastPurchaseVerifier {
  bool revoked = false;
  int calls = 0;
  String? licenseToken;
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<BroadcastPurchaseVerification> verify(PurchaseDetails purchase,
      {required String expectedProductId}) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    if (gate != null) await gate!.future;
    if (revoked) {
      return const BroadcastPurchaseVerification.rejected(
          source: 'google_play', reason: 'Store ownership revoked.');
    }
    return BroadcastPurchaseVerification.verified(
        source: 'google_play',
        fingerprint: 'f' * 64,
        entitlementId: 'household-42',
        licenseToken: licenseToken);
  }
}

PurchaseDetails _purchase({
  required PurchaseStatus status,
  String serverData = 'store-token',
  String localData = '{"purchaseState":0}',
  bool pendingComplete = false,
}) {
  final purchase = PurchaseDetails(
    purchaseID: 'order-1',
    productID: BroadcastAccessConfig.productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: localData,
      serverVerificationData: serverData,
      source: 'google_play',
    ),
    transactionDate: '1',
    status: status,
  );
  purchase.pendingCompletePurchase = pendingComplete;
  return purchase;
}

class _FakeInAppPurchaseStore implements InAppPurchaseStore {
  final _purchases = StreamController<List<PurchaseDetails>>.broadcast();
  final buyStarted = Completer<void>();
  int completeAttempts = 0;
  int buyCalls = 0;
  int restoreCalls = 0;
  Completer<void>? completeGate;
  Completer<bool>? buyGate;
  final completeStarted = Completer<void>();
  Future<ProductDetailsResponse>? delayedCatalog;
  int completeFailuresRemaining = 0;
  int completedPurchases = 0;

  void emit(List<PurchaseDetails> purchases) => _purchases.add(purchases);

  void emitError(Object error) =>
      _purchases.addError(error, StackTrace.current);

  Future<void> dispose() => _purchases.close();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _purchases.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> productIds,
  ) async =>
      delayedCatalog ??
      ProductDetailsResponse(
        productDetails: [
          ProductDetails(
            id: BroadcastAccessConfig.productId,
            title: 'Lifetime',
            description: 'Lifetime room access',
            price: '₺300,00',
            rawPrice: 300,
            currencyCode: 'TRY',
            currencySymbol: '₺',
          ),
        ],
        notFoundIDs: const [],
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCalls++;
    if (!buyStarted.isCompleted) buyStarted.complete();
    return buyGate == null ? true : await buyGate!.future;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completeAttempts++;
    if (!completeStarted.isCompleted) completeStarted.complete();
    if (completeGate != null) await completeGate!.future;
    if (completeFailuresRemaining > 0) {
      completeFailuresRemaining--;
      throw StateError('ack unavailable');
    }
    completedPurchases++;
  }
}

class _OwnedStore extends _FakeInAppPurchaseStore
    implements InAppPurchaseOwnedQueryStore {
  List<PurchaseDetails> owned = [];
  int ownedQueries = 0;
  Object? queryError;
  Completer<void>? queryGate;
  bool includesPending = true;
  @override
  bool get ownedQueryIncludesPending => includesPending;
  @override
  Future<List<PurchaseDetails>> queryOwnedPurchases(
      {bool includeFinished = true}) async {
    ownedQueries++;
    if (queryGate != null) await queryGate!.future;
    if (queryError != null) throw queryError!;
    return owned
        .where((purchase) =>
            includeFinished ||
            purchase.pendingCompletePurchase ||
            purchase.status == PurchaseStatus.pending)
        .toList();
  }
}
