import 'dart:io';

import 'certificate_fingerprint.dart';

class PinnedHttpClientFactory {
  HttpClient create({
    required String expectedFingerprintSha256Hex,
    required String expectedHost,
    required int expectedPort,
  }) {
    final normalizedFingerprint =
        CertificateFingerprint.normalizeHex(expectedFingerprintSha256Hex);
    if (normalizedFingerprint.isEmpty) {
      throw StateError('Missing server certificate fingerprint.');
    }
    final client =
        HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.badCertificateCallback =
        (certificate, host, port) => acceptsCertificate(
              certificateDerBytes: certificate.der,
              host: host,
              port: port,
              expectedFingerprintSha256Hex: normalizedFingerprint,
              expectedHost: expectedHost,
              expectedPort: expectedPort,
            );
    return client;
  }

  bool acceptsCertificate({
    required List<int> certificateDerBytes,
    required String host,
    required int port,
    required String expectedFingerprintSha256Hex,
    required String expectedHost,
    required int expectedPort,
  }) {
    final fingerprint =
        CertificateFingerprint.sha256HexOfDer(certificateDerBytes);
    return host == expectedHost &&
        port == expectedPort &&
        CertificateFingerprint.constantTimeEqualsHex(
          fingerprint,
          expectedFingerprintSha256Hex,
        );
  }
}

class PublicStatusCertificateDiscoveryClient {
  PublicStatusCertificateDiscoveryClient();

  String? discoveredFingerprintSha256Hex;

  HttpClient create({
    required String expectedHost,
    required int expectedPort,
  }) {
    final client =
        HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.badCertificateCallback = (certificate, host, port) {
      if (host != expectedHost || port != expectedPort) return false;
      discoveredFingerprintSha256Hex =
          CertificateFingerprint.sha256HexOfDer(certificate.der);
      return true;
    };
    return client;
  }
}
