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
  test('five remembered phones survive restart, re-pair with proof and remove',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = SharedPreferencesTrustedClientRepository(preferences);
    var now = DateTime(2026, 9, 5);
    final firstTokens = PairingTokenService(
      now: () => now,
      trustedClientRepository: repository,
    );
    final firstServer = _server(firstTokens, preferences);
    addTearDown(firstServer.dispose);
    final firstBase = Uri.parse(await firstServer.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final paired = <Map<String, Object?>>[];
    for (var index = 0; index < 5; index++) {
      final response = await _pair(client, firstBase.port, 'parent-$index');
      expect(response.statusCode, HttpStatus.ok);
      paired.add(response.body);
    }
    expect(firstServer.trustedClients, hasLength(5));
    final firstId = paired.first['clientId']! as String;
    final firstSecret = paired.first['trustedClientToken']! as String;
    final pairedAt = firstTokens.recordForClient(firstId)!.createdAtMs;
    await firstServer.renameTrustedClient(firstId, 'Annenin telefonu');
    await firstServer.dispose();

    now = now.add(const Duration(days: 3));
    final restartedTokens = PairingTokenService(
      now: () => now,
      trustedClientRepository:
          SharedPreferencesTrustedClientRepository(preferences),
    );
    final restartedServer = _server(restartedTokens, preferences);
    addTearDown(restartedServer.dispose);
    final base = Uri.parse(await restartedServer.startPairingMode());
    expect(restartedServer.trustedClients, hasLength(5));
    await restartedServer.stopPairingMode();

    final publicStatus = await _jsonRequest(
        client, base.port, 'GET', MiuCamProtocolV2.statusPublic);
    expect(publicStatus.statusCode, HttpStatus.notFound);
    final resumed = await _start(client, base.port, firstId, firstSecret);
    expect(resumed.statusCode, HttpStatus.ok);
    expect(resumed.body['activeStreamClients'], 1);
    expect(restartedServer.activeWatchClientIds, {firstId});

    await restartedServer.startPairingMode();
    final sixth = await _pair(client, base.port, 'parent-6');
    expect(sixth.statusCode, HttpStatus.conflict);
    expect(sixth.body['code'], TrustedClientLimitException.code);
    final unprovenCollision = await _pair(client, base.port, firstId);
    expect(unprovenCollision.statusCode, HttpStatus.conflict);
    expect(unprovenCollision.body['code'], TrustedClientLimitException.code);
    expect(restartedTokens.validateSessionToken(firstSecret), isTrue);

    final rePaired = await _pair(
      client,
      base.port,
      firstId,
      proof: firstSecret,
    );
    expect(rePaired.statusCode, HttpStatus.ok);
    expect(rePaired.body['clientId'], firstId);
    expect(rePaired.body['serverDeviceId'], paired.first['serverDeviceId']);
    expect(restartedTokens.pairedClientCount, 5);
    expect(restartedTokens.recordForClient(firstId)?.createdAtMs, pairedAt);
    expect(restartedTokens.recordForClient(firstId)?.clientName,
        'Annenin telefonu');
    final replacementSecret = rePaired.body['trustedClientToken']! as String;
    expect(replacementSecret, isNot(firstSecret));
    final superseded = await _start(client, base.port, firstId, firstSecret);
    expect(superseded.statusCode, HttpStatus.unauthorized);
    final resumedAgain =
        await _start(client, base.port, firstId, replacementSecret);
    expect(resumedAgain.statusCode, HttpStatus.ok);
    expect(resumedAgain.body['activeStreamClients'], 1);

    await restartedServer.revokeTrustedClient(firstId);
    expect(restartedTokens.pairedClientCount, 4);
    expect(restartedServer.activeWatchClientIds, isEmpty);
    final removed = await _start(client, base.port, firstId, replacementSecret);
    expect(removed.statusCode, HttpStatus.unauthorized);
    final streamToken = resumedAgain.body['streamToken']! as String;
    final mediaRequest = await client.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: base.port,
      path: MiuCamProtocolV2.video,
      queryParameters: {'streamToken': streamToken},
    ));
    final mediaResponse = await mediaRequest.close();
    await mediaResponse.drain<void>();
    expect(mediaResponse.statusCode, HttpStatus.unauthorized);
    final newPhone = await _pair(client, base.port, 'parent-6');
    expect(newPhone.statusCode, HttpStatus.ok);
    expect(restartedTokens.pairedClientCount, 5);
    final stored = PairingTokenService(
      now: () => now,
      trustedClientRepository: repository,
    );
    expect(stored.validateSessionToken(replacementSecret), isFalse);
    expect(
        stored.validateSessionToken(
            newPhone.body['trustedClientToken']! as String),
        isTrue);
  });
}

MiuCamServer _server(
  PairingTokenService tokenService,
  SharedPreferences preferences,
) =>
    MiuCamServer(
      config: ConfigurationService(preferences),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokenService,
      httpPort: 0,
      startMediaOnSessionStart: false,
    );

Future<({int statusCode, Map<String, Object?> body})> _pair(
  HttpClient client,
  int port,
  String deviceId, {
  String? proof,
}) async {
  final status =
      await _jsonRequest(client, port, 'GET', MiuCamProtocolV2.statusPublic);
  expect(status.statusCode, HttpStatus.ok);
  return _jsonRequest(client, port, 'POST', MiuCamProtocolV2.pairConfirm,
      body: {
        'pairingNonce': status.body['pairingNonce'],
        'clientName': 'MiuCam phone',
        'deviceId': deviceId,
        if (proof != null) 'existingTrustedClientToken': proof,
      });
}

Future<({int statusCode, Map<String, Object?> body})> _start(
  HttpClient client,
  int port,
  String clientId,
  String token,
) =>
    _jsonRequest(client, port, 'POST', MiuCamProtocolV2.sessionStart,
        token: token,
        body: {
          'clientId': clientId,
          MiuCamProtocolV2.streamAttemptId: 'pairing-lifecycle-attempt',
        });

Future<({int statusCode, Map<String, Object?> body})> _jsonRequest(
  HttpClient client,
  int port,
  String method,
  String path, {
  String? token,
  Map<String, Object?>? body,
}) async {
  final request = await client.openUrl(
      method,
      Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        path: path,
      ));
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  final decoded = text.isEmpty ? null : jsonDecode(text);
  return (
    statusCode: response.statusCode,
    body: decoded is Map
        ? Map<String, Object?>.from(decoded)
        : <String, Object?>{},
  );
}
