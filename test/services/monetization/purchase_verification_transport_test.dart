import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:miucam/services/monetization/license_grant.dart';
import 'package:miucam/services/monetization/purchase_verification.dart';

void main() {
  test('verified backend responses require a bounded transferable license',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? token;
    server.listen((request) async {
      await request.drain<void>();
      request.response.write(jsonEncode({
        ..._verifiedResponse,
        'licenseToken': token,
      }));
      await request.response.close();
    });
    final verifier = TrustedBackendPurchaseVerifier(
        endpoint: _endpoint(server), allowInsecureEndpointForTesting: true);
    for (final invalid in <String?>[
      null,
      '',
      'x' * (LicenseGrantVerifier.maxTokenBytes + 1),
    ]) {
      token = invalid;
      final result =
          await verifier.verify(_purchase(), expectedProductId: _productId);
      expect(result.verified, isFalse);
    }
    token = 'signed-backend-license';
    expect(
        (await verifier.verify(_purchase(), expectedProductId: _productId))
            .verified,
        isTrue);
  });

  test('license refresh sends only the signed token and retains revoked claims',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<Map>();
    server.listen((request) async {
      received
          .complete(jsonDecode(await utf8.decoder.bind(request).join()) as Map);
      request.response.write(jsonEncode({
        ..._verifiedResponse,
        'verified': false,
        'reasonCode': 'revoked',
        'licenseToken': 'signed-revoked-license',
      }));
      await request.response.close();
    });
    final verifier = TrustedBackendPurchaseVerifier(
        endpoint: _endpoint(server), allowInsecureEndpointForTesting: true);
    final result = await verifier.refreshLicense('saved-license',
        expectedProductId: _productId);
    expect(await received.future, {'licenseToken': 'saved-license'});
    expect(result.verified, isFalse);
    expect(result.failureReason, BroadcastPurchaseFailureReason.revoked);
    expect(result.licenseToken, 'signed-revoked-license');
    expect(result.entitlementId, 'synthetic-household');
    expect(result.fingerprint, 'a' * 64);
  });

  test(
      'checkout preflight requires ready product, store, and matching signing key',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var response = <String, Object?>{};
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body, {
        'preflight': true,
        'productId': _productId,
        'source': 'google_play'
      });
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    final verifier = TrustedBackendPurchaseVerifier(
        endpoint: _endpoint(server), allowInsecureEndpointForTesting: true);
    const ready = {
      'ready': true,
      'productId': _productId,
      'source': 'google_play',
      'licensePublicKey': 'pinned-key'
    };
    for (final overrides in [
      {'ready': false},
      {'productId': 'wrong'},
      {'source': 'app_store'},
      {'licensePublicKey': 'other-key'},
    ]) {
      response = {...ready, ...overrides};
      expect(
          await verifier.preflight(
              productId: _productId,
              source: 'google_play',
              licensePublicKey: 'pinned-key'),
          isFalse);
    }
    response = ready;
    expect(
        await verifier.preflight(
            productId: _productId,
            source: 'google_play',
            licensePublicKey: 'pinned-key'),
        isTrue);
  });

  test('canceling verification ends stalled headers without any later upload',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var uploads = 0;
    server.listen((request) async {
      uploads++;
      await request.drain<void>();
      await request.response.close();
    });
    final entered = Completer<void>();
    final headers = Completer<Map<String, String>>();
    final verifier = TrustedBackendPurchaseVerifier(
        endpoint: _endpoint(server),
        allowInsecureEndpointForTesting: true,
        timeout: const Duration(minutes: 1),
        headersProvider: () {
          entered.complete();
          return headers.future;
        });
    final result = verifier.verify(_purchase(), expectedProductId: _productId);
    await entered.future;
    verifier.cancelPending();
    expect(
        (await result.timeout(const Duration(milliseconds: 200))).failureReason,
        BroadcastPurchaseFailureReason.transient);
    headers.complete(const {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(uploads, 0);
  });

  test('stalled verification headers time out without a late receipt upload',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var uploads = 0;
    server.listen((request) async {
      uploads++;
      await request.drain<void>();
      request.response.write(jsonEncode(_verifiedResponse));
      await request.response.close();
    });
    final entered = Completer<void>();
    final headers = Completer<Map<String, String>>();
    final verifier = TrustedBackendPurchaseVerifier(
      endpoint: _endpoint(server),
      allowInsecureEndpointForTesting: true,
      timeout: const Duration(milliseconds: 40),
      headersProvider: () {
        entered.complete();
        return headers.future;
      },
    );
    final verification =
        verifier.verify(_purchase(), expectedProductId: _productId);
    addTearDown(() async {
      if (!headers.isCompleted) headers.complete(const {});
      await verification.timeout(const Duration(seconds: 1));
      await server.close(force: true);
    });
    await entered.future.timeout(const Duration(seconds: 1));
    final result =
        await verification.timeout(const Duration(milliseconds: 500));
    expect(result.verified, isFalse);
    expect(result.reason, contains('timed out'));

    headers.complete(const {'Authorization': 'Bearer synthetic-auth'});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(uploads, 0,
        reason: 'An expired header lookup must not upload a receipt later.');
  });

  test(
      'HTTP 303 cannot move trusted purchase verification to another authority',
      () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirected = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => origin.close(force: true));
    addTearDown(() => redirected.close(force: true));
    var redirectedRequests = 0;
    redirected.listen((request) async {
      redirectedRequests++;
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(_verifiedResponse));
      await request.response.close();
    });
    origin.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.seeOther
        ..headers
            .set(HttpHeaders.locationHeader, _endpoint(redirected).toString());
      await request.response.close();
    });
    final verifier = TrustedBackendPurchaseVerifier(
      endpoint: _endpoint(origin),
      allowInsecureEndpointForTesting: true,
      headersProvider: () async =>
          const {'Authorization': 'Bearer synthetic-auth'},
    );
    final result = await verifier
        .verify(_purchase(), expectedProductId: _productId)
        .timeout(const Duration(seconds: 1));
    expect(result.verified, isFalse);
    expect(result.reason, contains('HTTP 303'));
    expect(redirectedRequests, 0);
  });
}

const _productId = 'test.lifetime';
final _verifiedResponse = {
  'verified': true,
  'productId': _productId,
  'source': 'google_play',
  'transactionFingerprint': 'a' * 64,
  'entitlementId': 'synthetic-household',
  'licenseToken': 'signed-backend-license',
};

Uri _endpoint(HttpServer server) => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: server.port,
    path: '/verify');

PurchaseDetails _purchase() => PurchaseDetails(
      purchaseID: 'synthetic-order',
      productID: _productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '{"purchaseState":0}',
        serverVerificationData: 'synthetic-store-receipt',
        source: 'google_play',
      ),
      transactionDate: '1',
      status: PurchaseStatus.purchased,
    );
