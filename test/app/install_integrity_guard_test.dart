import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/app/install_integrity_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('fresh installation clears stale secure storage once', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var clears = 0;
    const guard = InstallIntegrityGuard();

    await guard.prepare(
      preferences,
      clearSecureStorage: () async => clears++,
    );
    await guard.prepare(
      preferences,
      clearSecureStorage: () async => clears++,
    );

    expect(clears, 1);
    expect(preferences.getBool(InstallIntegrityGuard.markerKey), isTrue);
  });

  test('existing installation upgrade preserves secure storage', () async {
    SharedPreferences.setMockInitialValues({'app_role': 'client'});
    final preferences = await SharedPreferences.getInstance();
    var clears = 0;

    await const InstallIntegrityGuard().prepare(
      preferences,
      clearSecureStorage: () async => clears++,
    );

    expect(clears, 0);
    expect(preferences.getBool(InstallIntegrityGuard.markerKey), isTrue);
  });
}
