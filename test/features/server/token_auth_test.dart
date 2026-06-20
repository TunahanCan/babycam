import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:mimicam/services/mimicam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('private endpointler Bearer token ister, query main token kabul etmez',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final token = tokenService
        .issueTrustedClientToken(clientName: 'Anne', deviceId: 'anne')
        .token;
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    expect(
      await _getStatusCode(client, base.port, MimiCamProtocolV2.status),
      HttpStatus.unauthorized,
    );
    expect(
      await _getStatusCode(
        client,
        base.port,
        MimiCamProtocolV2.status,
        query: {'token': token},
      ),
      HttpStatus.unauthorized,
    );
    expect(
      await _getStatusCode(client, base.port, MimiCamProtocolV2.video,
          query: {'token': token}),
      HttpStatus.unauthorized,
    );
    expect(
      await _getStatusCode(
        client,
        base.port,
        MimiCamProtocolV2.status,
        bearerToken: token,
      ),
      HttpStatus.ok,
    );
  });

  test('session/start kısa ömürlü streamToken üretir', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final request = await client.postUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: base.port,
      path: MimiCamProtocolV2.sessionStart,
    ));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${trusted.token}');
    request.write(jsonEncode({'clientId': trusted.clientId}));
    final response = await request.close();
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;

    expect(response.statusCode, HttpStatus.ok);
    expect(body['streamToken'], isNotEmpty);
    expect(tokenService.validateStreamToken(body['streamToken'] as String),
        isNotNull);
  });

  test('streamToken private endpointlerde ana token yerine geçmez', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final start = await _postSessionStart(
      client,
      base.port,
      trusted.token,
      trusted.clientId,
    );
    final streamToken = start['streamToken'] as String;

    expect(
      await _getStatusCode(
        client,
        base.port,
        MimiCamProtocolV2.status,
        query: {'streamToken': streamToken},
      ),
      HttpStatus.unauthorized,
    );
    expect(
      await _getStatusCode(
        client,
        base.port,
        MimiCamProtocolV2.status,
        bearerToken: trusted.token,
      ),
      HttpStatus.ok,
    );
  });

  test('expired streamToken video ve audio endpointlerinde reddedilir',
      () async {
    var now = DateTime(2026);
    final tokenService = PairingTokenService(
      now: () => now,
      streamTokenTtl: const Duration(seconds: 1),
    );
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final start = await _postSessionStart(
      client,
      base.port,
      trusted.token,
      trusted.clientId,
    );
    final streamToken = start['streamToken'] as String;
    now = now.add(const Duration(seconds: 2));

    expect(
      await _getStatusCode(
        client,
        base.port,
        MimiCamProtocolV2.video,
        query: {'streamToken': streamToken},
      ),
      HttpStatus.unauthorized,
    );
    expect(
      await _getStatusCode(
        client,
        base.port,
        MimiCamProtocolV2.audio,
        query: {'streamToken': streamToken},
      ),
      HttpStatus.unauthorized,
    );
  });
}

Future<MimiCamServer> _testServer(PairingTokenService tokenService) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return MimiCamServer(
    config: ConfigurationService(preferences),
    strings: AppStrings(const Locale('tr')),
    onLog: (_) {},
    onAlert: (_) {},
    tokenService: tokenService,
    httpPort: 0,
    startMediaOnSessionStart: false,
  );
}

Future<int> _getStatusCode(
  HttpClient client,
  int port,
  String path, {
  String? bearerToken,
  Map<String, String>? query,
}) async {
  final request = await client.getUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
    queryParameters: query,
  ));
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  final response = await request.close();
  await response.drain<void>();
  return response.statusCode;
}

Future<Map<String, Object?>> _postSessionStart(
  HttpClient client,
  int port,
  String bearerToken,
  String clientId,
) async {
  final request = await client.postUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: MimiCamProtocolV2.sessionStart,
  ));
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  request.write(jsonEncode({'clientId': clientId}));
  final response = await request.close();
  final body = jsonDecode(await utf8.decoder.bind(response).join());
  expect(response.statusCode, HttpStatus.ok);
  return Map<String, Object?>.from(body as Map);
}
