import 'dart:convert';

import 'package:crypto/crypto.dart';

class CertificateFingerprint {
  static String sha256HexOfDer(List<int> derBytes) =>
      sha256.convert(derBytes).toString();

  static String normalizeHex(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s:\-]'), '');

  static bool constantTimeEqualsHex(String a, String b) {
    final normalizedA = normalizeHex(a);
    final normalizedB = normalizeHex(b);
    final bytesA = utf8.encode(normalizedA);
    final bytesB = utf8.encode(normalizedB);
    final maxLength =
        bytesA.length > bytesB.length ? bytesA.length : bytesB.length;
    var diff = bytesA.length ^ bytesB.length;
    for (var i = 0; i < maxLength; i++) {
      final byteA = i < bytesA.length ? bytesA[i] : 0;
      final byteB = i < bytesB.length ? bytesB[i] : 0;
      diff |= byteA ^ byteB;
    }
    return diff == 0;
  }
}
