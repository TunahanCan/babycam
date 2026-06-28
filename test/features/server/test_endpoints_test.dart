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
  test('/test/status Bearer token ister ve runtime diagnostigi dondurur',
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
      await _statusCode(client, base.port, MimiCamProtocolV2.testStatus),
      HttpStatus.unauthorized,
    );

    final status = await _getJson(
      client,
      base.port,
      MimiCamProtocolV2.testStatus,
      trusted.token,
    );

    expect(status['ok'], isTrue);
    expect(status['runtime'], isA<Map>());
    expect(status['video'], isA<Map>());
    expect(status['audio'], isA<Map>());
    expect(status['events'], isA<Map>());
  });

  test('/test/alert websocket event kanalina sentetik bildirim yollar',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
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
        path: MimiCamProtocolV2.events,
      ).toString(),
      headers: {HttpHeaders.authorizationHeader: 'Bearer ${trusted.token}'},
    );
    addTearDown(() => socket.close());
    final firstMessage = socket.first.timeout(const Duration(seconds: 2));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final response = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.testAlert,
      trusted.token,
      {'message': 'MimiCam test bildirimi'},
    );
    final message = await firstMessage;
    final decoded = jsonDecode(message as String) as Map;

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body['ok'], isTrue);
    expect(response.body['deliveredWebSocketClients'], 1);
    expect(decoded['message'], 'MimiCam test bildirimi');
    expect(decoded['messageKey'], 'legacyAlert');
  });

  test('/test/probe start etmeden sentetik event kontrolu yapabilir', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
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
        path: MimiCamProtocolV2.events,
      ).toString(),
      headers: {HttpHeaders.authorizationHeader: 'Bearer ${trusted.token}'},
    );
    addTearDown(() => socket.close());
    final firstMessage = socket.first.timeout(const Duration(seconds: 2));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final response = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.testProbe,
      trusted.token,
      {
        'startRuntime': false,
        'waitMs': 0,
        'requireVideo': false,
        'requireAudio': false,
        'requireEvents': true,
        'requireEventDelivery': true,
        'emitAlert': true,
      },
    );
    final message = await firstMessage;

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body['ok'], isTrue);
    expect(response.body['checks'], {
      'video': true,
      'audio': true,
      'events': true,
      'eventDelivery': true,
    });
    expect(jsonDecode(message as String), isA<Map>());
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

Future<int> _statusCode(
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
  await response.drain<void>();
  return response.statusCode;
}

Future<Map<String, Object?>> _getJson(
  HttpClient client,
  int port,
  String path,
  String bearerToken,
) async {
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
  return Map<String, Object?>.from(jsonDecode(body) as Map);
}

Future<({int statusCode, Map<String, Object?> body})> _postJson(
  HttpClient client,
  int port,
  String path,
  String bearerToken,
  Map<String, Object?> body,
) async {
  final request = await client.postUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  request.write(jsonEncode(body));
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  return (
    statusCode: response.statusCode,
    body: Map<String, Object?>.from(jsonDecode(responseBody) as Map),
  );
}
