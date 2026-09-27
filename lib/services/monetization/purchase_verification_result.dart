const trustedBackendVerificationAuthority = 'trusted_backend';

enum BroadcastPurchaseFailureReason {
  transient,
  rejected,
  revoked,
  configuration;

  static BroadcastPurchaseFailureReason fromCode(Object? code) =>
      values.where((value) => value.name == code).firstOrNull ?? rejected;
}

class BroadcastPurchaseVerification {
  const BroadcastPurchaseVerification._({
    required this.verified,
    required this.source,
    required this.authority,
    this.fingerprint,
    this.entitlementId,
    this.reason,
    this.failureReason,
    this.licenseToken,
  });

  const BroadcastPurchaseVerification.verified({
    required String source,
    required String fingerprint,
    required String entitlementId,
    String authority = trustedBackendVerificationAuthority,
    String? licenseToken,
  }) : this._(
          verified: true,
          source: source,
          authority: authority,
          fingerprint: fingerprint,
          entitlementId: entitlementId,
          licenseToken: licenseToken,
        );

  const BroadcastPurchaseVerification.rejected({
    required String source,
    required String reason,
    String authority = trustedBackendVerificationAuthority,
    BroadcastPurchaseFailureReason failureReason =
        BroadcastPurchaseFailureReason.rejected,
    String? fingerprint,
    String? entitlementId,
    String? licenseToken,
  }) : this._(
          verified: false,
          source: source,
          authority: authority,
          reason: reason,
          failureReason: failureReason,
          fingerprint: fingerprint,
          entitlementId: entitlementId,
          licenseToken: licenseToken,
        );

  final bool verified;
  final String source;
  final String authority;
  final String? fingerprint;
  final String? entitlementId;
  final String? reason;
  final BroadcastPurchaseFailureReason? failureReason;
  final String? licenseToken;
}
