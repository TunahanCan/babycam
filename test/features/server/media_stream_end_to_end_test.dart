import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/features/client/media/mjpeg_stream_parser.dart';
import 'package:mimicam/features/client/media/wav_pcm_stream_parser.dart';
import 'package:mimicam/features/server/media/server_media_source.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:mimicam/services/mimicam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('streamToken ile gerçek video ve audio endpointleri medya üretir',
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

    final started = await _postSessionStart(
      client,
      base.port,
      trusted.token,
      trusted.clientId,
      audio: true,
    );
    final streamToken = started['streamToken'] as String;

    final videoFrame = await _readFirstMjpegFrame(
      base.port,
      streamToken,
    );
    final audio = await _readFirstPcmChunk(
      base.port,
      streamToken,
    );
    final status = await _getJson(
      client,
      base.port,
      MimiCamProtocolV2.testStatus,
      trusted.token,
    );

    expect(videoFrame.length, greaterThan(100));
    expect(audio.sampleRate, 16000);
    expect(audio.channels, 1);
    expect(audio.pcm16le.length, greaterThan(0));
    expect((status['video'] as Map)['framesStreamed'], greaterThan(0));
    expect((status['audio'] as Map)['chunksStreamed'], greaterThan(0));
  });

  test('media socket reconnect aynı aktif watch slotunu düşürmez', () async {
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

    final started = await _postSessionStart(
      client,
      base.port,
      trusted.token,
      trusted.clientId,
      audio: true,
    );
    final streamToken = started['streamToken'] as String;

    expect(await _readFirstMjpegFrame(base.port, streamToken), isNotEmpty);
    expect(await _readFirstMjpegFrame(base.port, streamToken), isNotEmpty);

    final status = await _getJson(
      client,
      base.port,
      MimiCamProtocolV2.status,
      trusted.token,
    );
    expect(status['activeStreamClients'], 1);
  });

  test('/test/probe loopback video ve audio client tüketimini kanıtlar',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(
      tokenService,
      startMediaOnSessionStart: false,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final response = await _postJson(
      client,
      base.port,
      MimiCamProtocolV2.testProbe,
      trusted.token,
      {
        'startRuntime': true,
        'waitMs': 250,
        'requireVideo': true,
        'requireAudio': true,
        'loopbackMedia': true,
      },
    );
    final checks = response.body['checks'] as Map;
    final loopback = response.body['loopback'] as Map;

    expect(response.statusCode, HttpStatus.ok);
    expect(response.body['ok'], isTrue);
    expect(checks['video'], isTrue);
    expect(checks['audio'], isTrue);
    expect(checks['videoClient'], isTrue);
    expect(checks['audioClient'], isTrue);
    expect(loopback['ok'], isTrue);
    expect(loopback['videoBytes'], greaterThan(0));
    expect(loopback['audioBytes'], greaterThan(0));
  });
}

Future<MimiCamServer> _testServer(
  PairingTokenService tokenService, {
  bool startMediaOnSessionStart = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return MimiCamServer(
    config: ConfigurationService(preferences),
    strings: AppStrings(const Locale('tr')),
    onLog: (_) {},
    onAlert: (_) {},
    tokenService: tokenService,
    httpPort: 0,
    startMediaOnSessionStart: startMediaOnSessionStart,
    mediaSource: DeterministicServerMediaSource(
      videoInterval: const Duration(milliseconds: 25),
      audioInterval: const Duration(milliseconds: 25),
    ),
  );
}

Future<Map<String, Object?>> _postSessionStart(
  HttpClient client,
  int port,
  String bearerToken,
  String clientId, {
  required bool audio,
}) async {
  final response = await _postJson(
    client,
    port,
    MimiCamProtocolV2.sessionStart,
    bearerToken,
    {'clientId': clientId, 'video': true, 'audio': audio},
  );
  expect(response.statusCode, HttpStatus.ok);
  return response.body;
}

Future<Uint8List> _readFirstMjpegFrame(int port, String streamToken) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: MimiCamProtocolV2.video,
      queryParameters: {'streamToken': streamToken},
    ));
    final response = await request.close().timeout(const Duration(seconds: 2));
    expect(response.statusCode, HttpStatus.ok);
    final parser = MjpegStreamParser();
    final completer = Completer<Uint8List>();
    late final StreamSubscription<List<int>> subscription;
    subscription = response.timeout(const Duration(milliseconds: 800)).listen(
      (chunk) {
        if (completer.isCompleted) return;
        final frames = parser.add(Uint8List.fromList(chunk));
        if (frames.isEmpty) return;
        completer.complete(frames.first);
        client.close(force: true);
        unawaited(subscription.cancel());
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('MJPEG stream ended'));
        }
      },
      cancelOnError: true,
    );
    return await completer.future.timeout(const Duration(seconds: 2));
  } finally {
    client.close(force: true);
  }
}

Future<ParsedPcmAudio> _readFirstPcmChunk(
  int port,
  String streamToken,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: MimiCamProtocolV2.audio,
      queryParameters: {'streamToken': streamToken},
    ));
    final response = await request.close().timeout(const Duration(seconds: 2));
    expect(response.statusCode, HttpStatus.ok);
    final parser = WavPcmStreamParser();
    final completer = Completer<ParsedPcmAudio>();
    late final StreamSubscription<List<int>> subscription;
    subscription = response.timeout(const Duration(milliseconds: 800)).listen(
      (chunk) {
        if (completer.isCompleted) return;
        final parsed = parser.add(Uint8List.fromList(chunk));
        if (parsed.pcm16le.isEmpty) return;
        completer.complete(parsed);
        client.close(force: true);
        unawaited(subscription.cancel());
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('WAV stream ended'));
        }
      },
      cancelOnError: true,
    );
    return await completer.future.timeout(const Duration(seconds: 2));
  } finally {
    client.close(force: true);
  }
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
  final json =
      responseBody.isEmpty ? <String, Object?>{} : jsonDecode(responseBody);
  return (
    statusCode: response.statusCode,
    body: json is Map ? Map<String, Object?>.from(json) : <String, Object?>{},
  );
}
