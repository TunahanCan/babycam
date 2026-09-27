import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('public pairing requires room code; QR and remembered access still work',
      () async {
    final tokens = PairingTokenService();
    final server = await _server(tokens);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    expect(base.scheme, 'http');
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final code = tokens.pairingCode!;
    final expiry = tokens.pairingCodeExpiresAtMs;
    final qr = tokens.createPairingNonce();
    final remembered = tokens.issueTrustedClientToken(
      clientName: 'Existing parent',
      deviceId: 'existing',
    );
    final public =
        await _request(client, base.port, MiuCamProtocolV2.statusPublic);
    expect(public.body['transport'], 'http_ws');
    expect(public.body['pairingCodeRequired'], isTrue);
    expect(public.body['pairingCodeExpiresAtMs'], expiry);
    expect(public.body.containsKey('pairingCode'), isFalse);
    for (var index = 0; index < 5; index++) {
      await _request(client, base.port, MiuCamProtocolV2.statusPublic);
    }
    expect(tokens.pairingCode, code);
    expect(tokens.pairingCodeExpiresAtMs, expiry);
    final nonce = public.body['pairingNonce'];
    final missing = await _request(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      body: {'pairingNonce': nonce, 'deviceId': 'new-parent'},
    );
    expect(missing.status, HttpStatus.unauthorized);
    expect(missing.body['code'], 'PAIRING_CODE_INVALID_OR_EXPIRED');
    expect(tokens.isPairingNonceActive(nonce as String), isTrue);
    final wrong = await _request(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      body: {'pairingNonce': nonce, 'pairingCode': 'wrong'},
    );
    expect(wrong.status, HttpStatus.unauthorized);
    expect(wrong.body['code'], 'PAIRING_CODE_INVALID_OR_EXPIRED');
    final paired = await _request(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      body: {
        'pairingNonce': nonce,
        'pairingCode': code,
        'deviceId': 'new-parent',
      },
    );
    expect(paired.status, HttpStatus.ok);
    expect(tokens.isPairingNonceActive(nonce), isFalse);
    expect(tokens.isPairingNonceActive(qr), isTrue);
    final qrPaired = await _request(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      body: {'pairingNonce': qr, 'deviceId': 'qr-parent'},
    );
    expect(qrPaired.status, HttpStatus.ok);
    await server.stopPairingMode();
    expect(tokens.pairingCode, isNull);
    await server.startPairingMode();
    expect(tokens.pairingCode, matches(RegExp(r'^[0-9]{6}$')));
    expect(tokens.validateTrustedClientToken(remembered.token), isNotNull);
    expect(
        tokens.validateTrustedClientToken(
            paired.body['trustedClientToken'] as String),
        isNotNull);
    final status = await _request(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearer: remembered.token,
    );
    expect(status.status, HttpStatus.ok);
  });

  test('five code attempts across source addresses cannot lock out a valid QR',
      () async {
    final tokens = PairingTokenService();
    final server = await _server(tokens);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final qr = tokens.createPairingNonce();
    final publicNonce = tokens.createPublicPairingNonce();
    final clients = [
      for (var index = 2; index < 8; index++)
        HttpClient()
          ..connectionFactory =
              (uri, proxyHost, proxyPort) => Socket.startConnect(
                    uri.host,
                    uri.port,
                    sourceAddress: InternetAddress('127.0.0.$index'),
                  ),
    ];
    addTearDown(() {
      for (final client in clients) {
        client.close(force: true);
      }
    });
    for (var index = 0; index < 5; index++) {
      final rejected = await _request(
        clients[index],
        base.port,
        MiuCamProtocolV2.pairConfirm,
        body: {'pairingNonce': publicNonce},
      );
      expect(rejected.status, HttpStatus.unauthorized);
    }
    for (var index = 0; index < 13; index++) {
      final limited = await _request(
        clients.last,
        base.port,
        MiuCamProtocolV2.pairConfirm,
        body: {
          'pairingNonce': publicNonce,
          'pairingCode': tokens.pairingCode,
        },
      );
      expect(limited.status, HttpStatus.tooManyRequests);
      expect(limited.body['code'], 'PAIR_CONFIRM_RATE_LIMITED');
    }
    final acceptedQr = await _request(
      clients.last,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      body: {'pairingNonce': qr, 'deviceId': 'qr-parent'},
    );
    expect(acceptedQr.status, HttpStatus.ok);
  });

  test(
      'full public source capacity does not block a valid QR from another phone',
      () async {
    final tokens = PairingTokenService(maxPairConfirmSources: 2);
    final server = await _server(tokens);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final nonce = tokens.createPublicPairingNonce();
    final qr = tokens.createPairingNonce();
    final clients = [
      for (var index = 2; index < 5; index++)
        HttpClient()
          ..connectionFactory =
              (uri, proxyHost, proxyPort) => Socket.startConnect(
                    uri.host,
                    uri.port,
                    sourceAddress: InternetAddress('127.0.0.$index'),
                  ),
    ];
    addTearDown(() {
      for (final client in clients) {
        client.close(force: true);
      }
    });
    for (final client in clients.take(2)) {
      final rejected = await _request(
        client,
        base.port,
        MiuCamProtocolV2.pairConfirm,
        body: {'pairingNonce': nonce},
      );
      expect(rejected.status, HttpStatus.unauthorized);
    }
    final accepted = await _request(
      clients.last,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      body: {'pairingNonce': qr, 'deviceId': 'qr-parent'},
    );
    expect(accepted.status, HttpStatus.ok);
  });

  test(
      'expired room code stays expired through public polls until host refresh',
      () async {
    var now = DateTime(2026);
    final tokens = PairingTokenService(
      now: () => now,
      pairingCodeTtl: const Duration(seconds: 1),
    );
    final server = await _server(tokens);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final code = tokens.pairingCode;
    final expiry = tokens.pairingCodeExpiresAtMs;
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    now = now.add(const Duration(seconds: 1));
    final public =
        await _request(client, base.port, MiuCamProtocolV2.statusPublic);
    expect(public.body['pairingCodeExpiresAtMs'], expiry);
    expect(tokens.pairingCode, isNull);
    final expired = await _request(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      body: {
        'pairingNonce': public.body['pairingNonce'],
        'pairingCode': code,
      },
    );
    expect(expired.status, HttpStatus.unauthorized);
    expect(expired.body['code'], 'PAIRING_CODE_INVALID_OR_EXPIRED');
    await server.startPairingMode();
    expect(tokens.pairingCode, isNotNull);
    expect(tokens.pairingCodeExpiresAtMs, greaterThan(expiry!));
    expect(tokens.isPairingNonceActive(public.body['pairingNonce'] as String),
        isFalse);
  });
}

Future<MiuCamServer> _server(PairingTokenService tokens) async {
  SharedPreferences.setMockInitialValues({});
  return MiuCamServer(
    config: ConfigurationService(await SharedPreferences.getInstance()),
    strings: AppStrings(const Locale('en')),
    onLog: (_) {},
    onAlert: (_) {},
    tokenService: tokens,
    httpPort: 0,
    startMediaOnSessionStart: false,
  );
}

Future<({int status, Map<String, Object?> body})> _request(
  HttpClient client,
  int port,
  String path, {
  Map<String, Object?>? body,
  String? bearer,
}) async {
  final request = await client.openUrl(
    body == null ? 'GET' : 'POST',
    Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path),
  );
  if (bearer != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  }
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  return (
    status: response.statusCode,
    body: Map<String, Object?>.from(
      jsonDecode(await utf8.decoder.bind(response).join()) as Map,
    ),
  );
}
