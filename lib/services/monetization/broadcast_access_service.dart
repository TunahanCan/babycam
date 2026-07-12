import 'dart:async';
import 'dart:math';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/async/serialized_async_executor.dart';
import 'purchase_verification.dart';

export 'purchase_verification.dart';

class BroadcastAccessConfig {
  const BroadcastAccessConfig._();

  static const freeLimit = Duration(hours: 2);
  static const oneTimePriceLabel = '300 TL';
  static const productId = 'mimicam_lifetime_unlock_try_300';
  static const entitlementAuthority = 'room_server';
  static const checkpointInterval = Duration(seconds: 15);
}

class BroadcastProductOffer {
  const BroadcastProductOffer({
    required this.productId,
    required this.localizedPrice,
    required this.rawPrice,
    required this.currencyCode,
  });

  final String productId;
  final String localizedPrice;
  final double rawPrice;
  final String currencyCode;
}

class BroadcastAccessSnapshot {
  const BroadcastAccessSnapshot({
    required this.unlocked,
    required this.active,
    required this.freeLimitMs,
    required this.usedMs,
    required this.remainingMs,
    required this.priceLabel,
    required this.productId,
    this.entitlementAuthority = BroadcastAccessConfig.entitlementAuthority,
    this.entitlementId,
    this.purchaseVerifiedAtMs,
    this.purchaseVerificationSource,
    this.purchaseVerificationAuthority,
    this.purchaseVerificationFingerprint,
  });

  final bool unlocked;
  final bool active;
  final int freeLimitMs;
  final int usedMs;
  final int remainingMs;
  final String priceLabel;
  final String productId;
  final String entitlementAuthority;
  final String? entitlementId;
  final int? purchaseVerifiedAtMs;
  final String? purchaseVerificationSource;
  final String? purchaseVerificationAuthority;
  final String? purchaseVerificationFingerprint;

  factory BroadcastAccessSnapshot.fromJson(Map<Object?, Object?> json) {
    int intValue(String key, [int fallback = 0]) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    final freeLimitMs = max(
      1,
      intValue(
        'freeLimitMs',
        BroadcastAccessConfig.freeLimit.inMilliseconds,
      ),
    );
    final usedMs = intValue('usedMs').clamp(0, freeLimitMs).toInt();
    final remainingMs = intValue(
      'remainingMs',
      (freeLimitMs - usedMs).clamp(0, freeLimitMs),
    ).clamp(0, freeLimitMs).toInt();
    return BroadcastAccessSnapshot(
      unlocked: json['unlocked'] == true,
      active: json['active'] == true,
      freeLimitMs: freeLimitMs,
      usedMs: usedMs,
      remainingMs: remainingMs,
      priceLabel: json['priceLabel']?.toString().trim().isNotEmpty == true
          ? json['priceLabel'].toString().trim()
          : BroadcastAccessConfig.oneTimePriceLabel,
      productId: json['productId']?.toString().trim().isNotEmpty == true
          ? json['productId'].toString().trim()
          : BroadcastAccessConfig.productId,
      entitlementAuthority: json['entitlementAuthority']?.toString() ??
          BroadcastAccessConfig.entitlementAuthority,
      entitlementId: json['entitlementId']?.toString(),
      purchaseVerifiedAtMs: int.tryParse(
        json['purchaseVerifiedAtMs']?.toString() ?? '',
      ),
      purchaseVerificationSource:
          json['purchaseVerificationSource']?.toString(),
      purchaseVerificationAuthority:
          json['purchaseVerificationAuthority']?.toString(),
      purchaseVerificationFingerprint:
          json['purchaseVerificationFingerprint']?.toString(),
    );
  }

  bool get isLocked => !unlocked && remainingMs <= 0;

  double get usedRatio {
    if (freeLimitMs <= 0) return 1;
    return (usedMs / freeLimitMs).clamp(0, 1).toDouble();
  }

  Duration get remaining => Duration(milliseconds: remainingMs);

