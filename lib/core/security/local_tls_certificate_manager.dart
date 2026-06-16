import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'certificate_fingerprint.dart';
import 'secure_random_token_generator.dart';

class LocalTlsIdentity {
  const LocalTlsIdentity(
      {required this.certificatePem,
      required this.privateKeyPem,
      required this.fingerprintSha256});
  final String certificatePem;
  final String privateKeyPem;
  final String fingerprintSha256;
}

abstract class LocalTlsCertificateManager {
  Future<LocalTlsIdentity> loadOrCreateIdentity();
}

/// Persistent per-device TLS identity placeholder.
///
/// Dart's `HttpServer.bindSecure` requires platform-compatible PEM material.
/// This manager deliberately avoids a shared hardcoded certificate and provides
/// a stable fingerprint/pinning abstraction. Replacing `_createIdentity` with
/// native/platform certificate generation keeps all callers unchanged.
class SharedPreferencesLocalTlsCertificateManager
    implements LocalTlsCertificateManager {
  SharedPreferencesLocalTlsCertificateManager(this._prefs,
      {SecureRandomTokenGenerator? tokenGenerator})
      : _tokenGenerator = tokenGenerator ?? SecureRandomTokenGenerator();

  final SharedPreferences _prefs;
  final SecureRandomTokenGenerator _tokenGenerator;

  static const _certificateKey = 'mimicam.localTls.certificatePem';
  static const _privateKeyKey = 'mimicam.localTls.privateKeyPem';

  @override
  Future<LocalTlsIdentity> loadOrCreateIdentity() async {
    var certificate = _prefs.getString(_certificateKey);
    var privateKey = _prefs.getString(_privateKeyKey);
    if (certificate == null || privateKey == null) {
      final identity = _createIdentity();
      await _prefs.setString(_certificateKey, identity.certificatePem);
      await _prefs.setString(_privateKeyKey, identity.privateKeyPem);
      return identity;
    }
    return LocalTlsIdentity(
      certificatePem: certificate,
      privateKeyPem: privateKey,
      fingerprintSha256:
          CertificateFingerprint.sha256Hex(utf8.encode(certificate)),
    );
  }

  LocalTlsIdentity _createIdentity() {
    final seed = _tokenGenerator.generateHex(byteCount: 64);
    final certificate =
        '-----BEGIN MIMICAM LOCAL CERTIFICATE-----\n$seed\n-----END MIMICAM LOCAL CERTIFICATE-----';
    final privateKey =
        '-----BEGIN MIMICAM LOCAL PRIVATE KEY-----\n${_tokenGenerator.generateHex(byteCount: 64)}\n-----END MIMICAM LOCAL PRIVATE KEY-----';
    return LocalTlsIdentity(
      certificatePem: certificate,
      privateKeyPem: privateKey,
      fingerprintSha256:
          CertificateFingerprint.sha256Hex(utf8.encode(certificate)),
    );
  }
}
