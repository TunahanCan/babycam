import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/failing_configuration_preferences.dart';

void main() {
  test('failed writes restore durable settings and allow retry', () async {
    final preferences = FailingConfigurationPreferences({
      'config.motion_threshold': .22,
    })
      ..failKey = 'config.motion_threshold';
    final config = ConfigurationService(preferences);

    await expectLater(config.setMotionThreshold(.4), throwsStateError);
    expect(config.motionThreshold, .22);
    expect(preferences.durable['config.motion_threshold'], .22);

    preferences.failKey = null;
    await config.setMotionThreshold(.4);
    expect(config.motionThreshold, .4);
    expect(preferences.durable['config.motion_threshold'], .4);
  });

  test('thrown writes cannot leave optimistic settings in memory', () async {
    final preferences = FailingConfigurationPreferences({})
      ..failKey = 'config.notify_cooldown_ms'
      ..throwOnWrite = true;
    final config = ConfigurationService(preferences);
    await expectLater(config.setNotifyCooldownMs(10000), throwsStateError);
    expect(config.notifyCooldownMs, 60000);
  });

  test('failed preset write does not overwrite subsequent successful writes',
      () async {
    final preferences = FailingConfigurationPreferences({})
      ..failKey = 'config.motion_threshold';
    final config = ConfigurationService(preferences);
    await expectLater(
      Future.wait([
        config.setMotionThreshold(.4),
        config.setCryScoreThreshold(.8),
        config.setCryMinDurationMs(2500),
        config.setWebRtcPilotEnabled(true),
      ]),
      throwsStateError,
    );
    expect(config.motionThreshold, .22);
    expect(config.cryScoreThreshold, .8);
    expect(config.cryMinDurationMs, 2500);
    expect(config.webRtcPilotEnabled, isTrue);
  });

  test('failed reset is reported and retains the durable setting', () async {
    final preferences = FailingConfigurationPreferences({
      'config.motion_threshold': .4,
      'unrelated.preference': true,
    })
      ..failKey = 'config.motion_threshold';
    final config = ConfigurationService(preferences);
    await expectLater(config.resetToDefaults(), throwsStateError);
    expect(config.motionThreshold, .4);
    preferences.failKey = null;
    await config.resetToDefaults();
    expect(config.motionThreshold, .22);
    expect(preferences.durable, {'unrelated.preference': true});
  });

  test('reset observes earlier queued writes and precedes later edits',
      () async {
    final preferences = FailingConfigurationPreferences({});
    final config = ConfigurationService(preferences);
    await Future.wait([
      config.setMotionThreshold(.4),
      config.resetToDefaults(),
      config.setCryScoreThreshold(.8),
    ]);
    expect(config.motionThreshold, .22);
    expect(config.cryScoreThreshold, .8);
    expect(preferences.durable, {'config.cry_score_threshold': .8});
  });

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