  BroadcastAccessSnapshot copyWith({
    bool? unlocked,
    bool? active,
    int? usedMs,
    int? remainingMs,
    String? priceLabel,
  }) =>
      BroadcastAccessSnapshot(
        unlocked: unlocked ?? this.unlocked,
        active: active ?? this.active,
        freeLimitMs: freeLimitMs,
        usedMs: usedMs ?? this.usedMs,
        remainingMs: remainingMs ?? this.remainingMs,
        priceLabel: priceLabel ?? this.priceLabel,
        productId: productId,
        entitlementAuthority: entitlementAuthority,
        entitlementId: entitlementId,
        purchaseVerifiedAtMs: purchaseVerifiedAtMs,
        purchaseVerificationSource: purchaseVerificationSource,
        purchaseVerificationAuthority: purchaseVerificationAuthority,
        purchaseVerificationFingerprint: purchaseVerificationFingerprint,
      );

  Map<String, Object?> toJson() => {
        'unlocked': unlocked,
        'active': active,
        'freeLimitMs': freeLimitMs,
        'usedMs': usedMs,
        'remainingMs': remainingMs,
        'priceLabel': priceLabel,
        'productId': productId,
        'locked': isLocked,
        'entitlementAuthority': entitlementAuthority,
        'entitlementId': entitlementId,
        'purchaseVerifiedAtMs': purchaseVerifiedAtMs,
        'purchaseVerificationSource': purchaseVerificationSource,
        'purchaseVerificationAuthority': purchaseVerificationAuthority,
        'purchaseVerificationFingerprint': purchaseVerificationFingerprint,
      };
}

class BroadcastAccessLockedException implements Exception {
  const BroadcastAccessLockedException(this.snapshot);

  final BroadcastAccessSnapshot snapshot;

  @override
  String toString() =>
      'BROADCAST_ACCESS_LOCKED: ${snapshot.priceLabel} one-time unlock required.';
}

class BroadcastPurchaseException implements Exception {
  const BroadcastPurchaseException(this.result);

  final BroadcastPurchaseResult result;

  @override
  String toString() =>
      'BROADCAST_PURCHASE_FAILED: ${result.message ?? result.status.name}';
}

enum BroadcastPurchaseStatus {
  purchased,
  restored,
  pending,
  canceled,
  unavailable,
  verificationFailed,
  error,
}

class BroadcastPurchaseResult {
  const BroadcastPurchaseResult({
    required this.status,
    this.message,
    this.verified = false,
    this.verificationSource,
    this.verificationFingerprint,
    this.verificationAuthority = trustedBackendVerificationAuthority,
    this.entitlementId = BroadcastAccessConfig.entitlementAuthority,
    this.localizedPrice,
  });

  final BroadcastPurchaseStatus status;
  final String? message;
  final bool verified;
  final String? verificationSource;
  final String? verificationFingerprint;
  final String verificationAuthority;
  final String entitlementId;
  final String? localizedPrice;

  bool get unlocksAccess =>
      verified &&
      verificationAuthority == trustedBackendVerificationAuthority &&
      entitlementId.trim().isNotEmpty &&
      (status == BroadcastPurchaseStatus.purchased ||
          status == BroadcastPurchaseStatus.restored);
}

abstract class BroadcastPurchaseGateway {
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  });

  Future<BroadcastPurchaseResult> restore({required String productId});

  Future<void> dispose() async {}
}

abstract interface class BroadcastPurchaseUpdateSource {
  Stream<BroadcastPurchaseResult> get updates;
}

abstract interface class BroadcastProductOfferGateway {
  BroadcastProductOffer? get cachedOffer;

  Future<BroadcastProductOffer?> loadOffer({required String productId});
}

abstract interface class InAppPurchaseStore {
  Stream<List<PurchaseDetails>> get purchaseStream;

  Future<bool> isAvailable();

  Future<ProductDetailsResponse> queryProductDetails(Set<String> productIds);

  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam});

  Future<void> restorePurchases();

  Future<void> completePurchase(PurchaseDetails purchase);
}

class FlutterInAppPurchaseStore implements InAppPurchaseStore {
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
  Future<void> restorePurchases() => _iap.restorePurchases();

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);
}

