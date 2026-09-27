import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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

import '../../support/deterministic_server_media_source.dart';
import '../../support/license_token_fixture.dart';

void main() {
  test(
      'paired parent activates an exhausted room offline; retries are idempotent',
      () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final remote = RemoteBroadcastAccessClient();
    final token = await harness.signer.token();

    expect((await harness.startStream()).status, HttpStatus.paymentRequired);
    expect(await remote.supportsActivation(harness.session), isTrue);
    final activated = await remote.activate(harness.session, token);
    final duplicate = await remote.activate(harness.session, token);

    expect(activated.unlocked, isTrue);
    expect(duplicate.toJson(), activated.toJson());
    expect((await harness.startStream()).status, HttpStatus.ok);
    final status = await harness.request(MiuCamProtocolV2.status);
    expect(status.body['supportsBroadcastLicenseActivation'], isTrue);
    expect(jsonEncode(status.body), isNot(contains(token)));
    expect(harness.gatewayCalls, 0,
        reason:
            'The room never opens its store or calls a verification backend.');
  });

  test('unauthorized, altered and wrong-product tokens cannot unlock',
      () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final token = await harness.signer.token();
    final unauthorized = await harness.activate(token, bearer: 'invalid');
    expect(unauthorized.status, HttpStatus.unauthorized);
    final invalid = await harness.activate('$token.changed');
    expect(invalid.status, HttpStatus.badRequest);
    final wrongProduct = await harness.activate(await harness.signer.token(
      claims: {'productId': 'another.product'},
    ));
    expect(wrongProduct.status, HttpStatus.badRequest);
    expect(wrongProduct.body['code'], 'LICENSE_PRODUCT_MISMATCH');
    expect((await harness.access.snapshot()).isLocked, isTrue);
  });

  test(
      'matching revocation denies media and prevents replay of the older grant',
      () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final active = await harness.signer.token();
    expect((await harness.activate(active)).status, HttpStatus.ok);
    final unrelated =
        await harness.activate(await harness.signer.token(claims: {
      'entitlementId': 'another-household',
      'status': 'revoked',
      'issuedAtMs': 1700000000001,
    }));
    expect(unrelated.status, HttpStatus.conflict);
    expect((await harness.access.snapshot()).unlocked, isTrue);

    final revoked = await harness.signer.token(claims: {
      'status': 'revoked',
      'issuedAtMs': 1700000000001,
    });
    expect((await harness.activate(revoked)).status, HttpStatus.ok);
    expect((await harness.activate(revoked)).status, HttpStatus.ok);
    expect((await harness.startStream()).status, HttpStatus.paymentRequired);
    final replay = await harness.activate(active);
    expect(replay.status, HttpStatus.conflict);
    expect(replay.body['code'], 'LICENSE_GRANT_STALE');
  });

  test('signed revocation also closes an already-running room stream',
      () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    await harness.activate(await harness.signer.token());
    final started = await harness.startStream();
    final request = await harness.client.getUrl(Uri(
      scheme: 'http',
      host: harness.session.host,
      port: harness.session.port,
      path: MiuCamProtocolV2.video,
      queryParameters: {'streamToken': started.body['streamToken'] as String},
    ));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    final ended = Completer<void>();
    response.listen((_) {},
        onDone: () => ended.complete(),
        onError: (Object _) {
          if (!ended.isCompleted) ended.complete();
        });
    expect((await harness.access.snapshot()).active, isTrue);

    await harness.activate(await harness.signer.token(claims: {
      'status': 'revoked',
      'issuedAtMs': 1700000000001,
    }));

    await ended.future.timeout(const Duration(seconds: 2));
    expect((await harness.access.snapshot()).isLocked, isTrue);
  });

  test('unconfigured verification is not advertised and cannot activate',
      () async {
    final harness = await _Harness.start(configured: false);
    addTearDown(harness.close);
    expect(
        await RemoteBroadcastAccessClient().supportsActivation(harness.session),
        isFalse);
    expect((await harness.activate(await harness.signer.token())).status,
        HttpStatus.serviceUnavailable);
    expect((await harness.access.snapshot()).isLocked, isTrue);
  });

  test(
      'trusted family recovery exports only a current active grant without caching',
      () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final remote = RemoteBroadcastAccessClient();
    expect(await remote.readLicense(harness.session), isNull);
    final token = await harness.signer.token();
    await remote.activate(harness.session, token);
    expect(await remote.readLicense(harness.session), token);
    expect(
        (await harness.request(MiuCamProtocolV2.broadcastAccessLicense,
                bearer: 'invalid'))
            .status,
        HttpStatus.unauthorized);
    final request = await harness.client.getUrl(Uri(
      scheme: 'http',
      host: harness.session.host,
      port: harness.session.port,
      path: MiuCamProtocolV2.broadcastAccessLicense,
    ));
    request.headers.set(HttpHeaders.authorizationHeader,
        'Bearer ${harness.session.sessionToken}');
    final response = await request.close();
    expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    await response.drain<void>();

    await harness.activate(await harness.signer.token(claims: {
      'status': 'revoked',
      'issuedAtMs': 1700000000001,
    }));
    expect(await remote.readLicense(harness.session), isNull);
  });

  test(
      'an invited parent can deliver the same signed family grant to another room',
      () async {
    final first = await _Harness.start();
    addTearDown(first.close);
    final remote = RemoteBroadcastAccessClient();
    await remote.activate(first.session, await first.signer.token());
    final recovered = await remote.readLicense(first.session);
    final second = await _Harness.start();
    addTearDown(second.close);
    expect((await second.access.snapshot()).isLocked, isTrue);

    final activated = await remote.activate(second.session, recovered!);

    expect(activated.unlocked, isTrue);
    expect(activated.entitlementId, 'household_test');
    expect(second.gatewayCalls, 0);
  });

  test('activation body is capped at 16 KiB before signature work', () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final response = await harness.activate('a' * (16 * 1024));
    expect(response.status, HttpStatus.requestEntityTooLarge);
    expect(response.body['maxBytes'], 16 * 1024);
    expect((await harness.access.snapshot()).isLocked, isTrue);
  });
}

