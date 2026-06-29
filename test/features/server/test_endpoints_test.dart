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
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('/test tarayici test panelini dondurur', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final html = await _getText(
      client,
      base.port,
      MimiCamProtocolV2.testDashboard,
    );

    expect(html, contains('MimiCam Test'));
    expect(html, contains('Tam sağlık testi'));
    expect(html, contains('/test/dashboard.js'));
  });

  test('/test/dashboard.js tarayici test algoritmalarini dondurur', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final script = await _getText(
      client,
      base.port,
      MimiCamProtocolV2.testDashboardScript,
    );

    expect(script, contains('/session/start'));
    expect(script, contains('/test/audio-tone'));
    expect(script, contains('/ws/events?token='));
    expect(script, contains('measureVideoStream'));
    expect(script, contains('/test/reset'));
    expect(script, contains('/quality/report'));
  });

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

  test('/test browser websocket query token ile sentetik bildirimi alir',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Tarayici',
      deviceId: 'browser',
    );
    final socket = await WebSocket.connect(
      Uri(
        scheme: 'ws',
        host: InternetAddress.loopbackIPv4.address,
        port: base.port,
        path: MimiCamProtocolV2.events,
        queryParameters: {'token': trusted.token},
      ).toString(),
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
      {'message': 'Browser event testi'},
    );
    final message = await firstMessage;

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body['deliveredWebSocketClients'], 1);
    expect((jsonDecode(message as String) as Map)['message'],
        'Browser event testi');
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

  test('/test/reset Bearer token ile test runtime temizligi dondurur',
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
      await _postStatusCode(client, base.port, MimiCamProtocolV2.testReset),
      HttpStatus.unauthorized,
    );

    final response = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.testReset,
      trusted.token,
      {},
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body['ok'], isTrue);
    expect(response.body['diagnostics'], isA<Map>());
  });

  test('/test/audio-tone Bearer token ile deterministik WAV tonu dondurur',
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
      await _statusCode(client, base.port, MimiCamProtocolV2.testAudioTone),
      HttpStatus.unauthorized,
    );

    final bytes = await _getBytes(
      client,
      base.port,
      MimiCamProtocolV2.testAudioTone,
      trusted.token,
      query: {
        'durationMs': '200',
        'frequencyHz': '1000',
        'amplitude': '0.25',
      },
    );

    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    final dataSize =
        ByteData.sublistView(bytes, 40, 44).getUint32(0, Endian.little);
    expect(dataSize, 16000 * 200 ~/ 1000 * 2);
    expect(bytes.length, 44 + dataSize);
    expect(_pcmPeak(bytes.sublist(44)), greaterThan(1000));
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

Future<int> _postStatusCode(
  HttpClient client,
  int port,
  String path,
) async {
  final request = await client.postUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  request.headers.contentType = ContentType.json;
  request.write('{}');
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

Future<String> _getText(
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
  return body;
}

Future<Uint8List> _getBytes(
  HttpClient client,
  int port,
  String path,
  String bearerToken, {
  Map<String, String>? query,
}) async {
  final request = await client.getUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
    queryParameters: query,
  ));
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  final response = await request.close();
  final chunks = await response.fold<List<int>>(
    <int>[],
    (buffer, chunk) => buffer..addAll(chunk),
  );
  expect(response.statusCode, HttpStatus.ok);
  return Uint8List.fromList(chunks);
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

int _pcmPeak(Uint8List pcm16le) {
  final view = ByteData.sublistView(pcm16le);
  var peak = 0;
  for (var i = 0; i < pcm16le.length ~/ 2; i++) {
    final sample = view.getInt16(i * 2, Endian.little).abs();
    if (sample > peak) peak = sample;
  }
  return peak;
}
