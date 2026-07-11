import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/feature_flags.dart';

void main() {
  test('broadcast paywall test buildlerinde varsayılan olarak kapalıdır', () {
    expect(MimiCamFeatureFlags.broadcastPaywallEnabled, isFalse);
  });
}