class _Harness {
  final client = HttpClient();
  final tokens = PairingTokenService();
  late LicenseTokenFixture signer;
  late BroadcastAccessService access;
  late MiuCamServer server;
  late PairingSession session;
  int gatewayCalls = 0;
  var attempt = 0;

  static Future<_Harness> start({bool configured = true}) async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms':
          BroadcastAccessConfig.freeLimit.inMilliseconds,
    });
    final preferences = await SharedPreferences.getInstance();
    final harness = _Harness();
    harness.signer = await LicenseTokenFixture.create();
    harness.access = BroadcastAccessService(preferences,
        purchaseGateway: _NoStoreGateway(() => harness.gatewayCalls++));
    harness.server = MiuCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: harness.tokens,
      httpPort: 0,
      startMediaOnSessionStart: false,
      mediaSource: DeterministicServerMediaSource(),
      broadcastAccess: harness.access,
      licenseGrantVerifier: LicenseGrantVerifier(
        publicKey: configured ? harness.signer.publicKey : const [],
      ),
      onStreamSessionStarted: (_,
          {required video, required audio, required mediaTransport}) async {},
      onStreamSessionStopped: (_) async {},
    );
    final address = Uri.parse(await harness.server.startPairingMode());
    final trusted = harness.tokens
        .issueTrustedClientToken(clientName: 'Parent', deviceId: 'parent');
    harness.session = PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: address.port,
        deviceId: 'room',
        deviceName: 'Room',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {},
      ),
      sessionToken: trusted.token,
    );
    return harness;
  }

  Future<({int status, Map<String, dynamic> body})> activate(String token,
          {String? bearer}) =>
      request(MiuCamProtocolV2.broadcastAccessActivate,
          body: {'licenseToken': token}, bearer: bearer);

  Future<({int status, Map<String, dynamic> body})> startStream() =>
      request(MiuCamProtocolV2.sessionStart, body: {
        MiuCamProtocolV2.streamAttemptId: 'activation-test-${attempt++}',
      });

  Future<({int status, Map<String, dynamic> body})> request(String path,
      {Map<String, Object?>? body, String? bearer}) async {
    final uri =
        Uri(scheme: 'http', host: session.host, port: session.port, path: path);
    final request = await client.openUrl(body == null ? 'GET' : 'POST', uri);
    request.headers.set(HttpHeaders.authorizationHeader,
        'Bearer ${bearer ?? session.sessionToken}');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (
      status: response.statusCode,
      body: text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>
    );
  }

  Future<void> close() async {
    client.close(force: true);
    await server.dispose();
    await access.dispose();
  }
}

class _NoStoreGateway implements BroadcastPurchaseGateway {
  _NoStoreGateway(this.onCall);
  final void Function() onCall;
  @override
  Future<BroadcastPurchaseResult> purchase(
          {required String productId, required String priceLabel}) =>
      restore(productId: productId);
  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async {
    onCall();
    return const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.unavailable);
  }

  @override
  Future<void> dispose() async {}
}
