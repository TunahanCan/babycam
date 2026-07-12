import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android LAN server owns an independent foreground-service lease', () {
    final activity = File(
      'android/app/src/main/kotlin/com/mimicam/app/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/mimicam/app/'
      'MimiCamForegroundService.kt',
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
