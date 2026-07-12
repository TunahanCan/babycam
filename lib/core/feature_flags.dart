import 'package:flutter/foundation.dart';

class MimiCamFeatureFlags {
  const MimiCamFeatureFlags._();

  /// Paid broadcast/watch access is intentionally hidden in normal test builds.
  /// Enable only for explicit store/paywall verification builds with:
  /// `--dart-define=MIMICAM_BROADCAST_PAYWALL_ENABLED=true`.
  static const broadcastPaywallEnabled = bool.fromEnvironment(
    'MIMICAM_BROADCAST_PAYWALL_ENABLED',
    defaultValue: false,
  );

  /// Destructive diagnostics are available in debug builds only unless an
  /// explicit internal build opts in.
  static const testEndpointsEnabled = bool.fromEnvironment(
    'MIMICAM_TEST_ENDPOINTS_ENABLED',
    defaultValue: kDebugMode,
  );
}
