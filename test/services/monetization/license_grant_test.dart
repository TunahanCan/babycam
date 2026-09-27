import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:miucam/services/monetization/license_grant.dart';

import '../../support/license_token_fixture.dart';

void main() {
  late LicenseTokenFixture fixture;
  late LicenseGrantVerifier verifier;
  setUp(() async {
    fixture = await LicenseTokenFixture.create();
    verifier = LicenseGrantVerifier(publicKey: fixture.publicKey);
  });

  test('backend signed active and revoked lifetime grants verify offline',
      () async {
    for (final status in LicenseGrantStatus.values) {
      final token = await fixture.token(claims: {'status': status.name});
      final grant = await verifier.verify(token,
          expectedProductId: BroadcastAccessConfig.productId);
      expect(grant.status, status);
      expect(grant.token, token);
      expect(grant.entitlementId, 'household_test');
      expect(grant.audience, 'miucam');
      expect(grant.version, 1);
    }
  });

  test('a different signing key cannot authorize a household grant', () async {
    final other = await LicenseTokenFixture.create(seed: 8);
    await expectLater(
      verifier.verify(await other.token(),
          expectedProductId: BroadcastAccessConfig.productId),
      throwsA(isA<LicenseGrantException>()
          .having((e) => e.code, 'code', 'INVALID_LICENSE_TOKEN')),
    );
  });

  for (final claims in <Map<String, Object?>>[
    {'aud': 'other-app'},
    {'version': 1.0},
    {'entitlementId': ''},
    {'source': 'local'},
    {'transactionFingerprint': 'not-a-fingerprint'},
    {'issuedAtMs': 0},
    {'issuedAtMs': '1700000000000'},
    {'status': 'pending'},
    {'exp': 2000000000},
  ]) {
    test('rejects signed malformed claims $claims', () async {
      await expectLater(
        verifier.verify(await fixture.token(claims: claims),
            expectedProductId: BroadcastAccessConfig.productId),
        throwsA(isA<LicenseGrantException>()
            .having((e) => e.code, 'code', 'INVALID_LICENSE_TOKEN')),
      );
    });
  }

  test('wrong product and unsupported signing header are rejected', () async {
    await expectLater(
      verifier.verify(await fixture.token(),
          expectedProductId: 'another.product'),
      throwsA(isA<LicenseGrantException>()
          .having((e) => e.code, 'code', 'LICENSE_PRODUCT_MISMATCH')),
    );
    await expectLater(
      verifier.verify(
          await fixture.token(header: {'alg': 'none', 'typ': 'JWT'}),
          expectedProductId: BroadcastAccessConfig.productId),
      throwsA(isA<LicenseGrantException>()),
    );
  });

  test('invalid config and oversized tokens fail closed', () async {
    final unavailable = LicenseGrantVerifier(publicKey: const []);
    expect(unavailable.isConfigured, isFalse);
    await expectLater(
      unavailable.verify(await fixture.token(),
          expectedProductId: BroadcastAccessConfig.productId),
      throwsA(isA<LicenseGrantException>()
          .having((e) => e.code, 'code', 'LICENSE_VERIFICATION_UNAVAILABLE')),
    );
    await expectLater(
      verifier.verify('a' * (LicenseGrantVerifier.maxTokenBytes + 1),
          expectedProductId: BroadcastAccessConfig.productId),
      throwsA(isA<LicenseGrantException>()
          .having((e) => e.code, 'code', 'LICENSE_TOKEN_TOO_LARGE')),
    );
  });
}
