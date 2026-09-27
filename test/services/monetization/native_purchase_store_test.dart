import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
// Native channel contract fixtures exercise the pinned plugin's actual codec.
// ignore: implementation_imports
import 'package:in_app_purchase_storekit/src/sk2_pigeon.g.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => InAppPurchasePlatform.instance = _UnusedPlatform());

  test('Android acknowledgement preserves native failure for retry', () async {
    final previous = InAppPurchasePlatform.instance;
    final platform = _AndroidPlatform();
    InAppPurchasePlatform.instance = platform;
    addTearDown(() => InAppPurchasePlatform.instance = previous);
    final iap = _Iap();
    addTearDown(iap.events.close);
    final store = FlutterInAppPurchaseStore(iap);
    await expectLater(store.completePurchase(_purchase()), throwsStateError);
    platform.response = BillingResponse.ok;
    await store.completePurchase(_purchase());
    expect(platform.ackCalls, 2);
    expect(iap.ackCalls, 0,
        reason:
            'The generic Future<void> path discards Android BillingResult.');
  });

  test('Android owned query retains pending and unfinished purchases',
      () async {
    final previous = InAppPurchasePlatform.instance;
    InAppPurchasePlatform.instance = _AndroidPlatform();
    addTearDown(() => InAppPurchasePlatform.instance = previous);
    final addition = _AndroidAddition()
      ..purchases = [
        _androidPurchase('finished', acknowledged: true),
        _androidPurchase('unfinished'),
        _androidPurchase('pending', pending: true),
      ];
    final iap = _Iap()..addition = addition;
    addTearDown(iap.events.close);
    final store = FlutterInAppPurchaseStore(iap);
    expect(store.ownedQueryIncludesPending, isTrue);
    expect((await store.queryOwnedPurchases()).length, 3);
    expect(
        (await store.queryOwnedPurchases(includeFinished: false))
            .map((purchase) => purchase.purchaseID),
        ['unfinished', 'pending']);
    addition.error =
        IAPError(source: 'google_play', code: 'offline', message: '');
    await expectLater(store.queryOwnedPurchases(), throwsStateError);
    expect(iap.restoreCalls, 0);
  });

  test('StoreKit finished purchase recovers its JWS without account sync',
      () async {
    final fixture = _StoreKitFixture()..history = [_transaction(7)];
    fixture.restored = [_storeKitPurchase(7, 'verified.current.receipt')];
    final purchases = await fixture.store.queryOwnedPurchases();
    expect(purchases.single.purchaseID, '7');
    expect(purchases.single.verificationData.serverVerificationData,
        'verified.current.receipt');
    expect(purchases.single.pendingCompletePurchase, isFalse);
    expect(fixture.syncCalls, 0);
    expect(fixture.currentEntitlementQueries, 1);
  });

  test('StoreKit recovery keeps the unfinished transaction eligible to finish',
      () async {
    final fixture = _StoreKitFixture()
      ..history = [_transaction(7), _transaction(8)]
      ..unfinished = [_transaction(8, receipt: 'unfinished.signed.receipt')]
      ..restored = [
        _storeKitPurchase(7, 'finished.signed.receipt'),
        _storeKitPurchase(8, 'unfinished.signed.receipt'),
      ];
    final purchases = await fixture.store.queryOwnedPurchases();
    expect(purchases.length, 2);
    expect(
        purchases
            .singleWhere((p) => p.purchaseID == '8')
            .pendingCompletePurchase,
        isTrue);
    expect(
        purchases
            .singleWhere((p) => p.purchaseID == '7')
            .pendingCompletePurchase,
        isFalse);
    final unfinished =
        await fixture.store.queryOwnedPurchases(includeFinished: false);
    expect(unfinished.single.purchaseID, '8');
    expect(fixture.historyQueries, 1);
    expect(fixture.currentEntitlementQueries, 1);
    expect(fixture.syncCalls, 0);
  });

  test('StoreKit refunded history does not masquerade as an owned purchase',
      () async {
    final fixture = _StoreKitFixture()
      ..history = [
        _transaction(7,
            json: '{"revocationDate":1800000000000,"revocationReason":1}')
      ];
    expect(await fixture.store.queryOwnedPurchases(), isEmpty);
    expect(fixture.syncCalls, 0);
    final gateway = InAppBroadcastPurchaseGateway(
      store: fixture.store,
      verifier: _Verifier(),
      deliverPurchase: (_) async {},
      timeout: const Duration(milliseconds: 15),
    );
    addTearDown(gateway.dispose);
    expect(
        (await gateway.purchase(
          productId: BroadcastAccessConfig.productId,
          priceLabel: 'store price',
        ))
            .status,
        BroadcastPurchaseStatus.pending);
    expect(fixture.iap.buyCalls, 1,
        reason: 'A refunded purchase must not prevent a new store checkout.');
  });

  test('StoreKit new purchase is recovered alongside its refunded history',
      () async {
    final fixture = _StoreKitFixture()
      ..history = [
        _transaction(7, json: '{"revocationDate":1800000000000}'),
        _transaction(8),
      ]
      ..restored = [_storeKitPurchase(8, 'new.signed.receipt')];
    final purchases = await fixture.store.queryOwnedPurchases();
    expect(purchases.single.purchaseID, '8');
    expect(purchases.single.verificationData.serverVerificationData,
        'new.signed.receipt');
    expect(fixture.syncCalls, 0);
  });

  test('StoreKit missing or malformed history evidence never invents a receipt',
      () async {
    final fixture = _StoreKitFixture()
      ..history = [_transaction(7, json: 'malformed')];
    final purchases = await fixture.store.queryOwnedPurchases();
    expect(purchases.single.purchaseID, '7');
    expect(purchases.single.verificationData.serverVerificationData, isEmpty);
    expect(fixture.syncCalls, 0);
  });

  test('StoreKit receipt query failure remains retryable', () async {
    final fixture = _StoreKitFixture()
      ..history = [_transaction(7)]
      ..restoreFailure = true;
    await expectLater(
        fixture.store.queryOwnedPurchases(), throwsA(isA<PlatformException>()));
    fixture.restoreFailure = false;
    fixture.restored = [_storeKitPurchase(7, 'recovered.signed.receipt')];
    expect(
        (await fixture.store.queryOwnedPurchases())
            .single
            .verificationData
            .serverVerificationData,
        'recovered.signed.receipt');
    expect(fixture.syncCalls, 0);
  });

  for (final pending in [false, true]) {
    test(
        'StoreKit sync is explicit only; observed pending=$pending is retained',
        () async {
      final previous = InAppPurchasePlatform.instance;
      InAppPurchasePlatform.instance = InAppPurchaseStoreKitPlatform();
      addTearDown(() => InAppPurchasePlatform.instance = previous);
      var syncCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final method in ['transactions', 'unfinishedTransactions', 'sync']) {
        final channel = BasicMessageChannel<Object?>(
            'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchase2API.$method',
            const StandardMessageCodec());
        messenger.setMockDecodedMessageHandler<Object?>(channel, (_) async {
          if (method == 'sync') {
            syncCalls++;
            return <Object?>[null];
          }
          return <Object?>[<Object?>[]];
        });
        addTearDown(
            () => messenger.setMockDecodedMessageHandler(channel, null));
      }
      final iap = _Iap();
      final store = FlutterInAppPurchaseStore(iap);
      final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: _Verifier(),
        deliverPurchase: (_) async {},
      );
      addTearDown(iap.events.close);
      addTearDown(gateway.dispose);
      expect(store.ownedQueryIncludesPending, isFalse);
      if (pending) {
        final observed = gateway.updates.first;
        iap.events.add([_purchase(status: PurchaseStatus.pending)]);
        await observed;
      }
      await gateway.reconcilePurchases();
      expect(syncCalls, 0);
      expect(iap.restoreCalls, 0);
      final result =
          await gateway.restore(productId: BroadcastAccessConfig.productId);
      expect(syncCalls, 1);
      expect(iap.restoreCalls, 1);
      expect(
          result.status,
          pending
              ? BroadcastPurchaseStatus.pending
              : BroadcastPurchaseStatus.noPurchaseFound);
    });
  }
}