/// Owns the store stream for its whole lifetime, independently of any active
/// purchase sheet. Late and restored transactions therefore still reach the
/// authoritative [BroadcastAccessService].
class InAppBroadcastPurchaseGateway
    implements
        BroadcastPurchaseGateway,
        BroadcastPurchaseUpdateSource,
        BroadcastProductOfferGateway {
  InAppBroadcastPurchaseGateway({
    InAppPurchase? inAppPurchase,
    InAppPurchaseStore? store,
    BroadcastPurchaseVerifier? verifier,
    this.expectedProductId = BroadcastAccessConfig.productId,
    this.timeout = const Duration(minutes: 2),
    this.catalogTimeout = const Duration(seconds: 10),
  })  : _store = store ?? FlutterInAppPurchaseStore(inAppPurchase),
        _verifier = verifier ?? defaultBroadcastPurchaseVerifier() {
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
  final _updates = StreamController<BroadcastPurchaseResult>.broadcast();
  final _processedEvidence = <String, BroadcastPurchaseResult>{};
  final _offers = <String, ProductDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Completer<BroadcastPurchaseResult>? _active;
  final _events = SerializedAsyncExecutor();
  Future<BroadcastProductOffer?>? _offerLoad;
  bool _disposed = false;

  @override
  Stream<BroadcastPurchaseResult> get updates => _updates.stream;

  @override
  BroadcastProductOffer? get cachedOffer {
    if (_offers.isEmpty) return null;
    return _toOffer(_offers.values.first);
  }

  @override
  Future<BroadcastProductOffer?> loadOffer({required String productId}) {
    final cached = _offers[productId];
    if (cached != null) return Future.value(_toOffer(cached));
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
    if (_disposed || !await _store.isAvailable().timeout(catalogTimeout)) {
      return null;
    }
    final response =
        await _store.queryProductDetails({productId}).timeout(catalogTimeout);
    for (final product in response.productDetails) {
      _offers[product.id] = product;
    }
    final product = _offers[productId];
    return product == null ? null : _toOffer(product);
  }

  @override
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  }) async {
    if (_disposed) return _disposedResult;
    if (productId != expectedProductId) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message: 'Purchase product does not match the configured entitlement.',
      );
    }
    if (_active != null) return _pendingResult;
    final completer = _begin();
    try {
      final available = await _store.isAvailable().timeout(catalogTimeout);
      if (!available) {
        _publishAndComplete(const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.unavailable,
          message: 'Store is not available on this device.',
        ));
      } else {
        final offer = await loadOffer(productId: productId);
        final product = _offers[productId];
        if (offer == null || product == null) {
          _publishAndComplete(const BroadcastPurchaseResult(
            status: BroadcastPurchaseStatus.unavailable,
            message: 'Purchase product is not configured.',
          ));
        } else {
          final launched = await _store
              .buyNonConsumable(
                purchaseParam: PurchaseParam(productDetails: product),
              )
              .timeout(timeout);
          if (!launched) {
            _publishAndComplete(const BroadcastPurchaseResult(
              status: BroadcastPurchaseStatus.error,
              message: 'Purchase sheet could not be opened.',
            ));
          }
        }
      }
    } catch (error) {
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
    if (productId != expectedProductId) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message: 'Restore product does not match the configured entitlement.',
      );
    }
    if (_active != null) return _pendingResult;
    final completer = _begin();
    try {
      if (!await _store.isAvailable().timeout(catalogTimeout)) {
        _publishAndComplete(const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.unavailable,
          message: 'Store is not available on this device.',
        ));
      } else {
        await _store.restorePurchases().timeout(timeout);
      }
    } catch (error) {
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

  Future<BroadcastPurchaseResult> _awaitActive(
    Completer<BroadcastPurchaseResult> completer, {
    required BroadcastPurchaseResult onTimeout,
  }) =>
      completer.future.timeout(
        timeout,
        onTimeout: () {
          if (identical(_active, completer)) {
            _active = null;
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
          _publish(const BroadcastPurchaseResult(
            status: BroadcastPurchaseStatus.pending,
            message: 'Purchase is pending store approval.',
          ));
        case PurchaseStatus.canceled:
          _publishAndComplete(const BroadcastPurchaseResult(
            status: BroadcastPurchaseStatus.canceled,
            message: 'Purchase was canceled.',
          ));
        case PurchaseStatus.error:
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
    final processed = _processedEvidence[evidenceKey];
    if (processed != null) {
      _publishAndComplete(processed);
      return;
    }
    try {
      final verification = await _verifier.verify(
        purchase,
        expectedProductId: expectedProductId,
      );
      final fingerprint = verification.fingerprint;
      final entitlementId = verification.entitlementId;
      if (!verification.verified ||
          verification.authority != trustedBackendVerificationAuthority ||
          fingerprint == null ||
          fingerprint.isEmpty ||
          entitlementId == null ||
          entitlementId.isEmpty) {
        _publishAndComplete(BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.verificationFailed,
          message: verification.reason ?? 'Purchase verification failed.',
          verificationSource: verification.source,
          verificationAuthority: verification.authority,
        ));
        return;
      }
      // A transaction is acknowledged only after the trusted verifier accepts
      // it. If acknowledgement fails, no entitlement result is published and a
      // later store redelivery can retry the operation.
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
      final result = BroadcastPurchaseResult(
        status: status,
        verified: true,
        verificationSource: verification.source,
        verificationFingerprint: fingerprint,
        verificationAuthority: verification.authority,
        entitlementId: entitlementId,
        localizedPrice: _offers[purchase.productID]?.price,
      );
      _processedEvidence[evidenceKey] = result;
      _publishAndComplete(result);
    } catch (error) {
      _publishAndComplete(BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.verificationFailed,
        message: 'Purchase verification could not be completed: $error',
      ));
    }
  }

  void _publish(BroadcastPurchaseResult result) {
    if (!_disposed && !_updates.isClosed) _updates.add(result);
  }

  void _publishAndComplete(BroadcastPurchaseResult result) {
    _publish(result);
    final completer = _active;
    _active = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
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

/// Authoritative room-device entitlement and crash-resilient trial ledger.
///
/// The paired client must treat the room/server response as the single access
/// authority instead of maintaining a second independent local trial.
class BroadcastAccessService {
  BroadcastAccessService(
    this._preferences, {
    BroadcastPurchaseGateway? purchaseGateway,
    DateTime Function()? now,
    int Function()? monotonicNowMs,
    Duration freeLimit = BroadcastAccessConfig.freeLimit,
    Duration checkpointInterval = BroadcastAccessConfig.checkpointInterval,
    String priceLabel = BroadcastAccessConfig.oneTimePriceLabel,
    String productId = BroadcastAccessConfig.productId,
  })  : assert(checkpointInterval > Duration.zero),
        _purchaseGateway = purchaseGateway ??
            InAppBroadcastPurchaseGateway(expectedProductId: productId),
        _now = now ?? DateTime.now,
        _monotonicNowOverride = monotonicNowMs,
        _freeLimit = freeLimit,
        _checkpointInterval = checkpointInterval,
        _fallbackPriceLabel = priceLabel,
        _productId = productId,
        _stopwatch = Stopwatch()..start() {
    _initialization = _initializeTrialLedger();
    final updateSource = _purchaseGateway is BroadcastPurchaseUpdateSource
        ? _purchaseGateway as BroadcastPurchaseUpdateSource
        : null;
    _purchaseUpdates =
        (updateSource?.updates ?? const Stream<BroadcastPurchaseResult>.empty())
            .listen(
      _handlePurchaseUpdate,
      onError: (Object _, StackTrace __) {},
    );
    _offerLoad = _loadOfferBestEffort();
  }

  static const _prefix = 'broadcast_access.';
  static const _unlockedKey = '${_prefix}unlocked';
  static const _usedMsKey = '${_prefix}used_ms';
  static const _verifiedAtMsKey = '${_prefix}verified_at_ms';
  static const _verificationSourceKey = '${_prefix}verification_source';
  static const _verificationFingerprintKey =
      '${_prefix}verification_fingerprint';
  static const _verificationAuthorityKey = '${_prefix}verification_authority';
  static const _entitlementIdKey = '${_prefix}entitlement_id';
  static const _activeMarkerKey = '${_prefix}active_marker';
  static const _activeCheckpointWallMsKey =
      '${_prefix}active_checkpoint_wall_ms';
  static const _lastObservedWallMsKey = '${_prefix}last_observed_wall_ms';

  final SharedPreferences _preferences;
  final BroadcastPurchaseGateway _purchaseGateway;
  final DateTime Function() _now;
  final int Function()? _monotonicNowOverride;
  final Duration _freeLimit;
  final Duration _checkpointInterval;
  final String _fallbackPriceLabel;
  final String _productId;
  final Stopwatch _stopwatch;
  final _activeSessions = <String, int>{};
  final _changes = StreamController<BroadcastAccessSnapshot>.broadcast();
  late final Future<void> _initialization;
  late final StreamSubscription<BroadcastPurchaseResult> _purchaseUpdates;
  late final Future<void> _offerLoad;
  final _mutations = SerializedAsyncExecutor();
  Timer? _checkpointTimer;
  int? _activeStartedAtMonoMs;
  String? _localizedPriceLabel;
  BroadcastPurchaseResult? _lastPurchaseResult;
  bool _disposed = false;

  Stream<BroadcastAccessSnapshot> get changes => _changes.stream;
  BroadcastPurchaseResult? get lastPurchaseResult => _lastPurchaseResult;

  Future<BroadcastAccessSnapshot> snapshot() async {
    await _initialization;
    await _offerLoad;
    await _mutations.drain();
    return _snapshot();
  }

  Future<BroadcastAccessSnapshot> beginSession(String sessionId) async {
    await _initialization;
    return _serialize(() async {
      final before = _snapshot();
      if (before.isLocked) throw BroadcastAccessLockedException(before);
      final normalized = _normalizeSessionId(sessionId);
      if (_activeSessions.containsKey(normalized)) return before;
      final monoNow = _monoNowMs();
      if (_activeSessions.isEmpty) {
        _activeStartedAtMonoMs = monoNow;
        await _writeActiveMarker(active: true);
        _startCheckpointTimer();
      }
      _activeSessions[normalized] = monoNow;
      return _snapshot();
    });
  }

  Future<BroadcastAccessSnapshot> endSession(String sessionId) async {
    await _initialization;
    return _serialize(() async {
      final removed = _activeSessions.remove(_normalizeSessionId(sessionId));
      if (removed == null) return _snapshot();
      if (_activeSessions.isEmpty) {
        _checkpointTimer?.cancel();
        _checkpointTimer = null;
        await _checkpointActiveElapsed(keepActive: false);
      }
      return _snapshot();
    });
  }

  Future<BroadcastAccessSnapshot> endAllSessions() async {
    await _initialization;
    return _serialize(() async {
      _activeSessions.clear();
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      await _checkpointActiveElapsed(keepActive: false);
      return _snapshot();
    });
  }

  Future<BroadcastAccessSnapshot> unlockWithOneTimePurchase() async {
    await _initialization;
    final result = await _purchaseGateway.purchase(
      productId: _productId,
      priceLabel: _localizedPriceLabel ?? _fallbackPriceLabel,
    );
    _lastPurchaseResult = result;
    if (!result.unlocksAccess) throw BroadcastPurchaseException(result);
    return _serialize(() => _persistVerifiedUnlock(result));
  }

  Future<BroadcastAccessSnapshot> restorePurchase() async {
    await _initialization;
    final result = await _purchaseGateway.restore(productId: _productId);
    _lastPurchaseResult = result;
    if (!result.unlocksAccess) throw BroadcastPurchaseException(result);
    return _serialize(() => _persistVerifiedUnlock(result));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await _initialization;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    await endAllSessions();
    _disposed = true;
    await _purchaseUpdates.cancel();
    await _purchaseGateway.dispose();
    await _changes.close();
  }

  Future<void> _initializeTrialLedger() async {
    final nowWallMs = _nowMs();
    final lastObservedWallMs =
        _preferences.getInt(_lastObservedWallMsKey) ?? nowWallMs;
    if (_preferences.getBool(_activeMarkerKey) == true) {
      final checkpointWallMs =
          _preferences.getInt(_activeCheckpointWallMsKey) ?? lastObservedWallMs;
      final wallDelta = nowWallMs - checkpointWallMs;
      // Charge at most one checkpoint interval after an unclean shutdown. This
      // bounds lost trial time without charging arbitrary offline time. A wall
      // clock rollback is treated as an unclean full interval.
      final recoveredMs = wallDelta < 0
          ? _checkpointInterval.inMilliseconds
          : min(wallDelta, _checkpointInterval.inMilliseconds);
      final stored = _preferences.getInt(_usedMsKey) ?? 0;
      await _preferences.setInt(
        _usedMsKey,
        (stored + recoveredMs).clamp(0, _freeLimit.inMilliseconds),
      );
    }
    await _preferences.setBool(_activeMarkerKey, false);
    await _preferences.remove(_activeCheckpointWallMsKey);
    await _preferences.setInt(
      _lastObservedWallMsKey,
      max(lastObservedWallMs, nowWallMs),
    );
  }

  Future<void> _loadOfferBestEffort() async {
    try {
      final gateway = _purchaseGateway;
      final offerGateway = gateway is BroadcastProductOfferGateway
          ? gateway as BroadcastProductOfferGateway
          : null;
      if (offerGateway == null) return;
      final offer = await offerGateway.loadOffer(productId: _productId);
      final price = offer?.localizedPrice.trim();
      if (price != null && price.isNotEmpty) _localizedPriceLabel = price;
    } catch (_) {
      // Store catalog availability is reflected by the purchase operation. A
      // cached/fallback label keeps diagnostics usable while the store is down.
    }
  }

  void _handlePurchaseUpdate(BroadcastPurchaseResult result) {
    _lastPurchaseResult = result;
    final price = result.localizedPrice?.trim();
    if (price != null && price.isNotEmpty) _localizedPriceLabel = price;
    if (!result.unlocksAccess || _disposed) return;
    unawaited(_initialization
        .then((_) => _serialize(() async {
              final snapshot = await _persistVerifiedUnlock(result);
              if (!_changes.isClosed) _changes.add(snapshot);
              return snapshot;
            }))
        .then<void>((_) {}, onError: (_) {}));
  }

  Future<BroadcastAccessSnapshot> _persistVerifiedUnlock(
    BroadcastPurchaseResult result,
  ) async {
    final source = result.verificationSource?.trim();
    final fingerprint = result.verificationFingerprint?.trim();
    final entitlementId = result.entitlementId.trim();
    if (!result.unlocksAccess ||
        source == null ||
        source.isEmpty ||
        fingerprint == null ||
        fingerprint.isEmpty ||
        entitlementId.isEmpty) {
      throw const BroadcastPurchaseException(BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.verificationFailed,
        message: 'Trusted purchase evidence is missing.',
      ));
    }
    if (_preferences.getString(_verificationFingerprintKey) == fingerprint &&
        _hasValidPersistedEntitlement()) {
      return _snapshot();
    }
    await _preferences.setString(_verificationSourceKey, source);
    await _preferences.setString(_verificationFingerprintKey, fingerprint);
    await _preferences.setString(
      _verificationAuthorityKey,
      result.verificationAuthority,
    );
    await _preferences.setString(_entitlementIdKey, entitlementId);
    await _preferences.setInt(_verifiedAtMsKey, _nowMs());
    // Write the grant last, after every piece of trusted evidence is durable.
    await _preferences.setBool(_unlockedKey, true);
    return _snapshot();
  }

  BroadcastAccessSnapshot _snapshot() {
    final unlocked = _hasValidPersistedEntitlement();
    final usedMs = _effectiveUsedMs();
    final freeLimitMs = _freeLimit.inMilliseconds;
    final remainingMs =
        unlocked ? freeLimitMs : (freeLimitMs - usedMs).clamp(0, freeLimitMs);
    return BroadcastAccessSnapshot(
      unlocked: unlocked,
      active: _activeSessions.isNotEmpty,
      freeLimitMs: freeLimitMs,
      usedMs: usedMs.clamp(0, freeLimitMs),
      remainingMs: remainingMs,
      priceLabel: _localizedPriceLabel ?? _fallbackPriceLabel,
      productId: _productId,
      entitlementId: _preferences.getString(_entitlementIdKey),
      purchaseVerifiedAtMs: _preferences.getInt(_verifiedAtMsKey),
      purchaseVerificationSource:
          _preferences.getString(_verificationSourceKey),
      purchaseVerificationAuthority:
          _preferences.getString(_verificationAuthorityKey),
      purchaseVerificationFingerprint:
          _preferences.getString(_verificationFingerprintKey),
    );
  }

  bool _hasValidPersistedEntitlement() =>
      (_preferences.getBool(_unlockedKey) ?? false) &&
      _preferences.getString(_verificationAuthorityKey) ==
          trustedBackendVerificationAuthority &&
      (_preferences.getString(_verificationSourceKey)?.isNotEmpty ?? false) &&
      (_preferences.getString(_verificationFingerprintKey)?.isNotEmpty ??
          false) &&
      (_preferences.getString(_entitlementIdKey)?.isNotEmpty ?? false) &&
      (_preferences.getInt(_verifiedAtMsKey) ?? 0) > 0;

  int _effectiveUsedMs() {
    final stored = _preferences.getInt(_usedMsKey) ?? 0;
    final startedAt = _activeStartedAtMonoMs;
    if (_activeSessions.isEmpty || startedAt == null) return stored;
    final elapsed = (_monoNowMs() - startedAt).clamp(
      0,
      _freeLimit.inMilliseconds,
    );
    return (stored + elapsed).clamp(0, _freeLimit.inMilliseconds);
  }

  Future<void> _checkpointActiveElapsed({required bool keepActive}) async {
    final startedAt = _activeStartedAtMonoMs;
    if (startedAt != null) {
      final monoNow = _monoNowMs();
      final elapsed = (monoNow - startedAt).clamp(
        0,
        _freeLimit.inMilliseconds,
      );
      final stored = _preferences.getInt(_usedMsKey) ?? 0;
      await _preferences.setInt(
        _usedMsKey,
        (stored + elapsed).clamp(0, _freeLimit.inMilliseconds),
      );
      _activeStartedAtMonoMs = keepActive ? monoNow : null;
    }
    await _writeActiveMarker(active: keepActive);
  }

  Future<void> _writeActiveMarker({required bool active}) async {
    final nowWallMs = _nowMs();
    final previousWallMs =
        _preferences.getInt(_lastObservedWallMsKey) ?? nowWallMs;
    final safeWallMs = max(previousWallMs, nowWallMs);
    await _preferences.setInt(_lastObservedWallMsKey, safeWallMs);
    await _preferences.setBool(_activeMarkerKey, active);
    if (active) {
      await _preferences.setInt(_activeCheckpointWallMsKey, safeWallMs);
    } else {
      await _preferences.remove(_activeCheckpointWallMsKey);
    }
  }

  void _startCheckpointTimer() {
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer.periodic(_checkpointInterval, (_) {
      if (_disposed || _activeSessions.isEmpty) return;
      unawaited(_serialize(() async {
        if (_activeSessions.isNotEmpty) {
          await _checkpointActiveElapsed(keepActive: true);
        }
      }).catchError((_) {}));
    });
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    return _mutations.run(operation);
  }

  int _nowMs() => _now().millisecondsSinceEpoch;
  int _monoNowMs() =>
      _monotonicNowOverride?.call() ?? _stopwatch.elapsedMilliseconds;

  String _normalizeSessionId(String sessionId) {
    final trimmed = sessionId.trim();
    return trimmed.isEmpty ? 'broadcast' : trimmed;
  }
}
