class MiuCamFeatureFlags {
  const MiuCamFeatureFlags._();

  /// Paid broadcast/watch access is intentionally hidden in normal test builds.
  /// Enable only for explicit store/paywall verification builds with:
  /// `--dart-define=MIUCAM_BROADCAST_PAYWALL_ENABLED=true`.
  static const broadcastPaywallEnabled = bool.fromEnvironment(
    'MIUCAM_BROADCAST_PAYWALL_ENABLED',
    defaultValue: false,
  );
}
