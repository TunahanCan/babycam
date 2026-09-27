import 'dart:math';

import 'purchase_verification_result.dart';

class BroadcastAccessConfig {
  const BroadcastAccessConfig._();

  static const freeLimit = Duration(hours: 2);
  static const oneTimePriceTry = 350;
  static const oneTimePriceLabel = '350 TL';
  // Keep the original store identity so previous purchases remain restorable.
  // The current price is configured in the stores, independently of this ID.
  static const productId = 'miucam_lifetime_unlock_try_300';
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
    this.hasStorePrice = false,
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
  final bool hasStorePrice;
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
      hasStorePrice: json['hasStorePrice'] == true,
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
    bool? hasStorePrice,
  }) =>
      BroadcastAccessSnapshot(
        unlocked: unlocked ?? this.unlocked,
        active: active ?? this.active,
        freeLimitMs: freeLimitMs,
        usedMs: usedMs ?? this.usedMs,
        remainingMs: remainingMs ?? this.remainingMs,
        priceLabel: priceLabel ?? this.priceLabel,
        hasStorePrice: hasStorePrice ?? this.hasStorePrice,
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
        'hasStorePrice': hasStorePrice,
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
  noPurchaseFound,
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
    this.licenseToken,
    this.failureReason,
  });

  final BroadcastPurchaseStatus status;
  final String? message;
  final bool verified;
  final String? verificationSource;
  final String? verificationFingerprint;
  final String verificationAuthority;
  final String entitlementId;
  final String? localizedPrice;
  final String? licenseToken;
  final BroadcastPurchaseFailureReason? failureReason;

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

typedef BroadcastPurchaseDelivery = Future<void> Function(
    BroadcastPurchaseResult result);

/// Store acknowledgement is permitted only after the entitlement owner has
/// durably accepted the verified transaction.
abstract interface class BroadcastPurchaseDeliveryGateway {
  void attachDeliveryHandler(BroadcastPurchaseDelivery handler);
  void detachDeliveryHandler(BroadcastPurchaseDelivery handler);
}

abstract interface class BroadcastEntitlementRefreshGateway {
  bool get checkoutConfigured;
  Future<BroadcastPurchaseResult> refreshLicense(String licenseToken);
}

abstract interface class BroadcastOwnedPurchaseGateway {
  Future<void> reconcilePurchases(
      {bool includeFinished = true, bool force = false});
}

abstract interface class BroadcastProductOfferGateway {
  BroadcastProductOffer? get cachedOffer;

  Future<BroadcastProductOffer?> loadOffer({required String productId});
}

class BroadcastAccessPersistenceException implements Exception {
  const BroadcastAccessPersistenceException(this.cause);

  final Object cause;

  @override
  String toString() => 'BROADCAST_ACCESS_PERSISTENCE_FAILED: $cause';
}
