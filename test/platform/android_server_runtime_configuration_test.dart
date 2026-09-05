import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native runtime notification tracks the persisted app locale', () {
    final service = File(
      'android/app/src/main/kotlin/com/miucam/app/MiuCamForegroundService.kt',
    ).readAsStringSync();
    final preferences =
        File('lib/services/client_preferences_service.dart').readAsStringSync();
    // Guard the cross-language persistence contract; Flutter's legacy store
    // adds the prefix before writing Android SharedPreferences.
    for (final key in ['client.locale.language', 'client.locale.country']) {
      expect(preferences, contains("'$key'"));
      expect(service, contains('"flutter.$key"'));
    }
    expect(
        service, contains('getSharedPreferences("FlutterSharedPreferences"'));
    expect(service, contains('registerOnSharedPreferenceChangeListener(this)'));
    expect(
        service, contains('unregisterOnSharedPreferenceChangeListener(this)'));
    expect(service, contains('override fun onConfigurationChanged'));
    expect(service, contains('configuration.setLocale(locale)'));
    expect(service, contains('createConfigurationContext(configuration)'));
    expect(service,
        contains('localized.getString(R.string.miucam_runtime_title_alerts)'));
  });

  test('Android LAN server owns an independent foreground-service lease', () {
    final activity = File(
      'android/app/src/main/kotlin/com/miucam/app/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/miucam/app/'
      'MiuCamForegroundService.kt',
    ).readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final composition = File('lib/features/server/server_composition_root.dart')
        .readAsStringSync();

    expect(activity, contains('"setServerDemand"'));
    expect(activity, contains('applyServerDemand('));
    expect(service, contains('private var serverDemand = false'));
    expect(service, contains('(alertDemand || serverDemand)'));
    expect(service, contains('acquireWifiLock()'));
    expect(service, contains('foregroundServiceUpdateRejected'));
    expect(service, contains('hasRequestedRuntimeDemand'));
    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE'),
    );
    expect(manifest, contains('connectedDevice'));
    expect(composition, contains('setServerDemand(active: true)'));
    expect(composition, contains('setServerDemand(active: false)'));
  });
}
