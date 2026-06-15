import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class CertificateFingerprint {
  static String sha256Hex(List<int> certificateDerOrPemBytes) => sha256.convert(certificateDerOrPemBytes).toString();

  static bool matchesPinnedFingerprint({required List<int> certificateBytes, required String expectedSha256Hex}) {
    final actual = sha256Hex(Uint8List.fromList(certificateBytes));
    return actual.toLowerCase() == expectedSha256Hex.toLowerCase();
  }
}
