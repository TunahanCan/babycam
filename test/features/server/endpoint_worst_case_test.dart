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
  test('state-changing endpointler yanlış HTTP method ile çalışmaz', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final streamToken =
        tokenService.issueStreamToken(clientId: trusted.clientId).token;
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final rejected = <int>[
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.pairConfirm,
        method: 'GET',
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.authRenew,
        method: 'GET',
        bearerToken: trusted.token,
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.sessionStart,
        method: 'GET',
        bearerToken: trusted.token,
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.sessionStop,
        method: 'GET',
        bearerToken: trusted.token,
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.qualityReport,
        method: 'GET',
        bearerToken: trusted.token,
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.statusPublic,
        method: 'POST',
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.status,
        method: 'POST',
        bearerToken: trusted.token,
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.video,
        method: 'POST',
        query: {'streamToken': streamToken},
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.audio,
        method: 'POST',
        query: {'streamToken': streamToken},
      ),
    ];

    expect(rejected, everyElement(HttpStatus.methodNotAllowed));

    final status = await _getJson(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearerToken: trusted.token,
    );
    expect(status['activeStreamClients'], 0);
    expect(status['videoClients'], 0);
    expect(status['audioClients'], 0);
  });

  test('non-upgrade websocket isteği landing page veya stream açmaz', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    expect(
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.events,
        method: 'GET',
      ),
      HttpStatus.upgradeRequired,
    );
    expect(
      await _requestStatusCode(
        client,
        base.port,
        '/ws/stream',
        method: 'GET',
      ),
      HttpStatus.upgradeRequired,
    );
  });

  test(
      'aynı trusted client ikinci event websocket için 429 alır ve slot açılır',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(
      tokenService,
      maxEventSocketsPerClient: 1,
      maxTotalEventSockets: 5,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final socket = await WebSocket.connect(
      Uri(
        scheme: 'ws',
        host: InternetAddress.loopbackIPv4.address,
        port: base.port,
        path: MiuCamProtocolV2.events,
      ).toString(),
      headers: {HttpHeaders.authorizationHeader: 'Bearer ${trusted.token}'},
    );
    addTearDown(socket.close);

    final rejected = await _rawWebSocketHandshake(
      base.port,
      trusted.token,
    );
    expect(rejected.statusCode, HttpStatus.tooManyRequests);
    expect(rejected.body, contains('CLIENT_CONNECTION_LIMIT_REACHED'));

    await socket.close();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    await _waitForEventSocketCount(
      client,
      base.port,
      trusted.token,
      0,
    );
    final replacement = await WebSocket.connect(
      Uri(
        scheme: 'ws',
        host: InternetAddress.loopbackIPv4.address,
        port: base.port,
        path: MiuCamProtocolV2.events,
      ).toString(),
      headers: {HttpHeaders.authorizationHeader: 'Bearer ${trusted.token}'},
    );
    await replacement.close();
  });

  test('toplam event websocket kapasitesi dolunca yeni client 503 alır',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(
      tokenService,
      maxEventSocketsPerClient: 1,
      maxTotalEventSockets: 2,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trustedClients = List.generate(
      3,
      (index) => tokenService.issueTrustedClientToken(
        clientName: 'Parent $index',
        deviceId: 'parent_$index',
      ),
    );
    final sockets = <WebSocket>[];
    for (final trusted in trustedClients.take(2)) {
      sockets.add(await WebSocket.connect(
        Uri(
          scheme: 'ws',
          host: InternetAddress.loopbackIPv4.address,
          port: base.port,
          path: MiuCamProtocolV2.events,
        ).toString(),
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer ${trusted.token}',
        },
      ));
    }
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
    });

    final rejected = await _rawWebSocketHandshake(
      base.port,
      trustedClients[2].token,
    );
    expect(rejected.statusCode, HttpStatus.serviceUnavailable);
    expect(rejected.body, contains('SERVER_CONNECTION_CAPACITY_REACHED'));
  });

  test('malformed ve non-object JSON mutasyon üretmez', () async {
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

    final badPair = await _postRaw(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      '{',
    );
    final listStart = await _postRaw(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      '["not","an","object"]',
      bearerToken: trusted.token,
    );
    final listStop = await _postRaw(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      '["not","an","object"]',
      bearerToken: trusted.token,
    );
    final badQuality = await _postRaw(
      client,
      base.port,
      MiuCamProtocolV2.qualityReport,
      '{"tier"',
      bearerToken: trusted.token,
    );

    expect(badPair, HttpStatus.badRequest);
    expect(listStart, HttpStatus.badRequest);
    expect(listStop, HttpStatus.badRequest);
    expect(badQuality, HttpStatus.badRequest);

    final status = await _getJson(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearerToken: trusted.token,
    );
    expect(status['activeStreamClients'], 0);
    expect(status['qualityReportClients'], 0);
  });

  test('control-plane JSON gövdeleri merkezi byte sınırını aşamaz', () async {
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
    final oversized = jsonEncode({
      'padding': 'x' * MiuCamServer.maxJsonRequestBodyBytes,
    });

    final statuses = [
      await _postRaw(
        client,
        base.port,
        MiuCamProtocolV2.pairConfirm,
        oversized,
      ),
      await _postRaw(
        client,
        base.port,
        MiuCamProtocolV2.sessionStart,
        oversized,
        bearerToken: trusted.token,
      ),
      await _postRaw(
        client,
        base.port,
        MiuCamProtocolV2.qualityReport,
        oversized,
        bearerToken: trusted.token,
      ),
    ];

    expect(statuses, everyElement(HttpStatus.requestEntityTooLarge));
    final status = await _getJson(
      client,
      base.port,
      MiuCamProtocolV2.status,
      bearerToken: trusted.token,
    );
    expect(status['activeStreamClients'], 0);
    expect(status['qualityReportClients'], 0);
  });

  test('pair/confirm nonce replay ve expired nonce kabul etmez', () async {
    var now = DateTime(2026);
    final tokenService = PairingTokenService(
      now: () => now,
      nonceTtl: const Duration(seconds: 1),
      maxTrustedClients: 10,
    );
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final publicStatus = await _getPublicJson(
      client,
      base.port,
      MiuCamProtocolV2.statusPublic,
    );
    final nonce = publicStatus['pairingNonce'] as String;
    final firstPair = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      null,
      {
        'pairingNonce': nonce,
        'clientName': 'Anne',
        'deviceId': 'anne',
      },
    );
    final replayPair = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      null,
      {
        'pairingNonce': nonce,
        'clientName': 'Replay',
        'deviceId': 'replay',
      },
    );

    final nextPublicStatus = await _getPublicJson(
      client,
      base.port,
      MiuCamProtocolV2.statusPublic,
    );
    now = now.add(const Duration(seconds: 2));
    final expiredPair = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      null,
      {
        'pairingNonce': nextPublicStatus['pairingNonce'],
        'clientName': 'Expired',
        'deviceId': 'expired',
      },
    );

    expect(firstPair.statusCode, HttpStatus.ok);
    expect(firstPair.body['trustedClientToken'], isNotEmpty);
    expect(replayPair.statusCode, HttpStatus.unauthorized);
    expect(replayPair.body['code'], 'PAIRING_NONCE_INVALID_OR_EXPIRED');
    expect(expiredPair.statusCode, HttpStatus.unauthorized);
    expect(expiredPair.body['code'], 'PAIRING_NONCE_INVALID_OR_EXPIRED');
    expect(tokenService.pairedClientCount, 1);
  });

  test('bir telefon kendi oda yayınıyla eşleşemez ve QR tüketilmez', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final status = await _getPublicJson(
      client,
      base.port,
      MiuCamProtocolV2.statusPublic,
    );
    final nonce = status['pairingNonce'] as String;

    final rejected = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      null,
      {
        'pairingNonce': nonce,
        'clientName': 'Aynı telefon',
        'deviceId': 'client',
        'originServerDeviceId': 'server_local',
      },
    );
    final validAfterRejection = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.pairConfirm,
      null,
      {
        'pairingNonce': nonce,
        'clientName': 'Diğer telefon',
        'deviceId': 'other-client',
      },
    );

    expect(rejected.statusCode, HttpStatus.conflict);
    expect(rejected.body['code'], 'SELF_PAIRING_NOT_ALLOWED');
    expect(validAfterRejection.statusCode, HttpStatus.ok);
    expect(tokenService.pairedClientCount, 1);
  });

  test(
      'auth/renew eski tokenı düşürür ve yeni token private endpointte çalışır',
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

    expect(
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.status,
        method: 'GET',
        bearerToken: trusted.token,
      ),
      HttpStatus.ok,
    );

    final renewed = await _postWithoutBody(
      client,
      base.port,
      MiuCamProtocolV2.authRenew,
      bearerToken: trusted.token,
    );
    final nextToken = renewed.body['trustedClientToken'] as String;

    expect(renewed.statusCode, HttpStatus.ok);
    expect(nextToken, isNot(trusted.token));
    expect(
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.status,
        method: 'GET',
        bearerToken: trusted.token,
      ),
      HttpStatus.unauthorized,
    );
    expect(
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.status,
        method: 'GET',
        bearerToken: nextToken,
      ),
      HttpStatus.ok,
    );
  });

  test(
      'revoked trusted token stream tokenlarını da medya endpointlerinde düşürür',
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

    final started = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId},
    );
    final streamToken = started.body['streamToken'] as String;
    tokenService.revokeSession(trusted.token);

    expect(
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.status,
        method: 'GET',
        bearerToken: trusted.token,
      ),
      HttpStatus.unauthorized,
    );
    expect(
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.video,
        method: 'GET',
        query: {'streamToken': streamToken},
      ),
      HttpStatus.unauthorized,
    );
    expect(
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.audio,
        method: 'GET',
        query: {'streamToken': streamToken},
      ),
      HttpStatus.unauthorized,
    );
  });

  test('authorization header sadece exact Bearer scheme kabul eder', () async {
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

    final rejected = <int>[
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.status,
        method: 'GET',
        authorizationHeader: 'bearer ${trusted.token}',
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.status,
        method: 'GET',
        authorizationHeader: 'Token ${trusted.token}',
      ),
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.status,
        method: 'GET',
        authorizationHeader: 'Bearer',
      ),
    ];

    expect(rejected, everyElement(HttpStatus.unauthorized));
    expect(
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.status,
        method: 'GET',
        bearerToken: trusted.token,
      ),
      HttpStatus.ok,
    );
  });

  test('session/stop body spoofing başka client oturumunu kapatamaz', () async {
    final tokenService = PairingTokenService(maxTrustedClients: 10);
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final first = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final second = tokenService.issueTrustedClientToken(
      clientName: 'Baba',
      deviceId: 'baba',
    );

    await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      first.token,
      {'clientId': first.clientId},
    );
    await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      second.token,
      {'clientId': second.clientId},
    );

    final spoofedStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      first.token,
      {'clientId': second.clientId},
    );
    expect(spoofedStop.statusCode, HttpStatus.ok);
    expect(spoofedStop.body['activeStreamClients'], 1);

    final secondStillActive = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.qualityReport,
      second.token,
      {
        'clientId': second.clientId,
        'tier': 'critical',
        'watchActive': true,
      },
    );
    expect(secondStillActive.statusCode, HttpStatus.ok);
    expect(secondStillActive.body['activeStreamClients'], 1);

    final secondStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      second.token,
      {'clientId': second.clientId},
    );
    expect(secondStop.statusCode, HttpStatus.ok);
    expect(secondStop.body['activeStreamClients'], 0);
  });

  test('aktif limit doluyken streamToken ile medya attach 429 döner', () async {
    final tokenService = PairingTokenService(maxTrustedClients: 10);
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    for (var index = 0; index < 5; index++) {
      final trusted = tokenService.issueTrustedClientToken(
        clientName: 'Client $index',
        deviceId: 'client_$index',
      );
      final started = await _postJson(
        client,
        base.port,
        MiuCamProtocolV2.sessionStart,
        trusted.token,
        {'clientId': trusted.clientId},
      );
      expect(started.statusCode, HttpStatus.ok);
    }

    final overflowStreamToken =
        tokenService.issueStreamToken(clientId: 'overflow_client').token;

    expect(
      await _requestStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.video,
        method: 'GET',
        query: {'streamToken': overflowStreamToken},
      ),
      HttpStatus.tooManyRequests,
    );
  });
}

