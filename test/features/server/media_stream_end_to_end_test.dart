import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/features/client/media/mjpeg_stream_parser.dart';
import 'package:miucam/features/client/media/wav_pcm_stream_parser.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/deterministic_server_media_source.dart';

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
      MiuCamProtocolV2.status,
      trusted.token,
    );

    expect(videoFrame.length, greaterThan(100));
    expect(audio.sampleRate, 16000);
    expect(audio.channels, 1);
    expect(audio.pcm16le.length, greaterThan(0));
    expect(status['activeStreamClients'], 1);
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
      MiuCamProtocolV2.status,
      trusted.token,
    );
    expect(status['activeStreamClients'], 1);
  });

  test('aynı token video ve audio dışında üçüncü media socket açamaz',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(
      tokenService,
      maxMediaConnectionsPerClient: 2,
      maxTotalMediaConnections: 10,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final controlClient = HttpClient();
    addTearDown(() => controlClient.close(force: true));
    final started = await _postSessionStart(
      controlClient,
      base.port,
      trusted.token,
      trusted.clientId,
      audio: true,
    );
    final streamToken = started['streamToken'] as String;

    final video = await _openMediaStream(
      base.port,
      MiuCamProtocolV2.video,
      streamToken,
    );
    final audio = await _openMediaStream(
      base.port,
      MiuCamProtocolV2.audio,
      streamToken,
    );
    addTearDown(video.close);
    addTearDown(audio.close);

    final rejected = await _requestRejectedMediaStream(
      base.port,
      MiuCamProtocolV2.video,
      streamToken,
    );
    expect(rejected.statusCode, HttpStatus.tooManyRequests);
    expect(rejected.body['code'], 'CLIENT_CONNECTION_LIMIT_REACHED');
    expect(rejected.retryAfter, '1');
    final status = await _getJson(
      controlClient,
      base.port,
      MiuCamProtocolV2.status,
      trusted.token,
    );
    expect(status['mediaConnections'], 2);
    expect(status['videoClients'], 1);
    expect(status['audioClients'], 1);
  });

  test('toplam media socket kapasitesi dolunca yeni client 503 alır', () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(
      tokenService,
      maxMediaConnectionsPerClient: 2,
      maxTotalMediaConnections: 2,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final controlClient = HttpClient();
    addTearDown(() => controlClient.close(force: true));
    final trustedClients = List.generate(
      3,
      (index) => tokenService.issueTrustedClientToken(
        clientName: 'Parent $index',
        deviceId: 'parent_$index',
      ),
    );
    final streamTokens = <String>[];
    for (final trusted in trustedClients) {
      final started = await _postSessionStart(
        controlClient,
        base.port,
        trusted.token,
        trusted.clientId,
        audio: false,
      );
      streamTokens.add(started['streamToken'] as String);
    }

    final first = await _openMediaStream(
      base.port,
      MiuCamProtocolV2.video,
      streamTokens[0],
    );
    final second = await _openMediaStream(
      base.port,
      MiuCamProtocolV2.video,
      streamTokens[1],
    );
    addTearDown(first.close);
    addTearDown(second.close);

    final rejected = await _requestRejectedMediaStream(
      base.port,
      MiuCamProtocolV2.video,
      streamTokens[2],
    );
    expect(rejected.statusCode, HttpStatus.serviceUnavailable);
    expect(rejected.body['code'], 'SERVER_CONNECTION_CAPACITY_REACHED');
    expect(rejected.body['channel'], 'media');
  });

  test('session/stop client medya socketlerini kapatip runtimei bosaltir',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final controlClient = HttpClient();
    final mediaClient = HttpClient();
    addTearDown(() => controlClient.close(force: true));
    addTearDown(() => mediaClient.close(force: true));

    final started = await _postSessionStart(
      controlClient,
      base.port,
      trusted.token,
      trusted.clientId,
      audio: false,
    );
    final streamToken = started['streamToken'] as String;
    final mediaRequest = await mediaClient.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: base.port,
      path: MiuCamProtocolV2.video,
      queryParameters: {'streamToken': streamToken},
    ));
    final mediaResponse = await mediaRequest.close();
    final firstFrame = Completer<void>();
    final streamClosed = Completer<void>();
    final parser = MjpegStreamParser();
    final subscription = mediaResponse.listen(
      (chunk) {
        if (firstFrame.isCompleted) return;
        if (parser.add(Uint8List.fromList(chunk)).isNotEmpty) {
          firstFrame.complete();
        }
      },
      onError: (Object _) {
        if (!streamClosed.isCompleted) streamClosed.complete();
      },
      onDone: () {
        if (!streamClosed.isCompleted) streamClosed.complete();
      },
      cancelOnError: true,
    );
    addTearDown(subscription.cancel);
    await firstFrame.future.timeout(const Duration(seconds: 2));

    final stopped = await _postJson(
      controlClient,
      base.port,
      MiuCamProtocolV2.sessionStop,
      trusted.token,
      {'clientId': trusted.clientId},
    );
    await streamClosed.future.timeout(const Duration(seconds: 2));
    final status = await _getJson(
      controlClient,
      base.port,
      MiuCamProtocolV2.status,
      trusted.token,
    );

    expect(stopped.statusCode, HttpStatus.ok);
    expect(stopped.body['activeStreamClients'], 0);
    expect(status['activeStreamClients'], 0);
    expect(status['videoClients'], 0);
  });

  test('iki parent client ayni anda video ve audio endpointlerinden medya alir',
      () async {
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

    final starts = await Future.wait([
      _postSessionStart(
        client,
        base.port,
        anne.token,
        anne.clientId,
        audio: true,
      ),
      _postSessionStart(
        client,
        base.port,
        baba.token,
        baba.clientId,
        audio: true,
      ),
    ]);
    final anneStreamToken = starts[0]['streamToken'] as String;
    final babaStreamToken = starts[1]['streamToken'] as String;

    final media = await Future.wait<Object>([
      _readFirstMjpegFrame(base.port, anneStreamToken),
      _readFirstMjpegFrame(base.port, babaStreamToken),
      _readFirstPcmChunk(base.port, anneStreamToken),
      _readFirstPcmChunk(base.port, babaStreamToken),
    ]);
    final status = await _getJson(
      client,
      base.port,
      MiuCamProtocolV2.status,
      anne.token,
    );

    expect((media[0] as Uint8List).length, greaterThan(100));
    expect((media[1] as Uint8List).length, greaterThan(100));
    expect((media[2] as ParsedPcmAudio).pcm16le.length, greaterThan(0));
    expect((media[3] as ParsedPcmAudio).pcm16le.length, greaterThan(0));
    expect(status['activeStreamClients'], 2);
  });
}

