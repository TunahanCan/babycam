import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('unsafe persisted detection values are clamped to release guardrails',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.motion_threshold': .01,
      'config.cry_score_threshold': .20,
      'config.motion_min_duration_ms': 100,
      'config.cry_min_duration_ms': 500,
      'config.notify_cooldown_ms': 1000,
    });
    final config = ConfigurationService(await SharedPreferences.getInstance());

    expect(config.motionThreshold, ConfigurationService.minMotionThreshold);
    expect(
      config.cryScoreThreshold,
      ConfigurationService.minCryScoreThreshold,
    );
    expect(
      config.motionMinDurationMs,
      ConfigurationService.minDetectionDurationMs,
    );
    expect(
      config.cryMinDurationMs,
      ConfigurationService.minCryEvidenceDurationMs,
    );
    expect(
      config.notifyCooldownMs,
      ConfigurationService.minNotificationCooldownMs,
    );
  });

  test('setters never persist values outside detection guardrails', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final config = ConfigurationService(preferences);

    await config.setMotionThreshold(5);
    await config.setCryScoreThreshold(-1);
    await config.setMotionMinDurationMs(50000);
    await config.setCryMinDurationMs(-1);
    await config.setNotifyCooldownMs(500000);

    expect(config.motionThreshold, ConfigurationService.maxMotionThreshold);
    expect(
      config.cryScoreThreshold,
      ConfigurationService.minCryScoreThreshold,
    );
    expect(
      config.motionMinDurationMs,
      ConfigurationService.maxDetectionDurationMs,
    );
    expect(
      config.cryMinDurationMs,
      ConfigurationService.minCryEvidenceDurationMs,
    );
    expect(
      config.notifyCooldownMs,
      ConfigurationService.maxNotificationCooldownMs,
    );
  });

  test('NaN ve infinity ayarları analyzer içine taşınmaz', () async {
    SharedPreferences.setMockInitialValues({
      'config.motion_threshold': double.nan,
      'config.cry_score_threshold': double.infinity,
    });
    final config = ConfigurationService(await SharedPreferences.getInstance());

    expect(config.motionThreshold, .22);
    expect(config.cryScoreThreshold, .65);

    await config.setMotionThreshold(double.negativeInfinity);
    await config.setCryScoreThreshold(double.nan);
    expect(config.motionThreshold, .22);
    expect(config.cryScoreThreshold, .65);
  });
}
