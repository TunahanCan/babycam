class MiuCamFeatureFlags {
  const MiuCamFeatureFlags._();

  /// Room devices include two cumulative free hours, then require a lifetime
  /// unlock. Only diagnostic builds should explicitly disable this policy.
  static const broadcastPaywallEnabled = bool.fromEnvironment(
    'MIUCAM_BROADCAST_PAYWALL_ENABLED',
    defaultValue: true,
  );
}
