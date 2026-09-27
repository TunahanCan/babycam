import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/media/remote_broadcast_access_client.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:miucam/services/monetization/license_grant.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/deterministic_server_media_source.dart';

void main() {
  test(
      'Python verified purchase activates real Dart room and signed refund locks it',
      () async {
    final root = Directory.current.absolute.path;
    final python = Platform.environment['MIUCAM_BACKEND_TEST_PYTHON'] ??
        '$root/build/purchase_backend_venv/bin/python';
    expect(File(python).existsSync(), isTrue,
        reason:
            'Install backend/requirements-test.txt in a virtual environment '
            'and set MIUCAM_BACKEND_TEST_PYTHON to its Python executable.');
    final temporary = await Directory.systemTemp.createTemp('miucam-billing-');
    final process = await Process.start(
      python,
      ['tests/fixture_server.py', '${temporary.path}/licenses.sqlite3'],
      workingDirectory: '$root/backend',
      environment: {'PYTHONPATH': '$root/backend'},
    );
    final errors = StringBuffer();
    final errorSubscription =
        process.stderr.transform(utf8.decoder).listen(errors.write);
    addTearDown(() async {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      await errorSubscription.cancel();
      await temporary.delete(recursive: true);
    });
    final startup = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 15),
            onTimeout: () =>
                throw StateError('Backend failed to start: $errors'));
    final configuration = jsonDecode(startup) as Map<String, dynamic>;
    final endpoint =
        Uri.parse('http://127.0.0.1:${configuration['port']}/verify');
    final publicKey = configuration['publicKey'] as String;
    final grants = LicenseGrantVerifier(
        publicKey: base64Url.decode(base64Url.normalize(publicKey)));
    final verifier = TrustedBackendPurchaseVerifier(
      endpoint: endpoint,
      allowInsecureEndpointForTesting: true,
    );
    expect(
        await verifier.preflight(
          productId: BroadcastAccessConfig.productId,
          source: 'google_play',
          licensePublicKey: publicKey,
        ),
        isTrue,
        reason: 'Ready backend must accept the matching release key. $errors');
    expect(
        await verifier.preflight(
          productId: BroadcastAccessConfig.productId,
          source: 'google_play',
          licensePublicKey: 'a-different-release-key',
        ),
        isFalse);
    final purchase = PurchaseDetails(
      productID: BroadcastAccessConfig.productId,
      purchaseID: 'synthetic-integration-order',
      transactionDate: '1800000000000',
      status: PurchaseStatus.purchased,
      verificationData: PurchaseVerificationData(
        source: 'google_play',
        serverVerificationData: 'synthetic-integration-purchase',
        localVerificationData: '{"purchaseState":0}',
      ),
    );
    final verified = await verifier.verify(purchase,
        expectedProductId: BroadcastAccessConfig.productId);
    expect(verified.verified, isTrue);
    final activeToken = verified.licenseToken!;
    final decoded = await grants.verify(activeToken,
        expectedProductId: BroadcastAccessConfig.productId);
    expect(decoded.entitlementId, verified.entitlementId);
    expect(decoded.transactionFingerprint, verified.fingerprint);
    expect(decoded.source, 'google_play');
    expect(decoded.status, LicenseGrantStatus.active);

    // This opt-in integration test lives under tool/ because it needs Python.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms':
          BroadcastAccessConfig.freeLimit.inMilliseconds,
    });
    final preferences = await SharedPreferences.getInstance();
    final roomStore = _NoRoomStore();
    final access = BroadcastAccessService(preferences,
        purchaseGateway: roomStore, licenseGrantVerifier: grants);
    final tokens = PairingTokenService();
    final room = MiuCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      httpPort: 0,
      startMediaOnSessionStart: false,
      mediaSource: DeterministicServerMediaSource(),
      broadcastAccess: access,
      licenseGrantVerifier: grants,
      onStreamSessionStarted: (_,
          {required video, required audio, required mediaTransport}) async {},
      onStreamSessionStopped: (_) async {},
    );
    addTearDown(() async {
      await room.dispose();
      await access.dispose();
      tokens.dispose();
    });
    final address = Uri.parse(await room.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
        clientName: 'Parent', deviceId: 'parent');
    final session = PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: '127.0.0.1',
        port: address.port,
        deviceId: 'room',
        deviceName: 'Baby Room',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: trusted.token,
    );
    final remote = RemoteBroadcastAccessClient();
    expect((await remote.snapshot(session))!.isLocked, isTrue);
    expect((await remote.activate(session, activeToken)).unlocked, isTrue);
    expect(await remote.readLicense(session), activeToken);
    expect(roomStore.calls, 0,
        reason:
            'No payment account or backend connectivity is needed on the room phone.');

    final client = HttpClient();
    try {
      final request =
          await client.postUrl(endpoint.replace(path: '/fixture/revoke'));
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, 200);
    } finally {
      client.close(force: true);
    }
    final revoked = await verifier.refreshLicense(activeToken,
        expectedProductId: BroadcastAccessConfig.productId);
    expect(revoked.failureReason, BroadcastPurchaseFailureReason.revoked);
    final revokedGrant = await grants.verify(revoked.licenseToken!,
        expectedProductId: BroadcastAccessConfig.productId);
    expect(revokedGrant.status, LicenseGrantStatus.revoked);
    expect(revokedGrant.entitlementId, decoded.entitlementId);
    expect(revokedGrant.transactionFingerprint, decoded.transactionFingerprint);
    expect(revokedGrant.issuedAtMs, greaterThan(decoded.issuedAtMs));
    expect((await remote.activate(session, revoked.licenseToken!)).isLocked,
        isTrue);
    await expectLater(
        remote.activate(session, activeToken), throwsA(isA<HttpException>()));
    expect(await remote.readLicense(session), isNull);
    expect(roomStore.calls, 0);
  }, timeout: const Timeout(Duration(seconds: 45)));
}

class _NoRoomStore extends BroadcastPurchaseGateway {
  int calls = 0;
  @override
  Future<BroadcastPurchaseResult> purchase(
          {required String productId, required String priceLabel}) =>
      restore(productId: productId);
  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async {
    calls++;
    return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable);
  }
}
