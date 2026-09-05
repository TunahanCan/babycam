import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('room shutdown failure still disposes billing and its pending catalog',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = _Store()..availability = Completer<bool>().future;
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: TrustedBackendPurchaseVerifier(
        endpoint: Uri.parse('https://example.com/verify'),
      ),
    );
    final service = BroadcastAccessService(
      await SharedPreferences.getInstance(),
      purchaseGateway: gateway,
    );
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      broadcastAccess: service,
      broadcastAccessChanges: service.changes,
      onStop: () async => throw StateError('Native shutdown failed'),
    );
    final closed = runtime.states.drain<void>();
    await expectLater(runtime.dispose(), throwsStateError);
    await closed;
    expect(store.events.hasListener, isFalse);
    await store.events.close();
  });

  test('a stalled store cannot delay the room trial lock', () async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms': const Duration(hours: 2).inMilliseconds,
    });
    final store = _Store()..availability = Completer<bool>().future;
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: TrustedBackendPurchaseVerifier(
        endpoint: Uri.parse('https://example.com/verify'),
      ),
    );
    final service = BroadcastAccessService(
      await SharedPreferences.getInstance(),
      purchaseGateway: gateway,
    );
    addTearDown(service.dispose);
    addTearDown(store.events.close);
    final snapshot =
        await service.snapshot().timeout(const Duration(seconds: 1));
    expect(snapshot.isLocked, isTrue);
    expect(snapshot.hasStorePrice, isFalse);
    await expectLater(service.beginSession('viewer'),
        throwsA(isA<BroadcastAccessLockedException>()));
  });

  test('disposing a pending catalog cancels its timeout', () async {
    final availability = Completer<bool>();
    final store = _Store()..availability = availability.future;
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: TrustedBackendPurchaseVerifier(
          endpoint: Uri.parse('https://example.com/verify')),
    );
    final offer = gateway.loadOffer(productId: BroadcastAccessConfig.productId);
    final expectation = expectLater(offer, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await gateway.dispose();
    await expectation;
    availability.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(store.catalogCalls, 0);
    expect(gateway.cachedOffer, isNull);
    await store.events.close();
  });

  test('late catalog availability cannot open checkout after disposal',
      () async {
    final availability = Completer<bool>();
    final store = _Store()..availability = availability.future;
    final gateway = InAppBroadcastPurchaseGateway(
      store: store,
      verifier: TrustedBackendPurchaseVerifier(
        endpoint: Uri.parse('https://example.com/verify'),
      ),
    );
    final purchase = gateway.purchase(
      productId: BroadcastAccessConfig.productId,
      priceLabel: '350 TL',
    );
    await Future<void>.delayed(Duration.zero);
    await gateway.dispose();
    availability.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect((await purchase).unlocksAccess, isFalse);
    expect(store.catalogCalls, 0);
    expect(store.buyCalls, 0);
    await store.events.close();
  });

  for (final verifier in <BroadcastPurchaseVerifier>[
    const UnavailableBroadcastPurchaseVerifier('Missing configuration'),
    const StorePayloadPurchaseVerifier(),
    TrustedBackendPurchaseVerifier(
        endpoint: Uri.parse('http://example.com/verify')),
  ]) {
    test(
        'unconfigured verifier cannot open checkout or start restore: ${verifier.runtimeType}',
        () async {
      final store = _Store();
      final gateway =
          InAppBroadcastPurchaseGateway(store: store, verifier: verifier);
      final result = await gateway.purchase(
        productId: BroadcastAccessConfig.productId,
        priceLabel: BroadcastAccessConfig.oneTimePriceLabel,
      );
      final restored =
          await gateway.restore(productId: BroadcastAccessConfig.productId);
      expect(result.status, BroadcastPurchaseStatus.unavailable);
      expect(restored.status, BroadcastPurchaseStatus.unavailable);
      expect(store.buyCalls, 0);
      expect(store.restoreCalls, 0);
      expect(store.catalogCalls, 0);
      await gateway.dispose();
      await store.events.close();
    });
  }

  test(
      'configured lifetime checkout uses the store product and does not consume it',
      () async {
    final store = _Store();
    final gateway = InAppBroadcastPurchaseGateway(
        store: store,
        verifier: TrustedBackendPurchaseVerifier(
            endpoint: Uri.parse('https://example.com/verify')));
    final result = await gateway.purchase(
        productId: BroadcastAccessConfig.productId, priceLabel: '350 TL');
    expect(store.buyCalls, 1);
    expect(store.selected?.productDetails.id, 'miucam_lifetime_unlock_try_300');
    expect(store.selected?.productDetails.price, '₺350,00');
    // This fake declines to present the store sheet; no transaction is granted.
    expect(result.unlocksAccess, isFalse);
    await gateway.dispose();
    await store.events.close();
  });
}

class _Store implements InAppPurchaseStore {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  int buyCalls = 0;
  int restoreCalls = 0;
  int catalogCalls = 0;
  PurchaseParam? selected;
  Future<bool>? availability;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() => availability ?? Future.value(true);
  @override
  Future<ProductDetailsResponse> queryProductDetails(
      Set<String> productIds) async {
    catalogCalls++;
    return ProductDetailsResponse(productDetails: [
      ProductDetails(
          id: BroadcastAccessConfig.productId,
          title: 'Lifetime',
          description: 'Lifetime room broadcast',
          price: '₺350,00',
          rawPrice: 350,
          currencyCode: 'TRY',
          currencySymbol: '₺')
    ], notFoundIDs: []);
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyCalls++;
    selected = purchaseParam;
    return false;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}
}