Future<MiuCamServer> _testServer(
  PairingTokenService tokenService, {
  bool startMediaOnSessionStart = true,
  int maxMediaConnectionsPerClient = 2,
  int? maxTotalMediaConnections,
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
    startMediaOnSessionStart: startMediaOnSessionStart,
    maxMediaConnectionsPerClient: maxMediaConnectionsPerClient,
    maxTotalMediaConnections: maxTotalMediaConnections,
    mediaSource: DeterministicServerMediaSource(
      videoInterval: const Duration(milliseconds: 25),
      audioInterval: const Duration(milliseconds: 25),
    ),
  );
}

class _OpenMediaStream {
  _OpenMediaStream(this._socket, this._subscription);

  final Socket _socket;
  final StreamSubscription<List<int>> _subscription;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    await _subscription.cancel();
  }
}

Future<_OpenMediaStream> _openMediaStream(
  int port,
  String path,
  String streamToken,
) async {
  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    port,
    timeout: const Duration(seconds: 2),
  );
  final headersReceived = Completer<void>();
  final headerBytes = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> subscription;
  subscription = socket.listen(
    (chunk) {
      if (headersReceived.isCompleted) return;
      headerBytes.add(chunk);
      final text = utf8.decode(headerBytes.toBytes(), allowMalformed: true);
      if (!text.contains('\r\n\r\n')) return;
      if (!text.startsWith('HTTP/1.1 200')) {
        headersReceived.completeError(StateError(
          'Media stream rejected: ${text.split('\r\n').first}',
        ));
        return;
      }
      headersReceived.complete();
    },
    onError: (Object error, StackTrace stack) {
      if (!headersReceived.isCompleted) {
        headersReceived.completeError(error, stack);
      }
    },
    onDone: () {
      if (!headersReceived.isCompleted) {
        headersReceived.completeError(StateError('Media stream ended'));
      }
    },
    cancelOnError: true,
  );
  socket.write(
    'GET $path?streamToken=${Uri.encodeQueryComponent(streamToken)} HTTP/1.1\r\n'
    'Host: 127.0.0.1:$port\r\n'
    'Connection: close\r\n'
    '\r\n',
  );
  await socket.flush();
  try {
    await headersReceived.future.timeout(const Duration(seconds: 2));
  } catch (_) {
    socket.destroy();
    await subscription.cancel();
    rethrow;
  }
  return _OpenMediaStream(socket, subscription);
}

Future<({int statusCode, Map<String, Object?> body, String? retryAfter})>
    _requestRejectedMediaStream(
  int port,
  String path,
  String streamToken,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: path,
      queryParameters: {'streamToken': streamToken},
    ));
    final response = await request.close().timeout(const Duration(seconds: 2));
    final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
    final body = await utf8.decoder.bind(response).join();
    return (
      statusCode: response.statusCode,
      body: Map<String, Object?>.from(jsonDecode(body) as Map),
      retryAfter: retryAfter,
    );
  } finally {
    client.close(force: true);
  }
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
    MiuCamProtocolV2.sessionStart,
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
      path: MiuCamProtocolV2.video,
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
      path: MiuCamProtocolV2.audio,
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
