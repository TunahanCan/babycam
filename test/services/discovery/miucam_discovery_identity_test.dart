import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/discovery/miucam_discovery_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('discovery identity is created once and survives provider recreation',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final identity = PersistentMiuCamDiscoveryIdentity(preferences);

    final values = await Future.wait([
      identity.getOrCreate(),
      identity.getOrCreate(),
      identity.getOrCreate(),
    ]);
    final stored = preferences.getString(identity.storageKey);
    final recreated =
        await PersistentMiuCamDiscoveryIdentity(preferences).getOrCreate();

    expect(values.toSet(), hasLength(1));
    expect(values.first, startsWith('server_'));
    expect(values.first, hasLength('server_'.length + 32));
    expect(stored, values.first);
    expect(recreated, values.first);
  });

  test('existing non-empty identity is retained', () async {
    SharedPreferences.setMockInitialValues({
      'discovery.server_device_id': 'persisted-device-id',
    });
    final preferences = await SharedPreferences.getInstance();

    final value =
        await PersistentMiuCamDiscoveryIdentity(preferences).getOrCreate();

    expect(value, 'persisted-device-id');
  });
}
