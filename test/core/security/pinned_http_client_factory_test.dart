import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/security/certificate_fingerprint.dart';
import 'package:mimicam/core/security/pinned_http_client_factory.dart';

void main() {
  test('matching fingerprint kabul edilir', () {
    final der = utf8.encode('cert');
    final fingerprint = CertificateFingerprint.sha256HexOfDer(der);

    expect(
      PinnedHttpClientFactory().acceptsCertificate(
        certificateDerBytes: der,
        host: '192.168.1.20',
        port: 8080,
        expectedFingerprintSha256Hex: fingerprint,
        expectedHost: '192.168.1.20',
        expectedPort: 8080,
      ),
      isTrue,
    );
  });

  test('mismatch fingerprint reddedilir', () {
    expect(
      PinnedHttpClientFactory().acceptsCertificate(
        certificateDerBytes: utf8.encode('cert'),
        host: '192.168.1.20',
        port: 8080,
        expectedFingerprintSha256Hex: '00' * 32,
        expectedHost: '192.168.1.20',
        expectedPort: 8080,
      ),
      isFalse,
    );
  });

  test('yanlış host reddedilir', () {
    final der = utf8.encode('cert');
    final fingerprint = CertificateFingerprint.sha256HexOfDer(der);

    expect(
      PinnedHttpClientFactory().acceptsCertificate(
        certificateDerBytes: der,
        host: '192.168.1.21',
        port: 8080,
        expectedFingerprintSha256Hex: fingerprint,
        expectedHost: '192.168.1.20',
        expectedPort: 8080,
      ),
      isFalse,
    );
  });

  test('yanlış port reddedilir', () {
    final der = utf8.encode('cert');
    final fingerprint = CertificateFingerprint.sha256HexOfDer(der);

    expect(
      PinnedHttpClientFactory().acceptsCertificate(
        certificateDerBytes: der,
        host: '192.168.1.20',
        port: 8081,
        expectedFingerprintSha256Hex: fingerprint,
        expectedHost: '192.168.1.20',
        expectedPort: 8080,
      ),
      isFalse,
    );
  });
}