Future<MiuCamServer> _testServer(
  PairingTokenService tokenService, {
  int maxEventSocketsPerClient = 1,
  int? maxTotalEventSockets,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return MiuCamServer(
    config: ConfigurationService(preferences),
    strings: AppStrings(const Locale('tr')),
    onLog: (_) {},
    onAlert: (_) {},
    tokenService: tokenService,
    httpPort: 0,
    startMediaOnSessionStart: false,
    maxEventSocketsPerClient: maxEventSocketsPerClient,
    maxTotalEventSockets: maxTotalEventSockets,
  );
}

Future<({int statusCode, String body})> _rawWebSocketHandshake(
  int port,
  String bearerToken,
) async {
  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    port,
    timeout: const Duration(seconds: 2),
  );
  try {
    socket.write(
      'GET ${MiuCamProtocolV2.events} HTTP/1.1\r\n'
      'Host: 127.0.0.1:$port\r\n'
      'Connection: Upgrade\r\n'
      'Upgrade: websocket\r\n'
      'Sec-WebSocket-Version: 13\r\n'
      'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
      'Authorization: Bearer $bearerToken\r\n'
      '\r\n',
    );
    await socket.flush();
    final response = await utf8.decoder
        .bind(socket)
        .join()
        .timeout(const Duration(seconds: 2));
    final firstLine = const LineSplitter().convert(response).first;
    return (
      statusCode: int.parse(firstLine.split(' ')[1]),
      body: response,
    );
  } finally {
    await socket.close();
  }
}

