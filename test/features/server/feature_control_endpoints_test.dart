import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:mimicam/services/mimicam_server.dart';
import 'package:mimicam/services/monetization/broadcast_access_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('feature control endpointleri Bearer ister ve streamToken reddeder',
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

    final start = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      {'clientId': trusted.clientId},
      bearerToken: trusted.token,
    );
    final streamToken = start.body['streamToken'] as String;

    expect(
      await _getStatusCode(
        client,
        base.port,
        MimiCamProtocolV2.comfortState,
      ),
      HttpStatus.unauthorized,
    );
    expect(
      (await _postJson(
        client,
        base.port,
        MimiCamProtocolV2.comfortCommand,
        {'action': 'play'},
        query: {'streamToken': streamToken},
      ))
          .statusCode,
      HttpStatus.unauthorized,
    );
    expect(
      await _getStatusCode(
        client,
        base.port,
        MimiCamProtocolV2.comfortState,
        bearerToken: trusted.token,
      ),
      HttpStatus.ok,
    );
  });

  test('comfort ve night light state reducer endpointleri calisir', () async {
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

    final comfort = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.comfortCommand,
      {'action': 'play', 'trackId': 'rain', 'volume': 0.7},
      bearerToken: trusted.token,
    );
    final nightLight = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.nightLightCommand,
      {'action': 'on', 'mode': 'screenGlow', 'brightness': 0.4},
      bearerToken: trusted.token,
    );

    expect(comfort.statusCode, HttpStatus.ok);
    expect((comfort.body['state'] as Map)['playing'], isTrue);
    expect((comfort.body['state'] as Map)['trackId'], 'rain');
    expect(nightLight.statusCode, HttpStatus.ok);
    expect((nightLight.body['state'] as Map)['enabled'], isTrue);
    expect((nightLight.body['state'] as Map)['mode'], 'screenGlow');
  });

  test('talk session tek aktif konusmaci tutar ve talk token ister', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final anne = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final baba = tokenService.issueTrustedClientToken(
      clientName: 'Baba',
      deviceId: 'baba',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final start = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.talkStart,
      const {},
      bearerToken: anne.token,
    );
    final busy = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.talkStart,
      const {},
      bearerToken: baba.token,
    );
    final talkToken =
        ((start.body['session'] as Map)['talkToken'] as String?) ?? '';

    final rejected = await _postBytes(
      client,
      base.port,
      MimiCamProtocolV2.talkAudio,
      Uint8List.fromList([1, 2, 3]),
      query: {'streamToken': 'not-a-talk-token'},
    );
    final accepted = await _postBytes(
      client,
      base.port,
      MimiCamProtocolV2.talkAudio,
      Uint8List.fromList([1, 2, 3, 4]),
      query: {'talkToken': talkToken},
    );
    final stop = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.talkStop,
      {'talkToken': talkToken},
      bearerToken: anne.token,
    );

    expect(start.statusCode, HttpStatus.ok);
    expect(talkToken, isNotEmpty);
    expect(busy.statusCode, HttpStatus.conflict);
    expect(rejected.statusCode, HttpStatus.unauthorized);
    expect(accepted.statusCode, HttpStatus.ok);
    expect(accepted.body['audioBytesReceived'], 4);
    expect(stop.body['ok'], isTrue);
  });

  test('ücretsiz yayın süresi dolduğunda session start 402 döner', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(
      tokenService,
      initialPreferences: {
        'broadcast_access.used_ms': const Duration(hours: 2).inMilliseconds,
      },
      enableBroadcastAccess: true,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final start = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      {'clientId': trusted.clientId},
      bearerToken: trusted.token,
    );

    expect(start.statusCode, HttpStatus.paymentRequired);
    expect(start.body['code'], 'BROADCAST_ACCESS_LOCKED');
    expect(start.body.containsKey('streamToken'), isFalse);
    expect((start.body['broadcastAccess'] as Map)['locked'], isTrue);
  });
}

Future<MimiCamServer> _testServer(
  PairingTokenService tokenService, {
  Map<String, Object> initialPreferences = const {},
  bool enableBroadcastAccess = false,
}) async {
  SharedPreferences.setMockInitialValues(initialPreferences);
  final preferences = await SharedPreferences.getInstance();
  return MimiCamServer(
    config: ConfigurationService(preferences),
    strings: AppStrings(const Locale('tr')),
    onLog: (_) {},
    onAlert: (_) {},
    tokenService: tokenService,
    httpPort: 0,
    startMediaOnSessionStart: false,
    broadcastAccess: enableBroadcastAccess
        ? BroadcastAccessService(
            preferences,
            purchaseGateway: _FakePurchaseGateway(),
          )
        : null,
  );
}

class _FakePurchaseGateway implements BroadcastPurchaseGateway {
  @override
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  }) async =>
      const BroadcastPurchaseResult(status: BroadcastPurchaseStatus.purchased);

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async =>
      const BroadcastPurchaseResult(status: BroadcastPurchaseStatus.restored);

  @override
  Future<void> dispose() async {}
}

Future<int> _getStatusCode(
  HttpClient client,
  int port,
  String path, {
  String? bearerToken,
}) async {
  final request = await client.getUrl(_uri(port, path));
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  final response = await request.close();
  await response.drain<void>();
  return response.statusCode;
}

Future<({int statusCode, Map<String, Object?> body})> _postJson(
  HttpClient client,
  int port,
  String path,
  Map<String, Object?> body, {
  String? bearerToken,
  Map<String, String>? query,
}) async {
  final request = await client.postUrl(_uri(port, path, query: query));
  request.headers.contentType = ContentType.json;
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
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

Future<({int statusCode, Map<String, Object?> body})> _postBytes(
  HttpClient client,
  int port,
  String path,
  Uint8List bytes, {
  Map<String, String>? query,
}) async {
  final request = await client.postUrl(_uri(port, path, query: query));
  request.add(bytes);
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  final json =
      responseBody.isEmpty ? <String, Object?>{} : jsonDecode(responseBody);
  return (
    statusCode: response.statusCode,
    body: json is Map ? Map<String, Object?>.from(json) : <String, Object?>{},
  );
}

Uri _uri(int port, String path, {Map<String, String>? query}) => Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: path,
      queryParameters: query,
    );
