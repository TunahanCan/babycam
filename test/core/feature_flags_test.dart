import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/feature_flags.dart';

void main() {
  test('broadcast access policy is enabled in normal builds', () {
    expect(MiuCamFeatureFlags.broadcastPaywallEnabled, isTrue);
  });
}