Future<void> _waitForEventSocketCount(
  HttpClient client,
  int port,
  String bearerToken,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final status = await _getJson(
      client,
      port,
      MiuCamProtocolV2.status,
      bearerToken: bearerToken,
    );
    if (status['eventSocketConnections'] == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('Event socket count did not become $expected.');
}

Future<int> _requestStatusCode(
  HttpClient client,
  int port,
  String path, {
  required String method,
  String? bearerToken,
  String? authorizationHeader,
  Map<String, String>? query,
}) async {
  final request = await client.openUrl(
    method,
    Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: path,
      queryParameters: query,
    ),
  );
  if (authorizationHeader != null) {
    request.headers.set(HttpHeaders.authorizationHeader, authorizationHeader);
  } else if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  final response = await request.close();
  await response.drain<void>();
  return response.statusCode;
}

Future<int> _postRaw(
  HttpClient client,
  int port,
  String path,
  String body, {
  String? bearerToken,
}) async {
  final request = await client.postUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  request.headers.contentType = ContentType.json;
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  request.write(body);
  final response = await request.close();
  await response.drain<void>();
  return response.statusCode;
}

Future<({int statusCode, Map<String, Object?> body})> _postJson(
  HttpClient client,
  int port,
  String path,
  String? token,
  Map<String, Object?> body,
) async {
  final request = await client.postUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  request.headers.contentType = ContentType.json;
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
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

Future<({int statusCode, Map<String, Object?> body})> _postWithoutBody(
  HttpClient client,
  int port,
  String path, {
  required String bearerToken,
}) async {
  final request = await client.postUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  final json =
      responseBody.isEmpty ? <String, Object?>{} : jsonDecode(responseBody);
  return (
    statusCode: response.statusCode,
    body: json is Map ? Map<String, Object?>.from(json) : <String, Object?>{},
  );
}

Future<Map<String, Object?>> _getPublicJson(
  HttpClient client,
  int port,
  String path,
) async {
  final request = await client.getUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  expect(response.statusCode, HttpStatus.ok);
  final json = jsonDecode(body);
  return Map<String, Object?>.from(json as Map);
}

Future<Map<String, Object?>> _getJson(
  HttpClient client,
  int port,
  String path, {
  required String bearerToken,
}) async {
  final request = await client.getUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  expect(response.statusCode, HttpStatus.ok);
  final json = jsonDecode(body);
  return Map<String, Object?>.from(json as Map);
}
