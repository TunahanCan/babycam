import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:miucam/services/monetization/license_grant.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/license_token_fixture.dart';

void main() {
  late LicenseTokenFixture fixture;
  late LicenseGrantVerifier verifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = await LicenseTokenFixture.create();
    verifier = LicenseGrantVerifier(publicKey: fixture.publicKey);
  });

  test('signed purchase survives restart without leaking its transfer token',
      () async {
    final token = await fixture.token();
    final prefs = await SharedPreferences.getInstance();
    final gateway = _Gateway()..result = _result(token);
    final service = BroadcastAccessService(prefs,
        purchaseGateway: gateway, licenseGrantVerifier: verifier);
    final snapshot = await service.unlockWithOneTimePurchase();
    expect(snapshot.unlocked, isTrue);
    expect(service.licenseToken, token);
    expect(snapshot.toJson().containsKey('licenseToken'), isFalse);
    expect(snapshot.toJson().values, isNot(contains(token)));
    await service.dispose();
    final restarted = BroadcastAccessService(prefs,
        purchaseGateway: _Gateway(), licenseGrantVerifier: verifier);
    addTearDown(restarted.dispose);
    expect((await restarted.snapshot()).unlocked, isTrue);
    expect(restarted.licenseToken, token);
  });

  test(
      'signed revocation persists and blocks older or conflicting active replay',
      () async {
    final active = await fixture.token();
    final revoked = await fixture
        .token(claims: {'status': 'revoked', 'issuedAtMs': 1700000000001});
    final conflicting =
        await fixture.token(claims: {'issuedAtMs': 1700000000001});
    final prefs = await SharedPreferences.getInstance();
    final service = BroadcastAccessService(prefs,
        purchaseGateway: _Gateway(), licenseGrantVerifier: verifier);
    await service.applyVerifiedLicenseGrant(await _grant(verifier, active));
    expect(
        (await service
                .applyVerifiedLicenseGrant(await _grant(verifier, revoked)))
            .isLocked,
        isTrue);
    await service.dispose();
    final restarted = BroadcastAccessService(prefs,
        purchaseGateway: _Gateway(), licenseGrantVerifier: verifier);
    addTearDown(restarted.dispose);
    expect((await restarted.snapshot()).isLocked, isTrue);
    for (final token in [active, conflicting]) {
      await expectLater(
          restarted.applyVerifiedLicenseGrant(await _grant(verifier, token)),
          throwsA(isA<LicenseGrantException>()
              .having((e) => e.code, 'code', 'LICENSE_GRANT_STALE')));
    }
    expect(restarted.licenseToken, revoked);
    expect((await restarted.snapshot()).isLocked, isTrue);
  });

  test('revocation for another family cannot remove the current family right',
      () async {
    final service = BroadcastAccessService(
        await SharedPreferences.getInstance(),
        purchaseGateway: _Gateway(),
        licenseGrantVerifier: verifier);
    addTearDown(service.dispose);
    await service.applyVerifiedLicenseGrant(
        await _grant(verifier, await fixture.token()));
    final unrelated = await fixture.token(claims: {
      'entitlementId': 'other_family',
      'status': 'revoked',
      'issuedAtMs': 1700000000001,
    });
    await expectLater(
        service.applyVerifiedLicenseGrant(await _grant(verifier, unrelated)),
        throwsA(isA<LicenseGrantException>()
            .having((e) => e.code, 'code', 'LICENSE_ENTITLEMENT_MISMATCH')));
    expect((await service.snapshot()).unlocked, isTrue);
  });

  test('unverified backend metadata cannot contradict its signed grant',
      () async {
    final gateway = _Gateway()
      ..result =
          _result(await fixture.token(), entitlementId: 'different_family');
    final service = BroadcastAccessService(
        await SharedPreferences.getInstance(),
        purchaseGateway: gateway,
        licenseGrantVerifier: verifier);
    addTearDown(service.dispose);
    await expectLater(service.unlockWithOneTimePurchase(),
        throwsA(isA<LicenseGrantException>()));
    expect((await service.snapshot()).unlocked, isFalse);
    expect(service.licenseToken, isNull);
  });

  test(
      'background refresh retains offline rights and applies matching signed revocation',
      () async {
    var monotonicMs = 0;
    final gateway = _Gateway();
    final service = BroadcastAccessService(
        await SharedPreferences.getInstance(),
        purchaseGateway: gateway,
        licenseGrantVerifier: verifier,
        monotonicNowMs: () => monotonicMs);
    addTearDown(service.dispose);
    final active = await fixture.token();
    await service.applyVerifiedLicenseGrant(await _grant(verifier, active));
    expect((await service.refreshEntitlement()).unlocked, isTrue);
    expect(gateway.refreshCalls, 1);
    expect(gateway.lastRefreshToken, active);
    await service.refreshEntitlement();
    expect(gateway.refreshCalls, 1);
    monotonicMs += const Duration(hours: 6).inMilliseconds;
    final revoked = await fixture
        .token(claims: {'status': 'revoked', 'issuedAtMs': 1700000000001});
    gateway.refreshResult = _result(revoked, revoked: true);
    expect((await service.refreshEntitlement()).isLocked, isTrue);
    expect(gateway.refreshCalls, 2);
    expect(service.licenseToken, revoked);
  });

  test('invalid signed refresh cannot revoke a saved lifetime right', () async {
    final gateway = _Gateway();
    final service = BroadcastAccessService(
        await SharedPreferences.getInstance(),
        purchaseGateway: gateway,
        licenseGrantVerifier: verifier);
    addTearDown(service.dispose);
    final active = await fixture.token();
    await service.applyVerifiedLicenseGrant(await _grant(verifier, active));
    gateway.refreshResult = _result('forged-license', revoked: true);
    expect((await service.refreshEntitlement()).unlocked, isTrue);
    expect(service.licenseToken, active);
  });
}

Future<VerifiedLicenseGrant> _grant(
        LicenseGrantVerifier verifier, String token) =>
    verifier.verify(token, expectedProductId: BroadcastAccessConfig.productId);

BroadcastPurchaseResult _result(String token,
        {bool revoked = false, String entitlementId = 'household_test'}) =>
    BroadcastPurchaseResult(
      status: revoked
          ? BroadcastPurchaseStatus.verificationFailed
          : BroadcastPurchaseStatus.restored,
      verified: !revoked,
      verificationSource: 'google_play',
      verificationFingerprint: 'a' * 64,
      entitlementId: entitlementId,
      licenseToken: token,
      failureReason: revoked ? BroadcastPurchaseFailureReason.revoked : null,
    );

class _Gateway
    implements BroadcastPurchaseGateway, BroadcastEntitlementRefreshGateway {
  BroadcastPurchaseResult result = const BroadcastPurchaseResult(
      status: BroadcastPurchaseStatus.unavailable);
  BroadcastPurchaseResult refreshResult = const BroadcastPurchaseResult(
      status: BroadcastPurchaseStatus.verificationFailed,
      failureReason: BroadcastPurchaseFailureReason.transient);
  int refreshCalls = 0;
  String? lastRefreshToken;
  @override
  bool get checkoutConfigured => true;
  @override
  Future<BroadcastPurchaseResult> purchase(
          {required String productId, required String priceLabel}) async =>
      result;
  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async =>
      result;
  @override
  Future<BroadcastPurchaseResult> refreshLicense(String licenseToken) async {
    refreshCalls++;
    lastRefreshToken = licenseToken;
    return refreshResult;
  }

  @override
  Future<void> dispose() async {}
}
