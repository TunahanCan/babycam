import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
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

class _UnusedPlatform extends InAppPurchasePlatform {}

class _Iap implements InAppPurchase {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  InAppPurchaseAndroidPlatformAddition? addition;
  int ackCalls = 0;
  int restoreCalls = 0;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() async => true;
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
