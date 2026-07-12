import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:mimicam/services/mimicam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('session/start aynı client için idempotent kalır', () async {
    final tokenService = PairingTokenService();
    var runtimeStarts = 0;
    final server = await _testServer(
      tokenService,
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) {
        runtimeStarts++;
        if (runtimeStarts > 1) throw StateError('duplicate media start');
      },
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );

    final first = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId},
    );
    final repaired = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final second = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      repaired.token,
      {'clientId': repaired.clientId},
    );

    expect(first.statusCode, HttpStatus.ok);
    expect(second.statusCode, HttpStatus.ok);
    expect(first.body['activeStreamClients'], 1);
    expect(second.body['activeStreamClients'], 1);
    expect(first.body['streamToken'], isNot(second.body['streamToken']));
    expect(runtimeStarts, 1);
  });

  test('başarısız replacement çalışan aynı-client oturumunu korur', () async {
    final tokenService = PairingTokenService();
    var runtimeStarts = 0;
    final server = await _testServer(
      tokenService,
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) {
        runtimeStarts++;
        if (audio) throw StateError('audio replacement failed');
      },
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );

    final first = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId, 'video': true, 'audio': false},
    );
    final failedReplacement = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId, 'video': true, 'audio': true},
    );
    final recovered = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId, 'video': true, 'audio': false},
    );

    expect(first.statusCode, HttpStatus.ok);
    expect(failedReplacement.statusCode, HttpStatus.internalServerError);
    expect(recovered.statusCode, HttpStatus.ok);
    expect(recovered.body['activeStreamClients'], 1);
    expect(
      tokenService.validateStreamToken(first.body['streamToken']! as String),
      isNotNull,
    );
    expect(runtimeStarts, 2);
  });

  test('quality health ölçümü aynı client için active client sayısını artırmaz',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );

    final start = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId},
    );
    final report = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.qualityReport,
      trusted.token,
      {
        'clientId': trusted.clientId,
        'tier': 'excellent',
        'watchActive': true,
        'videoFrameGapMs': 0,
        'audioGapMs': 0,
      },
    );

    expect(start.statusCode, HttpStatus.ok);
    expect(start.body['activeStreamClients'], 1);
    expect(report.statusCode, HttpStatus.ok);
    expect(report.body['activeStreamClients'], 1);
  });

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

Future<MimiCamServer> _testServer(
  PairingTokenService tokenService, {
  FutureOr<void> Function(
    String clientId, {
    required bool video,
    required bool audio,
    required String mediaTransport,
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
