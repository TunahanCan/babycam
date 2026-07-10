import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mimicam/services/monetization/broadcast_access_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('free broadcast time uses monotonic active wall time', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final clock = _Clock();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
      freeLimit: const Duration(minutes: 5),
    );
    addTearDown(service.dispose);

    await service.beginSession('a');
    await service.beginSession('b');
    clock.advance(const Duration(minutes: 2));
    await service.endSession('a');
    clock.advance(const Duration(minutes: 3));
    final activeLocked = await service.snapshot();

    expect(activeLocked.isLocked, isTrue);
    expect(activeLocked.usedMs, const Duration(minutes: 5).inMilliseconds);

    await service.endSession('b');
    await expectLater(
      service.beginSession('c'),
      throwsA(isA<BroadcastAccessLockedException>()),
    );
  });

  test('unfinished active checkpoint is recovered after process restart',
      () async {
    final clock = _Clock();
    final checkpoint = clock.now().millisecondsSinceEpoch - 10000;
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms': 2000,
      'broadcast_access.active_marker': true,
      'broadcast_access.active_checkpoint_wall_ms': checkpoint,
      'broadcast_access.last_observed_wall_ms': checkpoint,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
      freeLimit: const Duration(minutes: 5),
      checkpointInterval: const Duration(seconds: 15),
    );
    addTearDown(service.dispose);

    final snapshot = await service.snapshot();

    expect(snapshot.usedMs, 12000);
    expect(prefs.getBool('broadcast_access.active_marker'), isFalse);
    expect(
      prefs.containsKey('broadcast_access.active_checkpoint_wall_ms'),
      isFalse,
    );
  });

  test('wall-clock rollback charges one bounded checkpoint interval', () async {
    final clock = _Clock();
    final futureCheckpoint =
        clock.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'broadcast_access.active_marker': true,
      'broadcast_access.active_checkpoint_wall_ms': futureCheckpoint,
      'broadcast_access.last_observed_wall_ms': futureCheckpoint,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
      now: clock.now,
      monotonicNowMs: clock.monotonicNowMs,
      checkpointInterval: const Duration(seconds: 15),
    );
    addTearDown(service.dispose);

    expect((await service.snapshot()).usedMs, 15000);
  });

  test('one-time purchase persists complete trusted entitlement evidence',
      () async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms': const Duration(minutes: 5).inMilliseconds,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(
        result: _verifiedResult(),
      ),
      freeLimit: const Duration(minutes: 5),
    );
    addTearDown(service.dispose);

    expect((await service.snapshot()).isLocked, isTrue);
    final unlocked = await service.unlockWithOneTimePurchase();

    expect(unlocked.unlocked, isTrue);
    expect(unlocked.purchaseVerificationSource, 'google_play');
    expect(
      unlocked.purchaseVerificationAuthority,
      trustedBackendVerificationAuthority,
    );
    expect(unlocked.purchaseVerificationFingerprint, hasLength(64));
    expect(unlocked.entitlementId, 'household-42');
    expect(unlocked.purchaseVerifiedAtMs, isNotNull);
    await expectLater(service.beginSession('after-purchase'), completes);
  });

  test('bare local unlocked boolean fails closed without trusted evidence',
      () async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.unlocked': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(),
    );
    addTearDown(service.dispose);

    expect((await service.snapshot()).unlocked, isFalse);
  });

  test('unverified purchase cannot persist lifetime entitlement', () async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms': const Duration(minutes: 5).inMilliseconds,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(
      prefs,
      purchaseGateway: _FakePurchaseGateway(
        result: const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.purchased,
        ),
      ),
      freeLimit: const Duration(minutes: 5),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.unlockWithOneTimePurchase(),
      throwsA(isA<BroadcastPurchaseException>()),
    );
    expect((await service.snapshot()).unlocked, isFalse);
  });

  test('late verified gateway update unlocks without an active UI request',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gateway = _FakePurchaseGateway();
    final service = BroadcastAccessService(prefs, purchaseGateway: gateway);
    addTearDown(service.dispose);
    final changed = service.changes.first;

    gateway.emit(_verifiedResult(status: BroadcastPurchaseStatus.restored));
    final snapshot = await changed;

    expect(snapshot.unlocked, isTrue);
    expect(snapshot.entitlementId, 'household-42');
  });

  test('localized ProductDetails price is exposed by access snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gateway = _FakePurchaseGateway(
      offer: const BroadcastProductOffer(
        productId: BroadcastAccessConfig.productId,
        localizedPrice: '€4,99',
        rawPrice: 4.99,
        currencyCode: 'EUR',
      ),
    );
    final service = BroadcastAccessService(prefs, purchaseGateway: gateway);
    addTearDown(service.dispose);

    expect((await service.snapshot()).priceLabel, '€4,99');
  });

  test('local store envelope preflight never claims authenticity', () async {
    const verifier = StorePayloadPurchaseVerifier();
    final missing = _purchase(
      status: PurchaseStatus.purchased,
      serverData: '',
      localData: '',
    );
    final structurallyValid = _purchase(status: PurchaseStatus.purchased);

    final missingResult = await verifier.verify(
      missing,
      expectedProductId: BroadcastAccessConfig.productId,
    );
    final validEnvelopeResult = await verifier.verify(
      structurallyValid,
      expectedProductId: BroadcastAccessConfig.productId,
    );

    expect(missingResult.verified, isFalse);
    expect(validEnvelopeResult.verified, isFalse);
    expect(validEnvelopeResult.reason, contains('backend'));
  });

  test('purchase stream handles pending timeout then late verified completion',
      () async {
    final store = _FakeInAppPurchaseStore();
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const _AcceptingVerifier(),
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(gateway.dispose);
    final lateResult =
        gateway.updates.firstWhere((result) => result.unlocksAccess);

    final purchaseFuture = gateway.purchase(
      productId: BroadcastAccessConfig.productId,
      priceLabel: 'fallback',
    );
    await store.buyStarted.future;
    store.emit([_purchase(status: PurchaseStatus.pending)]);

    expect((await purchaseFuture).status, BroadcastPurchaseStatus.pending);

    final purchased = _purchase(
      status: PurchaseStatus.purchased,
      pendingComplete: true,
    );
    store.emit([purchased]);
    expect((await lateResult).unlocksAccess, isTrue);
    expect(store.completedPurchases, 1);

    final duplicate =
        gateway.updates.firstWhere((result) => result.unlocksAccess);
    store.emit([purchased]);
    await duplicate;
    expect(store.completedPurchases, 1);
  });

  test('restored startup transaction is processed without restore UI request',
      () async {
    final store = _FakeInAppPurchaseStore();
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const _AcceptingVerifier(),
    );
    addTearDown(gateway.dispose);
    final update = gateway.updates.firstWhere((result) => result.unlocksAccess);

    store.emit([
      _purchase(
        status: PurchaseStatus.restored,
        pendingComplete: true,
      ),
    ]);

    expect((await update).status, BroadcastPurchaseStatus.restored);
    expect(store.completedPurchases, 1);
  });

  test('purchase stream errors become observable results', () async {
    final store = _FakeInAppPurchaseStore();
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const _AcceptingVerifier(),
    );
    addTearDown(gateway.dispose);
    final update = gateway.updates.firstWhere(
      (result) => result.status == BroadcastPurchaseStatus.error,
    );

    store.emitError(StateError('billing disconnected'));

    expect((await update).message, contains('billing disconnected'));
  });

  test('store transaction is not acknowledged when verification fails',
      () async {
    final store = _FakeInAppPurchaseStore();
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const StorePayloadPurchaseVerifier(),
    );
    addTearDown(gateway.dispose);
    final update = gateway.updates.firstWhere(
      (result) => result.status == BroadcastPurchaseStatus.verificationFailed,
    );

    store.emit([
      _purchase(
        status: PurchaseStatus.purchased,
        pendingComplete: true,
      ),
    ]);

    expect((await update).verified, isFalse);
    expect(store.completedPurchases, 0);
  });

  test('ack failure does not cache entitlement and store redelivery retries',
      () async {
    final store = _FakeInAppPurchaseStore()..completeFailuresRemaining = 1;
    addTearDown(store.dispose);
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: const _AcceptingVerifier(),
    );
    addTearDown(gateway.dispose);
    final failed = gateway.updates.firstWhere(
      (result) => result.status == BroadcastPurchaseStatus.verificationFailed,
    );
    final purchase = _purchase(
      status: PurchaseStatus.purchased,
      pendingComplete: true,
    );

    store.emit([purchase]);
    await failed;
    final retried =
        gateway.updates.firstWhere((result) => result.unlocksAccess);
    store.emit([purchase]);

    expect((await retried).unlocksAccess, isTrue);
    expect(store.completeAttempts, 2);
    expect(store.completedPurchases, 1);
  });

  test('trusted backend verifier sends evidence and validates response binding',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<Map<String, Object?>>();
    unawaited(server.forEach((request) async {
      final body = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      received.complete(body);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'verified': true,
        'productId': BroadcastAccessConfig.productId,
        'source': 'google_play',
        'transactionFingerprint': 'a' * 64,
        'entitlementId': 'household-42',
      }));
      await request.response.close();
    }));
    final verifier = TrustedBackendPurchaseVerifier(
      endpoint: Uri.parse(
        'http://${InternetAddress.loopbackIPv4.address}:${server.port}/verify',
      ),
      allowInsecureEndpointForTesting: true,
    );

    final result = await verifier.verify(
      _purchase(status: PurchaseStatus.purchased),
      expectedProductId: BroadcastAccessConfig.productId,
    );

    expect(result.verified, isTrue);
    expect(result.entitlementId, 'household-42');
    expect((await received.future)['serverVerificationData'], 'store-token');
  });
}

