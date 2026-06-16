import 'package:mimicam/analysis/alert/alert_type.dart';
import 'package:mimicam/analysis/alert/cooldown_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CooldownPolicy', () {
    late CooldownPolicy policy;

    setUp(() {
      policy = CooldownPolicy(
        cooldownMsByType: {
          AlertType.cryDetected: 1000,
          AlertType.motionDetected: 500,
          AlertType.loudSound: 0,
        },
      );
    });

    test('allows first event', () {
      expect(policy.canEmit(AlertType.cryDetected, 1000), isTrue);
    });

    test('blocks within cooldown after markEmitted', () {
      policy.markEmitted(AlertType.cryDetected, 1000);

      expect(policy.canEmit(AlertType.cryDetected, 1500), isFalse);
    });

    test('allows after cooldown expires', () {
      policy.markEmitted(AlertType.cryDetected, 1000);

      expect(policy.canEmit(AlertType.cryDetected, 2000), isTrue);
    });

    test('different alert types do not affect each other', () {
      policy.markEmitted(AlertType.cryDetected, 1000);

      expect(policy.canEmit(AlertType.motionDetected, 1001), isTrue);
    });

    test('remainingMs is calculated correctly', () {
      policy.markEmitted(AlertType.cryDetected, 1000);

      expect(policy.remainingMs(AlertType.cryDetected, 1250), 750);
      expect(policy.remainingMs(AlertType.cryDetected, 2000), 0);
    });

    test('reset for one type clears only that type', () {
      policy
        ..markEmitted(AlertType.cryDetected, 1000)
        ..markEmitted(AlertType.motionDetected, 1000)
        ..reset(AlertType.cryDetected);

      expect(policy.canEmit(AlertType.cryDetected, 1100), isTrue);
      expect(policy.canEmit(AlertType.motionDetected, 1100), isFalse);
    });

    test('reset with no type clears all cooldowns', () {
      policy
        ..markEmitted(AlertType.cryDetected, 1000)
        ..markEmitted(AlertType.motionDetected, 1000)
        ..reset();

      expect(policy.canEmit(AlertType.cryDetected, 1100), isTrue);
      expect(policy.canEmit(AlertType.motionDetected, 1100), isTrue);
    });

    test('timestamp moving backwards does not crash and remains safe', () {
      policy.markEmitted(AlertType.cryDetected, 1000);

      expect(() => policy.canEmit(AlertType.cryDetected, 900), returnsNormally);
      expect(policy.canEmit(AlertType.cryDetected, 900), isFalse);
    });

    test('zero cooldown always permits emission', () {
      policy.markEmitted(AlertType.loudSound, 1000);

      expect(policy.canEmit(AlertType.loudSound, 1000), isTrue);
    });
  });
}