class _StoreKitFixture {
  _StoreKitFixture() {
    InAppPurchasePlatform.instance = InAppPurchaseStoreKitPlatform();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in [
      'transactions',
      'unfinishedTransactions',
      'restorePurchases',
      'sync'
    ]) {
      final channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchase2API.$method',
        InAppPurchase2API.pigeonChannelCodec,
      );
      messenger.setMockDecodedMessageHandler<Object?>(channel, (_) async {
        switch (method) {
          case 'transactions':
            historyQueries++;
            return <Object?>[history];
          case 'unfinishedTransactions':
            return <Object?>[unfinished];
          case 'restorePurchases':
            currentEntitlementQueries++;
            if (restoreFailure) {
              return <Object?>['offline', 'Unavailable', null];
            }
            if (restored.isNotEmpty) iap.events.add(restored);
            return <Object?>[null];
          default:
            syncCalls++;
            return <Object?>[null];
        }
      });
      addTearDown(() => messenger.setMockDecodedMessageHandler(channel, null));
    }
    addTearDown(iap.events.close);
  }

  final iap = _Iap();
  late final store = FlutterInAppPurchaseStore(iap);
  List<SK2TransactionMessage> history = [];
  List<SK2TransactionMessage> unfinished = [];
  List<PurchaseDetails> restored = [];
  bool restoreFailure = false;
  int historyQueries = 0;
  int currentEntitlementQueries = 0;
  int syncCalls = 0;
}

