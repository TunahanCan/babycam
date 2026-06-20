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
  test('6. aktif izleyici 429 MAX_ACTIVE_CLIENTS_REACHED alır', () async {
    final tokenService = PairingTokenService(maxTrustedClients: 10);
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    for (var index = 0; index < 5; index++) {
      final token = tokenService.issueTrustedClientToken(
        clientName: 'Client $index',
        deviceId: 'client_$index',
      );
      final response = await _postJson(
        client,
        base.port,
        MimiCamProtocolV2.sessionStart,
        token.token,
        {'clientId': token.clientId},
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(response.body['streamToken'], isNotEmpty);
    }

    final sixth = tokenService.issueTrustedClientToken(
      clientName: 'Client 6',
      deviceId: 'client_6',
    );
    final rejected = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      sixth.token,
      {'clientId': sixth.clientId},
    );

    expect(rejected.statusCode, HttpStatus.tooManyRequests);
    expect(rejected.body['code'], 'MAX_ACTIVE_CLIENTS_REACHED');

    final stop = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStop,
      tokenService.recordForClient('client_0') == null
          ? ''
          : tokenService
              .issueTrustedClientToken(
                clientName: 'Client 0',
                deviceId: 'client_0',
              )
              .token,
      {'clientId': 'client_0'},
    );
    expect(stop.statusCode, HttpStatus.ok);

    final acceptedAfterStop = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      sixth.token,
      {'clientId': sixth.clientId},
    );
    expect(acceptedAfterStop.statusCode, HttpStatus.ok);
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

Future<({int statusCode, Map<String, Object?> body})> _postJson(
  HttpClient client,
  int port,
  String path,
  String token,
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
    ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
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
