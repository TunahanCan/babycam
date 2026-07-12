import 'package:shared_preferences/shared_preferences.dart';

import '../core/security/mimicam_secure_storage.dart';

class InstallIntegrityGuard {
  const InstallIntegrityGuard();

  static const markerKey = 'installation.initialized.v1';

  Future<void> prepare(
    SharedPreferences preferences, {
    Future<void> Function()? clearSecureStorage,
  }) async {
    if (preferences.getBool(markerKey) == true) return;

    // iOS Keychain can outlive an uninstall while SharedPreferences does not.
    // Existing preferences mean this is an upgrade, not a clean reinstall.
    final isFreshInstallation = preferences.getKeys().isEmpty;
    if (isFreshInstallation) {
      await (clearSecureStorage ?? mimicamSecureStorage.deleteAll)();
    }
    await preferences.setBool(markerKey, true);
  }
}