BroadcastPurchaseResult _verifiedResult({
  BroadcastPurchaseStatus status = BroadcastPurchaseStatus.purchased,
}) =>
    BroadcastPurchaseResult(
      status: status,
      verified: true,
      verificationSource: 'google_play',
      verificationFingerprint: 'f' * 64,
      entitlementId: 'household-42',
    );

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

class _Clock {
  DateTime _now = DateTime(2026, 1, 1, 12);
  int _monotonicMs = 0;

  DateTime now() => _now;
  int monotonicNowMs() => _monotonicMs;

  void advance(Duration duration) {
    _now = _now.add(duration);
    _monotonicMs += duration.inMilliseconds;
  }
}

class _FakePurchaseGateway
    implements
        BroadcastPurchaseGateway,
        BroadcastPurchaseUpdateSource,
        BroadcastProductOfferGateway {
  _FakePurchaseGateway({
    BroadcastPurchaseResult? result,
    this.offer,
  }) : result = result ?? _verifiedResult();

  final BroadcastPurchaseResult result;
  final BroadcastProductOffer? offer;
  final _updates = StreamController<BroadcastPurchaseResult>.broadcast();

  void emit(BroadcastPurchaseResult result) => _updates.add(result);

  @override
  Stream<BroadcastPurchaseResult> get updates => _updates.stream;

  @override
  BroadcastProductOffer? get cachedOffer => offer;

  @override
  Future<BroadcastProductOffer?> loadOffer({required String productId}) async =>
      offer;

  @override
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  }) async =>
      result;

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async =>
      result;

  @override
  Future<void> dispose() => _updates.close();
}

class _FakeInAppPurchaseStore implements InAppPurchaseStore {
  final _purchases = StreamController<List<PurchaseDetails>>.broadcast();
  final buyStarted = Completer<void>();
  int completeAttempts = 0;
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
    if (!buyStarted.isCompleted) buyStarted.complete();
    return true;
  }

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completeAttempts++;
    if (completeFailuresRemaining > 0) {
      completeFailuresRemaining--;
      throw StateError('ack unavailable');
    }
    completedPurchases++;
  }
}

class _AcceptingVerifier implements BroadcastPurchaseVerifier {
  const _AcceptingVerifier();

  @override
  Future<BroadcastPurchaseVerification> verify(
    PurchaseDetails purchase, {
    required String expectedProductId,
  }) async =>
      BroadcastPurchaseVerification.verified(
        source: purchase.verificationData.source,
        fingerprint: 'f' * 64,
        entitlementId: 'household-42',
      );
}
