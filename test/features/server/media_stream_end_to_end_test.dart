import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/features/client/media/mjpeg_stream_parser.dart';
import 'package:miucam/features/client/media/stream_session_controller.dart';
import 'package:miucam/features/client/media/wav_pcm_stream_parser.dart';
import 'package:miucam/features/client/pairing/pairing_failure.dart';
import 'package:miucam/features/client/pairing/pairing_payload_gateway.dart';
import 'package:miucam/features/client/pairing/pairing_session_store.dart';
import 'package:miucam/features/client/pairing/qr_pairing_client.dart';
import 'package:miucam/features/client/pairing/trusted_token_renewal_client.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/features/server/pairing/server_qr_payload_builder.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/deterministic_server_media_source.dart';

void main() {
  for (final useCode in [true, false]) {
    test(
        '${useCode ? 'PIN' : 'QR'} pairing persists, streams without pairing mode, renews and revokes',
        () async {
      final tokens = PairingTokenService();
      final server = await _testServer(tokens, analysisEnabled: false);
      addTearDown(server.dispose);
      final port = Uri.parse(await server.startPairingMode()).port;
      final public = await const HttpPairingPayloadGateway().fetch(
        host: '127.0.0.1',
        port: port,
      );
      expect(public.requiresPairingCode, isTrue);
      expect(public.pairingCode, isNull);
      final pairing = QRPairingClient(
        clientIdProvider: () async => 'acceptance-parent',
      );
      late final PairingPayload invitation;
      if (useCode) {
        await expectLater(
          pairing.pair(public),
          throwsA(isA<PairingFailure>().having(
            (failure) => failure.code,
            'code',
            PairingFailureCode.pairingCodeInvalidOrExpired,
          )),
        );
        expect(server.trustedClients, isEmpty);
        invitation = public.withPairingCode(tokens.pairingCode);
      } else {
        // Exercise the shipped QR encoder/parser, not a handcrafted HTTP body.
        final qr = ServerQrPayloadBuilder(
          tokenService: tokens,
          deviceId: public.deviceId,
          deviceName: public.deviceName,
        ).build(host: '127.0.0.1', port: port);
        invitation = PairingPayload.parseUri(qr.toUriString())!;
        expect(invitation.requiresPairingCode, isFalse);
      }
      final paired = await pairing.pair(invitation);
      expect(paired.payload.pairingCode, isNull);
      expect(server.trustedClients.single.clientId, paired.clientId);
      expect(tokens.isPairingNonceActive(invitation.pairingNonce), isFalse);

      final preferences = await SharedPreferences.getInstance();
      final secureTokens = _MemorySecureTokenStore();
      await PairingSessionStore(preferences, secureTokens: secureTokens)
          .save(paired);
      final storedMetadata =
          jsonDecode(preferences.getString('pairing_session')!)
              as Map<String, dynamic>;
      expect(storedMetadata['payload'], isNot(contains('pairingCode')));
      expect(storedMetadata, isNot(contains('token')));

      // A fresh parent store reuses its persisted authority after the room
      // closes invitations. Neither the expired invitation nor its code is
      // needed to renew authorization or begin another watch session.
      await server.stopPairingMode();
      expect(tokens.pairingCode, isNull);
      final restored = await PairingSessionStore(
        preferences,
        secureTokens: secureTokens,
      ).load();
      expect(restored, isNotNull);
      expect(restored!.sessionToken, paired.sessionToken);
      expect(restored.payload.pairingCode, isNull);
      final streams = StreamSessionController();
      addTearDown(streams.dispose);
      final firstWatch = await streams.start(restored, audioEnabled: true);
      expect(firstWatch, isNotNull);
      final firstMedia = await Future.wait<Object>([
        _readFirstMjpegFrame(port, firstWatch!.streamToken),
        _readFirstPcmChunk(port, firstWatch.streamToken),
      ]);
      expect((firstMedia[0] as Uint8List).length, greaterThan(100));
      final audio = firstMedia[1] as ParsedPcmAudio;
      expect(audio.sampleRate, 16000);
      expect(audio.pcm16le, isNotEmpty);
      await streams.stop(restored);
      expect(server.activeWatchClientIds, isEmpty);

      final renewed = await TrustedTokenRenewalClient().renew(restored);
      expect(renewed, isNotNull);
      expect(renewed!.clientId, restored.clientId);
      expect(renewed.sessionToken, isNot(restored.sessionToken));
      final secondWatch = await streams.start(renewed, audioEnabled: true);
      expect(await _readFirstMjpegFrame(port, secondWatch!.streamToken),
          isNotEmpty);
      expect(server.activeWatchClientIds, contains(renewed.clientId));

      await server.revokeTrustedClient(renewed.clientId);
      expect(server.activeWatchClientIds, isEmpty);
      expect(await TrustedTokenRenewalClient().renew(renewed), isNull);
      final revokedStream = await _requestRejectedMediaStream(
        port,
        MiuCamProtocolV2.video,
        secondWatch.streamToken,
      );
      expect(revokedStream.statusCode, HttpStatus.unauthorized);
    });
  }

  test('streamToken ile gerçek video ve audio endpointleri medya üretir',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService, analysisEnabled: false);
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
    final analysis = status['analysis'] as Map;
    expect((analysis['audio'] as Map)['windowsAnalyzed'], 0,
        reason: 'Disabling alerts must preserve the real WAV stream.');
    expect((analysis['motion'] as Map)['framesAnalyzed'], 0,
        reason: 'Disabling alerts must preserve the real MJPEG stream.');
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

class _MemorySecureTokenStore implements SecureTokenStore {
  final _values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => _values.remove(key);
}

Future<MiuCamServer> _testServer(
  PairingTokenService tokenService, {
  bool startMediaOnSessionStart = true,
  bool analysisEnabled = true,
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
    audioAnalysisDemand: () => analysisEnabled,
    videoAnalysisDemand: () => analysisEnabled,
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
      body: body.isEmpty
          ? <String, Object?>{}
          : Map<String, Object?>.from(jsonDecode(body) as Map),
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
  request.write(jsonEncode(_withV2AttemptFixture(path, body)));
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  final json =
      responseBody.isEmpty ? <String, Object?>{} : jsonDecode(responseBody);
  return (
    statusCode: response.statusCode,
    body: json is Map ? Map<String, Object?>.from(json) : <String, Object?>{},
  );
}

Map<String, Object?> _withV2AttemptFixture(
  String path,
  Map<String, Object?> body,
) {
  final fixture = Map<String, Object?>.of(body);
  if (path == MiuCamProtocolV2.sessionStart ||
      path == MiuCamProtocolV2.sessionStop) {
    fixture.putIfAbsent(
      MiuCamProtocolV2.streamAttemptId,
      () => 'media-stream-fixture-attempt',
    );
  }
  return fixture;
}
