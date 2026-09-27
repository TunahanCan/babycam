import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart'
    show InAppPurchasePlatform;
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'broadcast_access_models.dart';

class FlutterInAppPurchaseStore
    implements InAppPurchaseStore, InAppPurchaseOwnedQueryStore {
  FlutterInAppPurchaseStore([InAppPurchase? inAppPurchase])
      : _iap = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> productIds) =>
      _iap.queryProductDetails(productIds);

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      _iap.buyNonConsumable(purchaseParam: purchaseParam);

  @override
  Future<void> restorePurchases() async {
    if (InAppPurchasePlatform.instance is InAppPurchaseStoreKitPlatform &&
        InAppPurchaseStoreKitPlatform.isStoreKit2Enabled) {
      // Only an explicit Restore action may show Apple's account-sync UI.
      // Silent lifecycle reconciliation uses current transactions below.
      await AppStore().sync();
    }
    await _iap.restorePurchases();
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    final platform = InAppPurchasePlatform.instance;
    if (platform is InAppPurchaseAndroidPlatform) {
      // The cross-platform Future<void> API discards Android's BillingResult.
      // A non-OK ack must remain eligible for retry, never enter our ack cache.
      final result = await platform.completePurchase(purchase);
      if (result.responseCode != BillingResponse.ok) {
        throw StateError(
            'Store acknowledgement failed: ${result.responseCode.name}');
      }
      return;
    }
    await _iap.completePurchase(purchase);
  }

  @override
  bool get ownedQueryIncludesPending =>
      InAppPurchasePlatform.instance is InAppPurchaseAndroidPlatform;

  @override
  Future<List<PurchaseDetails>> queryOwnedPurchases(
      {bool includeFinished = true}) async {
    final platform = InAppPurchasePlatform.instance;
    if (platform is InAppPurchaseAndroidPlatform) {
      final response = await _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
          .queryPastPurchases();
      if (response.error != null) {
        throw StateError(
            'Owned purchase query failed: ${response.error!.code}');
      }
      return response.pastPurchases
          .where((purchase) =>
              includeFinished ||
              purchase.pendingCompletePurchase ||
              purchase.status == PurchaseStatus.pending)
          .toList(growable: false);
    }
    if (platform is InAppPurchaseStoreKitPlatform &&
        InAppPurchaseStoreKitPlatform.isStoreKit2Enabled) {
      final unfinished = await SK2Transaction.unfinishedTransactions();
      final transactions = includeFinished
          ? await SK2Transaction.transactions()
          : <SK2Transaction>[];
      final pendingIds =
          unfinished.map((transaction) => transaction.id).toSet();
      final byId = <String, SK2Transaction>{
        for (final transaction in transactions) transaction.id: transaction,
        for (final transaction in unfinished) transaction.id: transaction,
      };
      final purchases = byId.values
          .map((transaction) => SK2PurchaseDetails(
                productID: transaction.productId,
                purchaseID: transaction.id,
                transactionDate: transaction.purchaseDate,
                appAccountToken: transaction.appAccountToken,
                status: pendingIds.contains(transaction.id)
                    ? PurchaseStatus.purchased
                    : PurchaseStatus.restored,
                verificationData: PurchaseVerificationData(
                  localVerificationData: transaction.jsonRepresentation ?? '',
                  serverVerificationData: transaction.receiptData ?? '',
                  source: 'app_store',
                ),
              ))
          .toList(growable: false);
      if (includeFinished &&
          purchases.any((purchase) =>
              purchase.verificationData.serverVerificationData.isEmpty)) {
        // Locked StoreKit plugin 0.4.10+1 omits JWS from transactions(). Its
        // SK2 restore wrapper enumerates Transaction.currentEntitlements and
        // publishes JWS without calling AppStore.sync or opening a sign-in UI.
        // Keep the original metadata when no receipt arrives: the gateway
        // fails verification and blocks a second checkout instead of treating
        // a potentially owned product as absent.
        final recovered = <String, PurchaseDetails>{};
        final receiptArrived = Completer<void>();
        final listener = _iap.purchaseStream.listen((updates) {
          for (final purchase in updates) {
            if (purchase.purchaseID != null &&
                byId.containsKey(purchase.purchaseID) &&
                purchase.verificationData.source == 'app_store' &&
                purchase.verificationData.serverVerificationData.isNotEmpty) {
              recovered[purchase.purchaseID!] = purchase;
              if (!receiptArrived.isCompleted) receiptArrived.complete();
            }
          }
        });
        try {
          await SK2Transaction.restorePurchases()
              .timeout(const Duration(seconds: 5));
          if (recovered.isEmpty) {
            await receiptArrived.future
                .timeout(const Duration(milliseconds: 250), onTimeout: () {});
          }
          // Callback delivery uses a broadcast stream; drain its microtasks
          // before the checkout decision reads the completed query.
          await Future<void>.delayed(Duration.zero);
          if (recovered.isNotEmpty) {
            return {
              ...recovered,
              for (final purchase
                  in purchases.where((p) => p.pendingCompletePurchase))
                purchase.purchaseID!: purchase,
            }.values.toList(growable: false);
          }
        } finally {
          await listener.cancel();
        }
      }
      return purchases;
    }
    return const [];
  }
}
