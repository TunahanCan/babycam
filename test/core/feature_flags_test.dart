import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/feature_flags.dart';

void main() {
  test('broadcast paywall test buildlerinde varsayılan olarak kapalıdır', () {
    expect(MiuCamFeatureFlags.broadcastPaywallEnabled, isFalse);
  });
}
