import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/async/serialized_async_executor.dart';
import 'broadcast_access_models.dart';
import 'in_app_purchase_store.dart';
import 'license_grant.dart';
import 'purchase_verification.dart';

/// Owns the store stream for its whole lifetime, independently of any active
/// purchase sheet. Late and restored transactions therefore still reach the
/// authoritative entitlement owner.
class InAppBroadcastPurchaseGateway
    implements
        BroadcastPurchaseGateway,
        BroadcastPurchaseUpdateSource,
        BroadcastProductOfferGateway,
        BroadcastPurchaseDeliveryGateway,
        BroadcastEntitlementRefreshGateway,
        BroadcastOwnedPurchaseGateway {
  InAppBroadcastPurchaseGateway({
    InAppPurchase? inAppPurchase,
    InAppPurchaseStore? store,
    BroadcastPurchaseVerifier? verifier,
    this.expectedProductId = BroadcastAccessConfig.productId,
    this.timeout = const Duration(minutes: 2),
    this.catalogTimeout = const Duration(seconds: 10),
    this.verificationTimeout = const Duration(seconds: 20),
    this.completionTimeout = const Duration(seconds: 10),
    BroadcastPurchaseDelivery? deliverPurchase,
    LicenseGrantVerifier? licenseGrantVerifier,
    String? storeSource,
    this.reconciliationInterval = const Duration(minutes: 1),
    this.catalogCacheDuration = const Duration(minutes: 15),
    int Function()? monotonicNowMs,
  })  : _store = store ?? FlutterInAppPurchaseStore(inAppPurchase),
        _verifier = verifier ?? defaultBroadcastPurchaseVerifier(),
        _deliverPurchase = deliverPurchase,
        _licenseGrantVerifier = licenseGrantVerifier ?? LicenseGrantVerifier(),
        _storeSource = storeSource ??
            (Platform.isIOS || Platform.isMacOS ? 'app_store' : 'google_play'),
        _monotonicNowOverride = monotonicNowMs {
    _subscription = _store.purchaseStream.listen(
      _enqueuePurchases,
      onError: (Object error, StackTrace stackTrace) {
        _enqueueStreamError(error);
      },
    );
  }

  final InAppPurchaseStore _store;
  final BroadcastPurchaseVerifier _verifier;
  final String expectedProductId;
  final Duration timeout;
  final Duration catalogTimeout;
  final Duration verificationTimeout;
  final Duration completionTimeout;
  BroadcastPurchaseDelivery? _deliverPurchase;
  final LicenseGrantVerifier _licenseGrantVerifier;
  final String _storeSource;
  final Duration reconciliationInterval;
  final Duration catalogCacheDuration;
  final int Function()? _monotonicNowOverride;
  final _reconciliationClock = Stopwatch()..start();
  Future<void>? _reconciliation;
  int? _lastReconciliationMs;
  bool _lastQueryIncludedFinished = false;
  bool? _lastQueryHadProduct;
  final _updates = StreamController<BroadcastPurchaseResult>.broadcast();
  final _processedEvidence = <String, BroadcastPurchaseResult>{};
  final _offers = <String, ProductDetails>{};
  final _offerFetchedAtMs = <String, int>{};
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Completer<BroadcastPurchaseResult>? _active;
  final _events = SerializedAsyncExecutor();
  final _closed = Completer<void>();
  Future<BroadcastProductOffer?>? _offerLoad;
  bool _disposed = false;
  bool _pendingStoreApproval = false;
  bool _checkoutAwaitingResult = false;
  int _checkoutGeneration = 0;
  int? _nativeCheckoutGeneration;
  bool _restoring = false;

  @override
  Future<void> reconcilePurchases(
      {bool includeFinished = true, bool force = false}) async {
    final store = _store;
    if (_disposed ||
        store is! InAppPurchaseOwnedQueryStore ||
        _deliverPurchase == null) {
      return;
    }
    final ongoing = _reconciliation;
    if (ongoing != null) {
      await ongoing;
      if (!includeFinished || _lastQueryIncludedFinished) return;
    }
    final nowMs = _monotonicNowMs();
    final previousMs = _lastReconciliationMs;
    if (!force &&
        !_pendingStoreApproval &&
        !_checkoutAwaitingResult &&
        previousMs != null &&
        nowMs - previousMs < reconciliationInterval.inMilliseconds &&
        (!includeFinished || _lastQueryIncludedFinished)) {
      return;
    }
    _lastReconciliationMs = nowMs;
    late final Future<void> operation;
    operation = (() async {
      final purchases = await _awaitStore(
        () => (store as InAppPurchaseOwnedQueryStore)
            .queryOwnedPurchases(includeFinished: includeFinished),
        catalogTimeout,
      );
      _lastQueryIncludedFinished = includeFinished;
      final relevant = purchases
          .where((purchase) => purchase.productID == expectedProductId)
          .toList();
      _lastQueryHadProduct = relevant.isNotEmpty;
      if (relevant.isEmpty &&
          _nativeCheckoutGeneration == null &&
          (store as InAppPurchaseOwnedQueryStore).ownedQueryIncludesPending) {
        _pendingStoreApproval = false;
        _finishCheckout();
      }
      await _events.run(() => _handlePurchases(relevant));
    })()
        .whenComplete(() {
      if (identical(_reconciliation, operation)) _reconciliation = null;
    });
    _reconciliation = operation;
    await operation;
  }

  @override
  bool get checkoutConfigured => isPurchaseVerifierConfigured(_verifier);

  @override
  void attachDeliveryHandler(BroadcastPurchaseDelivery handler) {
    if (_deliverPurchase != null && _deliverPurchase != handler) {
      throw StateError('A purchase gateway must have one entitlement owner.');
    }
    _deliverPurchase = handler;
  }

  @override
  void detachDeliveryHandler(BroadcastPurchaseDelivery handler) {
    if (_deliverPurchase == handler) _deliverPurchase = null;
  }

  @override
  Future<BroadcastPurchaseResult> refreshLicense(String licenseToken) async {
    final verifier = _verifier;
    if (_disposed || verifier is! BroadcastLicenseRefresher) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        failureReason: BroadcastPurchaseFailureReason.configuration,
      );
    }
    try {
      final verification = await _awaitStore(
        () => (verifier as BroadcastLicenseRefresher).refreshLicense(
          licenseToken,
          expectedProductId: expectedProductId,
        ),
        verificationTimeout,
      );
      return _verificationResult(
          verification, BroadcastPurchaseStatus.restored);
    } catch (error) {
      if (error is TimeoutException &&
          _verifier is CancellableBroadcastPurchaseVerifier) {
        (_verifier as CancellableBroadcastPurchaseVerifier).cancelPending();
      }
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.verificationFailed,
        failureReason: BroadcastPurchaseFailureReason.transient,
        message: 'License refresh is temporarily unavailable.',
      );
    }
  }

  @override
  Stream<BroadcastPurchaseResult> get updates => _updates.stream;

  @override
  BroadcastProductOffer? get cachedOffer {
    if (_offers.isEmpty) return null;
    final product = _offers.values.first;
    return _isOfferFresh(product.id) ? _toOffer(product) : null;
  }

  int _monotonicNowMs() =>
      _monotonicNowOverride?.call() ?? _reconciliationClock.elapsedMilliseconds;

  bool _isOfferFresh(String productId) {
    final fetchedAt = _offerFetchedAtMs[productId];
    if (fetchedAt == null) return false;
    final elapsed = _monotonicNowMs() - fetchedAt;
    return elapsed >= 0 && elapsed < catalogCacheDuration.inMilliseconds;
  }

  @override
  Future<BroadcastProductOffer?> loadOffer({required String productId}) {
    if (_disposed || !isPurchaseVerifierConfigured(_verifier)) {
      return Future.value(null);
    }
    final cached = _offers[productId];
    if (cached != null && _isOfferFresh(productId)) {
      return Future.value(_toOffer(cached));
    }
    final loading = _offerLoad;
    if (loading != null) return loading;
    late final Future<BroadcastProductOffer?> operation;
    operation = _loadOffer(productId).whenComplete(() {
      if (identical(_offerLoad, operation)) _offerLoad = null;
    });
    _offerLoad = operation;
    return operation;
  }

  Future<BroadcastProductOffer?> _loadOffer(String productId) async {
    if (_disposed || !await _awaitStore(_store.isAvailable, catalogTimeout)) {
      return null;
    }
    final response = await _awaitStore(
      () => _store.queryProductDetails({productId}),
      catalogTimeout,
    );
    if (_disposed) return null;
    for (final product in response.productDetails) {
      _offers[product.id] = product;
      _offerFetchedAtMs[product.id] = _monotonicNowMs();
    }
    final product = _offers[productId];
    return product == null || !_isOfferFresh(productId)
        ? null
        : _toOffer(product);
  }

  @override
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  }) async {
    if (_disposed) return _disposedResult;
    if (!isPurchaseVerifierConfigured(_verifier)) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message:
            'Purchase verification is not configured; checkout was not opened.',
      );
    }
    if (productId != expectedProductId) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message: 'Purchase product does not match the configured entitlement.',
      );
    }
    if (_deliverPurchase == null) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        failureReason: BroadcastPurchaseFailureReason.configuration,
        message:
            'No durable entitlement owner is attached; checkout was not opened.',
      );
    }
    if (_active != null || _pendingStoreApproval || _checkoutAwaitingResult) {
      return _pendingResult;
    }
    final completer = _begin();
    try {
      await reconcilePurchases(force: true);
      if (completer.isCompleted) return completer.future;
      if (_pendingStoreApproval || _checkoutAwaitingResult) {
        _publishAndComplete(_pendingResult);
        return completer.future;
      }
      final available = await _awaitStore(_store.isAvailable, catalogTimeout);
      if (completer.isCompleted) return completer.future;
      if (!available) {
        _publishAndComplete(const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.unavailable,
          message: 'Store is not available on this device.',
        ));
      } else {
        final offer = await loadOffer(productId: productId);
        if (completer.isCompleted) return completer.future;
        final product = _offers[productId];
        if (offer == null || product == null) {
          _publishAndComplete(const BroadcastPurchaseResult(
            status: BroadcastPurchaseStatus.unavailable,
            message: 'Purchase product is not configured.',
          ));
        } else {
          final verifier = _verifier;
          if (verifier is BroadcastCheckoutPreflight) {
            final key = _licenseGrantVerifier.publicKeyBase64Url;
            final ready = key != null &&
                await _awaitStore(
                  () => (verifier as BroadcastCheckoutPreflight).preflight(
                      productId: productId,
                      source: _storeSource,
                      licensePublicKey: key),
                  verificationTimeout,
                );
            if (!ready) {
              _publishAndComplete(const BroadcastPurchaseResult(
                status: BroadcastPurchaseStatus.unavailable,
                failureReason: BroadcastPurchaseFailureReason.configuration,
                message:
                    'Purchase backend or license verification is not ready.',
              ));
              return completer.future;
            }
            if (completer.isCompleted) return completer.future;
          }
          final launched =
              await _awaitStore(() => _openCheckout(product), timeout);
          if (completer.isCompleted) return completer.future;
          if (!launched) {
            _publishAndComplete(const BroadcastPurchaseResult(
              status: BroadcastPurchaseStatus.error,
              message: 'Purchase sheet could not be opened.',
            ));
          }
        }
      }
    } catch (error) {
      if (completer.isCompleted) return completer.future;
      if (error is TimeoutException && _checkoutAwaitingResult) {
        // StoreKit's native call remains open while the user decides in the
        // payment sheet. A UI deadline is not evidence of a failed checkout.
        _publishAndComplete(_pendingResult);
        return completer.future;
      }
      if (error is TimeoutException &&
          _verifier is CancellableBroadcastPurchaseVerifier) {
        (_verifier as CancellableBroadcastPurchaseVerifier).cancelPending();
      }
      _publishAndComplete(BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.error,
        message: 'Purchase could not be started: $error',
      ));
    }
    return _awaitActive(
      completer,
      onTimeout: _pendingResult,
    );
  }

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async {
    if (_disposed) return _disposedResult;
    if (!isPurchaseVerifierConfigured(_verifier)) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message: 'Purchase verification is not configured.',
      );
    }
    if (productId != expectedProductId) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message: 'Restore product does not match the configured entitlement.',
      );
    }
    if (_active != null) return _pendingResult;
    final completer = _begin();
    _restoring = true;
    try {
      final available = await _awaitStore(_store.isAvailable, catalogTimeout);
      if (completer.isCompleted) return completer.future;
      if (!available) {
        _publishAndComplete(const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.unavailable,
          message: 'Store is not available on this device.',
        ));
      } else {
        if (_store is InAppPurchaseOwnedQueryStore) {
          final ownedStore = _store as InAppPurchaseOwnedQueryStore;
          if (!ownedStore.ownedQueryIncludesPending) {
            // StoreKit's local history can be empty after reinstall/account
            // changes. Explicit restore must sync before declaring no right.
            await _awaitStore(_store.restorePurchases, timeout);
            if (completer.isCompleted) return completer.future;
          }
          await reconcilePurchases(force: true);
          if (completer.isCompleted) return completer.future;
          if (_pendingStoreApproval || _checkoutAwaitingResult) {
            _publishAndComplete(_pendingResult);
            return completer.future;
          }
          if (_lastQueryHadProduct == false) {
            _publishAndComplete(const BroadcastPurchaseResult(
              status: BroadcastPurchaseStatus.noPurchaseFound,
              message:
                  'No purchase for this product was found in the current store account.',
            ));
            return completer.future;
          }
          if (!ownedStore.ownedQueryIncludesPending) {
            return _awaitActive(completer, onTimeout: _pendingResult);
          }
        }
        await _awaitStore(_store.restorePurchases, timeout);
      }
    } catch (error) {
      if (completer.isCompleted) return completer.future;
      _publishAndComplete(BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.error,
        message: 'Purchases could not be restored: $error',
      ));
    }
    return _awaitActive(
      completer,
      onTimeout: const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message: 'No previous purchase was restored.',
      ),
    );
  }

  Completer<BroadcastPurchaseResult> _begin() {
    return _active = Completer<BroadcastPurchaseResult>();
  }

  Future<bool> _openCheckout(ProductDetails product) async {
    final generation = ++_checkoutGeneration;
    _nativeCheckoutGeneration = generation;
    _checkoutAwaitingResult = true;
    try {
      final launched = await _store.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
      if (!launched) _rejectCheckoutLaunch(generation);
      return launched;
    } catch (_) {
      _rejectCheckoutLaunch(generation);
      return false;
    } finally {
      if (_nativeCheckoutGeneration == generation) {
        _nativeCheckoutGeneration = null;
      }
    }
  }

  void _rejectCheckoutLaunch(int generation) {
    if (_disposed || generation != _checkoutGeneration) return;
    _finishCheckout();
    _publishAndComplete(const BroadcastPurchaseResult(
      status: BroadcastPurchaseStatus.error,
      message: 'Purchase sheet could not be opened.',
    ));
  }

  void _finishCheckout() {
    _checkoutGeneration++;
    _checkoutAwaitingResult = false;
  }

  // Native store calls may never finish when the owner leaves the room screen.
  // Complete their wrapper on disposal so catalog timers cannot keep running
  // and a late store response cannot open checkout after the screen is gone.
  Future<T> _awaitStore<T>(
    Future<T> Function() operation,
    Duration limit,
  ) {
    if (_disposed) {
      return Future.error(StateError('Purchase gateway is disposed.'));
    }
    return Future.any<T>([
      operation(),
      _closed.future.then<T>(
        (_) => throw StateError('Purchase gateway is disposed.'),
      ),
    ]).timeout(limit);
  }

  Future<BroadcastPurchaseResult> _awaitActive(
    Completer<BroadcastPurchaseResult> completer, {
    required BroadcastPurchaseResult onTimeout,
  }) =>
      completer.future.timeout(
        timeout,
        onTimeout: () {
          if (identical(_active, completer)) {
            _active = null;
            _restoring = false;
          }
          return onTimeout;
        },
      );

  void _enqueuePurchases(List<PurchaseDetails> purchases) {
    unawaited(
        _events.run(() => _handlePurchases(purchases)).catchError((_) {}));
  }

  void _enqueueStreamError(Object error) {
    unawaited(_events.run(() async {
      _publishAndComplete(BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.error,
        message: 'Purchase stream failed: $error',
      ));
    }).catchError((_) {}));
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    if (_disposed) return;
    for (final purchase in purchases) {
      if (purchase.productID != expectedProductId) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
          await _verifyAcknowledgeAndPublish(
            purchase,
            BroadcastPurchaseStatus.purchased,
          );
        case PurchaseStatus.restored:
          await _verifyAcknowledgeAndPublish(
            purchase,
            BroadcastPurchaseStatus.restored,
          );
        case PurchaseStatus.pending:
          _pendingStoreApproval = true;
          _publish(const BroadcastPurchaseResult(
            status: BroadcastPurchaseStatus.pending,
            message: 'Purchase is pending store approval.',
          ));
        case PurchaseStatus.canceled:
          _pendingStoreApproval = false;
          _finishCheckout();
          await _completeTerminalPurchase(purchase);
          _publishAndComplete(const BroadcastPurchaseResult(
            status: BroadcastPurchaseStatus.canceled,
            message: 'Purchase was canceled.',
          ));
        case PurchaseStatus.error:
          _pendingStoreApproval = false;
          _finishCheckout();
          await _completeTerminalPurchase(purchase);
          _publishAndComplete(BroadcastPurchaseResult(
            status: BroadcastPurchaseStatus.error,
            message: purchase.error?.message ?? 'Purchase failed.',
          ));
      }
    }
  }

  Future<void> _verifyAcknowledgeAndPublish(
    PurchaseDetails purchase,
    BroadcastPurchaseStatus status,
  ) async {
    final evidenceKey = purchaseEvidenceFingerprint(purchase);
    _pendingStoreApproval = false;
    _finishCheckout();
    final processed = _processedEvidence[evidenceKey];
    if (processed != null &&
        !_restoring &&
        status != BroadcastPurchaseStatus.restored) {
      _publishAndComplete(processed);
      return;
    }
    try {
      final verification = await _awaitStore(
        () => _verifier.verify(purchase, expectedProductId: expectedProductId),
        verificationTimeout,
      );
      final fingerprint = verification.fingerprint;
      final entitlementId = verification.entitlementId;
      if (!verification.verified ||
          verification.authority != trustedBackendVerificationAuthority ||
          fingerprint == null ||
          fingerprint.isEmpty ||
          entitlementId == null ||
          entitlementId.isEmpty) {
        final result = _verificationResult(verification, status);
        if (result.failureReason == BroadcastPurchaseFailureReason.revoked &&
            result.licenseToken != null &&
            _deliverPurchase != null) {
          await _awaitStore(() => _deliverPurchase!(result), completionTimeout);
        }
        _processedEvidence.remove(evidenceKey);
        _publishAndComplete(result);
        return;
      }
      final result = BroadcastPurchaseResult(
        status: status,
        verified: true,
        verificationSource: verification.source,
        verificationFingerprint: fingerprint,
        verificationAuthority: verification.authority,
        entitlementId: entitlementId,
        localizedPrice: _offers[purchase.productID]?.price,
        licenseToken: verification.licenseToken,
      );
      final deliver = _deliverPurchase;
      if (deliver == null) {
        throw StateError('No durable entitlement owner is attached.');
      }
      await _awaitStore(() => deliver(result), completionTimeout);
      // A crash or screen transition after this point cannot lose a paid
      // entitlement: delivery is durable before the store transaction finishes.
      if (purchase.pendingCompletePurchase) {
        try {
          await _awaitStore(
              () => _store.completePurchase(purchase), completionTimeout);
        } catch (_) {
          // The customer already owns the durably delivered entitlement. Do
          // not report a failed purchase or cache away the store's ack retry.
          _publishAndComplete(result);
          return;
        }
      }
      _processedEvidence[evidenceKey] = result;
      _publishAndComplete(result);
    } catch (error) {
      if (error is TimeoutException &&
          _verifier is CancellableBroadcastPurchaseVerifier) {
        (_verifier as CancellableBroadcastPurchaseVerifier).cancelPending();
      }
      _publishAndComplete(BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.verificationFailed,
        message: 'Purchase verification could not be completed: $error',
        failureReason: BroadcastPurchaseFailureReason.transient,
      ));
    }
  }

  Future<void> _completeTerminalPurchase(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _awaitStore(
          () => _store.completePurchase(purchase), completionTimeout);
    } catch (_) {
      // Keep cancellation/error observable; the store can redeliver an
      // unfinished terminal transaction for a later completion retry.
    }
  }

  BroadcastPurchaseResult _verificationResult(
    BroadcastPurchaseVerification verification,
    BroadcastPurchaseStatus status,
  ) =>
      BroadcastPurchaseResult(
        status: verification.verified
            ? status
            : BroadcastPurchaseStatus.verificationFailed,
        verified: verification.verified,
        message: verification.reason,
        verificationSource: verification.source,
        verificationAuthority: verification.authority,
        verificationFingerprint: verification.fingerprint,
        entitlementId: verification.entitlementId ?? '',
        licenseToken: verification.licenseToken,
        failureReason: verification.failureReason,
      );

  void _publish(BroadcastPurchaseResult result) {
    if (!_disposed && !_updates.isClosed) _updates.add(result);
  }

  void _publishAndComplete(BroadcastPurchaseResult result) {
    _publish(result);
    final completer = _active;
    _active = null;
    _restoring = false;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _closed.complete();
    final verifier = _verifier;
    if (verifier is CancellableBroadcastPurchaseVerifier) {
      (verifier as CancellableBroadcastPurchaseVerifier).cancelPending();
    }
    final active = _active;
    _active = null;
    if (active != null && !active.isCompleted) active.complete(_disposedResult);
    await _subscription?.cancel();
    _subscription = null;
    await _events.drain();
    await _updates.close();
  }

  static BroadcastProductOffer _toOffer(ProductDetails product) =>
      BroadcastProductOffer(
        productId: product.id,
        localizedPrice: product.price,
        rawPrice: product.rawPrice,
        currencyCode: product.currencyCode,
      );

  static const _pendingResult = BroadcastPurchaseResult(
    status: BroadcastPurchaseStatus.pending,
    message: 'A purchase is already in progress or awaiting store approval.',
  );
  static const _disposedResult = BroadcastPurchaseResult(
    status: BroadcastPurchaseStatus.error,
    message: 'Purchase gateway is disposed.',
  );
}
