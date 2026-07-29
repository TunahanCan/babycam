import 'package:shared_preferences/shared_preferences.dart';

import '../../core/security/secure_random_token_generator.dart';

/// Persists the DNS-SD identity independently from a device's changing IP.
class PersistentMiuCamDiscoveryIdentity {
  PersistentMiuCamDiscoveryIdentity(
    this._preferences, {
    SecureRandomTokenGenerator? tokenGenerator,
    this.storageKey = 'discovery.server_device_id',
  }) : _tokenGenerator = tokenGenerator ?? SecureRandomTokenGenerator();

  final SharedPreferences _preferences;
  final SecureRandomTokenGenerator _tokenGenerator;
  final String storageKey;
  Future<String>? _inFlight;

  Future<String> getOrCreate() {
    final current = _preferences.getString(storageKey)?.trim();
    if (current != null && current.isNotEmpty) return Future.value(current);
    return _inFlight ??= _create().whenComplete(() => _inFlight = null);
  }

  Future<String> _create() async {
    final existing = _preferences.getString(storageKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = 'server_${_tokenGenerator.generateHex(byteCount: 16)}';
    await _preferences.setString(storageKey, generated);
    return generated;
  }
}
