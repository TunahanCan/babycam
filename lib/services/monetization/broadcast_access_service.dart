import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BroadcastAccessConfig {
  const BroadcastAccessConfig._();

  static const freeLimit = Duration(hours: 2);
  static const oneTimePriceLabel = '300 TL';
  static const productId = 'mimicam_lifetime_unlock_try_300';
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
    this.purchaseVerifiedAtMs,
    this.purchaseVerificationSource,
  });

  final bool unlocked;
  final bool active;
  final int freeLimitMs;
  final int usedMs;
  final int remainingMs;
  final String priceLabel;
  final String productId;
  final int? purchaseVerifiedAtMs;
  final String? purchaseVerificationSource;

  bool get isLocked => !unlocked && remainingMs <= 0;
  double get usedRatio {
    if (freeLimitMs <= 0) return 1;
    return (usedMs / freeLimitMs).clamp(0, 1).toDouble();
  }

  Duration get remaining => Duration(milliseconds: remainingMs);

  Map<String, Object?> toJson() => {
        'unlocked': unlocked,
        'active': active,
        'freeLimitMs': freeLimitMs,
        'usedMs': usedMs,
        'remainingMs': remainingMs,
        'priceLabel': priceLabel,
        'productId': productId,
        'locked': isLocked,
        'purchaseVerifiedAtMs': purchaseVerifiedAtMs,
        'purchaseVerificationSource': purchaseVerificationSource,
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
  });

  final BroadcastPurchaseStatus status;
  final String? message;
  final bool verified;
  final String? verificationSource;
  final String? verificationFingerprint;

  bool get unlocksAccess =>
      verified &&
      (status == BroadcastPurchaseStatus.purchased ||
          status == BroadcastPurchaseStatus.restored);
}

class BroadcastPurchaseVerification {
  const BroadcastPurchaseVerification._({
    required this.verified,
    required this.source,
    this.fingerprint,
    this.reason,
  });

  const BroadcastPurchaseVerification.verified({
    required String source,
    required String fingerprint,
  }) : this._(
          verified: true,
          source: source,
          fingerprint: fingerprint,
        );

  const BroadcastPurchaseVerification.rejected({
    required String source,
    required String reason,
  }) : this._(
          verified: false,
          source: source,
          reason: reason,
        );

  final bool verified;
  final String source;
  final String? fingerprint;
  final String? reason;
}

abstract class BroadcastPurchaseVerifier {
  Future<BroadcastPurchaseVerification> verify(
    PurchaseDetails purchase, {
    required String expectedProductId,
  });
}

/// Validates the store-originated verification envelope before an entitlement
/// is granted. The raw receipt/purchase token is deliberately never persisted.
/// A remote verifier can replace this strategy without changing purchase flow.
class StorePayloadPurchaseVerifier implements BroadcastPurchaseVerifier {
  const StorePayloadPurchaseVerifier();

  static const _supportedSources = {'app_store', 'google_play'};

  @override
  Future<BroadcastPurchaseVerification> verify(
    PurchaseDetails purchase, {
    required String expectedProductId,
  }) async {
    final source = purchase.verificationData.source.trim();
    if (purchase.productID != expectedProductId) {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'The store transaction belongs to a different product.',
      );
    }
    if (!_supportedSources.contains(source)) {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'Unknown purchase verification source.',
      );
    }
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'The transaction is not in a deliverable state.',
      );
    }
    final serverData = purchase.verificationData.serverVerificationData.trim();
    final localData = purchase.verificationData.localVerificationData.trim();
    if (serverData.isEmpty || localData.isEmpty) {
      return BroadcastPurchaseVerification.rejected(
        source: source,
        reason: 'The store did not provide verification evidence.',
      );
    }

    final fingerprint = sha256
        .convert(
            utf8.encode('$source\u0000${purchase.productID}\u0000$serverData'))
        .toString();
    return BroadcastPurchaseVerification.verified(
      source: source,
      fingerprint: fingerprint,
    );
  }
}

abstract class BroadcastPurchaseGateway {
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  });

  Future<BroadcastPurchaseResult> restore({required String productId});

  Future<void> dispose() async {}
}

class InAppBroadcastPurchaseGateway implements BroadcastPurchaseGateway {
  InAppBroadcastPurchaseGateway({
    InAppPurchase? inAppPurchase,
    BroadcastPurchaseVerifier? verifier,
    this.timeout = const Duration(minutes: 2),
  })  : _iap = inAppPurchase ?? InAppPurchase.instance,
        _verifier = verifier ?? const StorePayloadPurchaseVerifier();

  final InAppPurchase _iap;
  final BroadcastPurchaseVerifier _verifier;
  final Duration timeout;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Completer<BroadcastPurchaseResult>? _active;
  String? _activeProductId;

