import 'dart:async';
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

  test('session/start audio talebini runtime callbackine taşır', () async {
    final tokenService = PairingTokenService();
    ({String clientId, bool video, bool audio})? started;
    final server = await _testServer(
      tokenService,
      onStreamSessionStarted: (
        clientId, {
        required bool video,
        required bool audio,
      }) {
        started = (clientId: clientId, video: video, audio: audio);
      },
    );
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
    request.write(jsonEncode({
      'clientId': trusted.clientId,
      'video': true,
      'audio': true,
    }));
    final response = await request.close();
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;

    expect(response.statusCode, HttpStatus.ok);
    expect(body['video'], isTrue);
    expect(body['audio'], isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(started?.clientId, trusted.clientId);
    expect(started?.video, isTrue);
    expect(started?.audio, isTrue);
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

  test('quality/report yeni alanları auth clientId ile işler', () async {
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

    await _postSessionStart(
      client,
      base.port,
      trusted.token,
      trusted.clientId,
    );
    final response = await _postQualityReport(
      client,
      base.port,
      trusted.token,
      {
        'clientId': 'spoofed_client',
        'tier': 'excellent',
        'videoFrameGapMs': 5000,
        'audioUnderrun': true,
        'watchActive': true,
      },
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body['effectiveNetworkTier'], 'critical');
    expect(
      (response.body['mediaProfile'] as Map)['height'],
      360,
    );
    expect((response.body['mediaProfile'] as Map)['audioFirst'], isTrue);
  });

  test('quality/report eski payload kabul eder ve streamToken reddeder',
      () async {
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
    final accepted = await _postQualityReport(
      client,
      base.port,
      trusted.token,
      {'tier': 'weak', 'rttMs': 600},
    );

    expect(accepted.statusCode, HttpStatus.ok);
    expect(accepted.body['effectiveNetworkTier'], 'weak');

    final request = await client.postUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: base.port,
      path: MimiCamProtocolV2.qualityReport,
      queryParameters: {'streamToken': start['streamToken'] as String},
    ));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'tier': 'critical'}));
    final rejected = await request.close();
    await rejected.drain<void>();

    expect(rejected.statusCode, HttpStatus.unauthorized);
  });

  test('quality/report revoked trusted token reddeder', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    tokenService.revokeSession(trusted.token);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final response = await _postQualityReport(
      client,
      base.port,
      trusted.token,
      {'tier': 'weak'},
    );

    expect(response.statusCode, HttpStatus.unauthorized);
  });
}

Future<MimiCamServer> _testServer(
  PairingTokenService tokenService, {
  FutureOr<void> Function(
    String clientId, {
    required bool video,
    required bool audio,
  })? onStreamSessionStarted,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return MimiCamServer(
    config: ConfigurationService(preferences),
    strings: AppStrings(const Locale('tr')),
    onLog: (_) {},
    onAlert: (_) {},
    onStreamSessionStarted: onStreamSessionStarted,
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

Future<({int statusCode, Map<String, Object?> body})> _postQualityReport(
  HttpClient client,
  int port,
  String bearerToken,
  Map<String, Object?> body,
) async {
  final request = await client.postUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: MimiCamProtocolV2.qualityReport,
  ));
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  request.write(jsonEncode(body));
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  final json =
      responseBody.isEmpty ? <String, Object?>{} : jsonDecode(responseBody);
  return (
    statusCode: response.statusCode,
    body: json is Map ? Map<String, Object?>.from(json) : <String, Object?>{},
  );
}
