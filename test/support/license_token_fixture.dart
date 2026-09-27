import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';

class LicenseTokenFixture {
  LicenseTokenFixture._(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;
  final List<int> publicKey;

  static Future<LicenseTokenFixture> create({int seed = 7}) async {
    final keyPair =
        await Ed25519().newKeyPairFromSeed(List<int>.filled(32, seed));
    final publicKey = await keyPair.extractPublicKey();
    return LicenseTokenFixture._(keyPair, publicKey.bytes);
  }

  Future<String> token({
    Map<String, Object?> claims = const {},
    Map<String, Object?> header = const {'alg': 'EdDSA', 'typ': 'JWT'},
  }) async {
    final payload = {
      'aud': 'miucam',
      'version': 1,
      'productId': BroadcastAccessConfig.productId,
      'entitlementId': 'household_test',
      'source': 'google_play',
      'transactionFingerprint': 'a' * 64,
      'issuedAtMs': 1700000000000,
      'status': 'active',
      ...claims,
    };
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final input = '${encode(header)}.${encode(payload)}';
    final signature =
        await Ed25519().sign(ascii.encode(input), keyPair: _keyPair);
    return '$input.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
  }
}
