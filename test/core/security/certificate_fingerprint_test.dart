import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/security/certificate_fingerprint.dart';

void main() {
  test('sha256HexOfDer deterministic çalışır', () {
    final bytes = utf8.encode('mimicam-cert');

    expect(
      CertificateFingerprint.sha256HexOfDer(bytes),
      CertificateFingerprint.sha256HexOfDer(bytes),
    );
    expect(CertificateFingerprint.sha256HexOfDer(bytes), hasLength(64));
  });

  test('normalizeHex ayırıcıları ve case farkını temizler', () {
    expect(
      CertificateFingerprint.normalizeHex('AA:bb- CC dd'),
      'aabbccdd',
    );
  });

  test('constantTimeEqualsHex eşit hex için true döner', () {
    expect(
      CertificateFingerprint.constantTimeEqualsHex('AA:BB', 'aa-bb'),
      isTrue,
    );
  });

  test('constantTimeEqualsHex farklı hex için false döner', () {
    expect(
      CertificateFingerprint.constantTimeEqualsHex('aabb', 'aabc'),
      isFalse,
    );
  });
}
