import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:miucam/services/monetization/purchase_verification.dart';

void main() {
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