  @override
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  }) async {
    if (_active != null) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.pending,
        message: 'A purchase is already in progress.',
      );
    }
    final available = await _iap.isAvailable();
    if (!available) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message: 'Store is not available on this device.',
      );
    }
    final products = await _iap.queryProductDetails({productId});
    if (products.productDetails.isEmpty) {
      final error = products.error?.message;
      return BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message: error ?? 'Purchase product is not configured.',
      );
    }

    final completer = _begin(productId);
    final product = products.productDetails.first;
    final launched = await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!launched) {
      _complete(
        const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.error,
          message: 'Purchase sheet could not be opened.',
        ),
      );
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _active = null;
        _activeProductId = null;
        return const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.pending,
          message: 'Purchase is still pending.',
        );
      },
    );
  }

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async {
    if (_active != null) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.pending,
        message: 'A purchase is already in progress.',
      );
    }
    final available = await _iap.isAvailable();
    if (!available) {
      return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable,
        message: 'Store is not available on this device.',
      );
    }
    final completer = _begin(productId);
    await _iap.restorePurchases();
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _active = null;
        _activeProductId = null;
        return const BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.unavailable,
          message: 'No previous purchase was restored.',
        );
      },
    );
  }

  Completer<BroadcastPurchaseResult> _begin(String productId) {
    _activeProductId = productId;
    _active = Completer<BroadcastPurchaseResult>();
    _subscription ??= _iap.purchaseStream.listen(_handlePurchases);
    return _active!;
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    final productId = _activeProductId;
    if (productId == null || _active == null) return;
    for (final purchase in purchases) {
      if (purchase.productID != productId) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
          await _completeVerifiedPurchase(
            purchase,
            BroadcastPurchaseStatus.purchased,
          );
        case PurchaseStatus.restored:
          await _completeVerifiedPurchase(
            purchase,
            BroadcastPurchaseStatus.restored,
          );
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.canceled:
          _complete(const BroadcastPurchaseResult(
            status: BroadcastPurchaseStatus.canceled,
            message: 'Purchase was canceled.',
          ));
        case PurchaseStatus.error:
          _complete(BroadcastPurchaseResult(
            status: BroadcastPurchaseStatus.error,
            message: purchase.error?.message ?? 'Purchase failed.',
          ));
      }
    }
  }

  Future<void> _completeVerifiedPurchase(
    PurchaseDetails purchase,
    BroadcastPurchaseStatus status,
  ) async {
    final productId = _activeProductId;
    if (productId == null) return;
    try {
      final verification = await _verifier.verify(
        purchase,
        expectedProductId: productId,
      );
      if (!verification.verified || verification.fingerprint == null) {
        _complete(BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.verificationFailed,
          message: verification.reason ?? 'Purchase verification failed.',
          verificationSource: verification.source,
        ));
        return;
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      _complete(BroadcastPurchaseResult(
        status: status,
        verified: true,
        verificationSource: verification.source,
        verificationFingerprint: verification.fingerprint,
      ));
    } catch (error) {
      _complete(BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.verificationFailed,
        message: 'Purchase verification could not be completed: $error',
      ));
    }
  }

  void _complete(BroadcastPurchaseResult result) {
    final completer = _active;
    _active = null;
    _activeProductId = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

class BroadcastAccessService {
  BroadcastAccessService(
    this._preferences, {
    BroadcastPurchaseGateway? purchaseGateway,
    DateTime Function()? now,
    Duration freeLimit = BroadcastAccessConfig.freeLimit,
    String priceLabel = BroadcastAccessConfig.oneTimePriceLabel,
    String productId = BroadcastAccessConfig.productId,
  })  : _purchaseGateway = purchaseGateway,
        _now = now ?? DateTime.now,
        _freeLimit = freeLimit,
        _priceLabel = priceLabel,
        _productId = productId;

  static const _prefix = 'broadcast_access.';
  static const _unlockedKey = '${_prefix}unlocked';
  static const _usedMsKey = '${_prefix}used_ms';
  static const _verifiedAtMsKey = '${_prefix}verified_at_ms';
  static const _verificationSourceKey = '${_prefix}verification_source';
  static const _verificationFingerprintKey =
      '${_prefix}verification_fingerprint';

  final SharedPreferences _preferences;
  BroadcastPurchaseGateway? _purchaseGateway;
  final DateTime Function() _now;
  final Duration _freeLimit;
  final String _priceLabel;
  final String _productId;
  final _activeSessions = <String, int>{};
  int? _activeStartedAtMs;

  Future<BroadcastAccessSnapshot> snapshot() async => _snapshot();

  Future<BroadcastAccessSnapshot> beginSession(String sessionId) async {
    final before = _snapshot();
    if (before.isLocked) throw BroadcastAccessLockedException(before);
    final normalized = _normalizeSessionId(sessionId);
    if (_activeSessions.containsKey(normalized)) return before;
    final nowMs = _nowMs();
    if (_activeSessions.isEmpty) _activeStartedAtMs = nowMs;
    _activeSessions[normalized] = nowMs;
    return _snapshot();
  }

  Future<BroadcastAccessSnapshot> endSession(String sessionId) async {
    final normalized = _normalizeSessionId(sessionId);
    final removed = _activeSessions.remove(normalized);
    if (removed == null) return _snapshot();
    if (_activeSessions.isEmpty) {
      await _commitActiveElapsed();
    }
    return _snapshot();
  }

  Future<BroadcastAccessSnapshot> endAllSessions() async {
    if (_activeSessions.isNotEmpty) {
      _activeSessions.clear();
      await _commitActiveElapsed();
    }
    return _snapshot();
  }

  Future<BroadcastAccessSnapshot> unlockWithOneTimePurchase() async {
    final result = await _gateway.purchase(
      productId: _productId,
      priceLabel: _priceLabel,
    );
    if (!result.unlocksAccess) throw BroadcastPurchaseException(result);
    await _persistVerifiedUnlock(result);
    return _snapshot();
  }

  Future<BroadcastAccessSnapshot> restorePurchase() async {
    final result = await _gateway.restore(productId: _productId);
    if (!result.unlocksAccess) throw BroadcastPurchaseException(result);
    await _persistVerifiedUnlock(result);
    return _snapshot();
  }

  Future<void> dispose() async {
    await _purchaseGateway?.dispose();
  }

  BroadcastPurchaseGateway get _gateway =>
      _purchaseGateway ??= InAppBroadcastPurchaseGateway();

  BroadcastAccessSnapshot _snapshot() {
    final unlocked = _preferences.getBool(_unlockedKey) ?? false;
    final usedMs = _effectiveUsedMs();
    final freeLimitMs = _freeLimit.inMilliseconds;
    final remainingMs = unlocked
        ? freeLimitMs
        : (freeLimitMs - usedMs).clamp(0, freeLimitMs).toInt();
    return BroadcastAccessSnapshot(
      unlocked: unlocked,
      active: _activeSessions.isNotEmpty,
      freeLimitMs: freeLimitMs,
      usedMs: usedMs.clamp(0, freeLimitMs).toInt(),
      remainingMs: remainingMs,
      priceLabel: _priceLabel,
      productId: _productId,
      purchaseVerifiedAtMs: _preferences.getInt(_verifiedAtMsKey),
      purchaseVerificationSource:
          _preferences.getString(_verificationSourceKey),
    );
  }

  Future<void> _persistVerifiedUnlock(BroadcastPurchaseResult result) async {
    final source = result.verificationSource;
    final fingerprint = result.verificationFingerprint;
    if (!result.verified ||
        source == null ||
        source.isEmpty ||
        fingerprint == null ||
        fingerprint.isEmpty) {
      throw const BroadcastPurchaseException(BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.verificationFailed,
          message: 'Verified purchase evidence is missing.'));
    }
    await _preferences.setString(_verificationSourceKey, source);
    await _preferences.setString(_verificationFingerprintKey, fingerprint);
    await _preferences.setInt(_verifiedAtMsKey, _nowMs());
    await _preferences.setBool(_unlockedKey, true);
  }

  int _effectiveUsedMs() {
    final stored = _preferences.getInt(_usedMsKey) ?? 0;
    if (_activeSessions.isEmpty || _activeStartedAtMs == null) return stored;
    return (stored +
            (_nowMs() - _activeStartedAtMs!)
                .clamp(0, _freeLimit.inMilliseconds))
        .toInt();
  }

  Future<void> _commitActiveElapsed() async {
    final startedAtMs = _activeStartedAtMs;
    _activeStartedAtMs = null;
    if (startedAtMs == null) return;
    final elapsedMs =
        (_nowMs() - startedAtMs).clamp(0, _freeLimit.inMilliseconds);
    final stored = _preferences.getInt(_usedMsKey) ?? 0;
    final next =
        (stored + elapsedMs).clamp(0, _freeLimit.inMilliseconds).toInt();
    await _preferences.setInt(_usedMsKey, next);
  }

  int _nowMs() => _now().millisecondsSinceEpoch;

  String _normalizeSessionId(String sessionId) {
    final trimmed = sessionId.trim();
    return trimmed.isEmpty ? 'broadcast' : trimmed;
  }
}