SK2TransactionMessage _transaction(int id, {String? receipt, String? json}) =>
    SK2TransactionMessage(
      id: id,
      originalId: id,
      productId: BroadcastAccessConfig.productId,
      purchaseDate: '2026-09-27T12:00:00Z',
      receiptData: receipt,
      jsonRepresentation: json ?? '{}',
      status: SK2PurchaseStatusMessage.purchased,
    );

SK2PurchaseDetails _storeKitPurchase(int id, String receipt) =>
    SK2PurchaseDetails(
      productID: BroadcastAccessConfig.productId,
      purchaseID: '$id',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: receipt,
        source: 'app_store',
      ),
      transactionDate: '2026-09-27T12:00:00Z',
      status: PurchaseStatus.restored,
    );

class _UnusedPlatform extends InAppPurchasePlatform {}

class _Iap implements InAppPurchase {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  InAppPurchaseAndroidPlatformAddition? addition;
  int ackCalls = 0;
  int restoreCalls = 0;
  int buyCalls = 0;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: [
          ProductDetails(
            id: BroadcastAccessConfig.productId,
            title: 'Family lifetime',
            description: 'One-time family purchase',
            price: '₺300,00',
            rawPrice: 300,
            currencyCode: 'TRY',
          ),
        ],
        notFoundIDs: const [],
      );
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCalls++;
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls++;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    ackCalls++;
  }

  @override
  T getPlatformAddition<T extends InAppPurchasePlatformAddition?>() =>
      addition as T;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AndroidPlatform extends InAppPurchaseAndroidPlatform {
  _AndroidPlatform() : super(manager: _Manager());
  BillingResponse response = BillingResponse.error;
  int ackCalls = 0;
  @override
  Future<BillingResultWrapper> completePurchase(
      PurchaseDetails purchase) async {
    ackCalls++;
    return BillingResultWrapper(responseCode: response);
  }
}

class _Manager implements BillingClientManager {
  @override
  Stream<PurchasesResultWrapper> get purchasesUpdatedStream =>
      const Stream.empty();
  @override
  Stream<UserChoiceDetailsWrapper> get userChoiceDetailsStream =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AndroidAddition extends InAppPurchaseAndroidPlatformAddition {
  _AndroidAddition() : super(_Manager());
  List<GooglePlayPurchaseDetails> purchases = [];
  IAPError? error;
  @override
  Future<QueryPurchaseDetailsResponse> queryPastPurchases(
          {String? applicationUserName}) async =>
      QueryPurchaseDetailsResponse(pastPurchases: purchases, error: error);
}

GooglePlayPurchaseDetails _androidPurchase(String id,
        {bool acknowledged = false, bool pending = false}) =>
    GooglePlayPurchaseDetails.fromPurchase(PurchaseWrapper(
      orderId: id,
      packageName: 'test.package',
      purchaseTime: 1,
      purchaseToken: 'synthetic-$id',
      signature: 'synthetic-signature',
      products: const [BroadcastAccessConfig.productId],
      isAutoRenewing: false,
      originalJson: '{}',
      isAcknowledged: acknowledged,
      purchaseState: pending
          ? PurchaseStateWrapper.pending
          : PurchaseStateWrapper.purchased,
    )).single;

PurchaseDetails _purchase({PurchaseStatus status = PurchaseStatus.purchased}) =>
    PurchaseDetails(
      productID: BroadcastAccessConfig.productId,
      verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: 'synthetic-receipt',
          source: 'app_store'),
      transactionDate: '1',
      status: status,
    );

class _Verifier implements BroadcastPurchaseVerifier {
  @override
  Future<BroadcastPurchaseVerification> verify(PurchaseDetails purchase,
          {required String expectedProductId}) async =>
      const BroadcastPurchaseVerification.rejected(
          source: 'app_store',
          reason: 'No completed transaction in this test.');
}
