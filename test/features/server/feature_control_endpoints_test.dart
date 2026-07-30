import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:miucam/services/platform/pcm_audio_output.dart';
import 'package:miucam/services/server/baby_monitor_feature_controller.dart';
import 'package:miucam/services/server/room_audio_coordinator.dart';
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
      MiuCamProtocolV2.sessionStart,
      {'clientId': trusted.clientId},
      bearerToken: trusted.token,
    );
    final streamToken = start.body['streamToken'] as String;

    expect(
      await _getStatusCode(
        client,
        base.port,
        MiuCamProtocolV2.comfortState,
      ),
      HttpStatus.unauthorized,
    );
    expect(
      (await _postJson(
        client,
        base.port,
        MiuCamProtocolV2.comfortCommand,
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
        MiuCamProtocolV2.comfortState,
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
      MiuCamProtocolV2.comfortCommand,
      {'action': 'play', 'trackId': 'rain', 'volume': 0.7},
      bearerToken: trusted.token,
    );
    final nightLight = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.nightLightCommand,
      {'action': 'on', 'mode': 'screenGlow', 'brightness': 0.4},
      bearerToken: trusted.token,
    );

    expect(comfort.statusCode, HttpStatus.ok);
    expect((comfort.body['state'] as Map)['playing'], isTrue);
    expect((comfort.body['state'] as Map)['trackId'], 'rain');

    final shushing = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.comfortCommand,
      {'action': 'play', 'trackId': 'shushing', 'volume': 0.35},
      bearerToken: trusted.token,
    );
    expect(shushing.statusCode, HttpStatus.ok);
    expect((shushing.body['state'] as Map)['trackId'], 'shushing');

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
      MiuCamProtocolV2.talkStart,
      const {},
      bearerToken: anne.token,
    );
    final busy = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStart,
      const {},
      bearerToken: baba.token,
    );
    final talkToken =
        ((start.body['session'] as Map)['talkToken'] as String?) ?? '';

    final rejected = await _postBytes(
      client,
      base.port,
      MiuCamProtocolV2.talkAudio,
      Uint8List.fromList([1, 2, 3]),
      query: {'streamToken': 'not-a-talk-token'},
    );
    final accepted = await _postBytes(
      client,
      base.port,
      MiuCamProtocolV2.talkAudio,
      Uint8List.fromList([1, 2, 3, 4]),
      query: {'talkToken': talkToken},
    );
    final stop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStop,
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

  test('talk attempt siralamasi gec kalan start ve stop isteklerini izole eder',
      () async {
    final tokenService = PairingTokenService();
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final anne = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final first = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStart,
      {MiuCamProtocolV2.talkAttemptId: 'attempt-a'},
      bearerToken: anne.token,
    );
    final second = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStart,
      {MiuCamProtocolV2.talkAttemptId: 'attempt-b'},
      bearerToken: anne.token,
    );
    final firstToken =
        ((first.body['session'] as Map)['talkToken'] as String?) ?? '';
    final secondToken =
        ((second.body['session'] as Map)['talkToken'] as String?) ?? '';

    final lateFirstStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStop,
      {
        MiuCamProtocolV2.talkAttemptId: 'attempt-a',
        'talkToken': firstToken,
      },
      bearerToken: anne.token,
    );
    final successorAudio = await _postBytes(
      client,
      base.port,
      MiuCamProtocolV2.talkAudio,
      Uint8List.fromList([4, 3, 2, 1]),
      query: {'talkToken': secondToken},
    );

    expect(first.statusCode, HttpStatus.ok);
    expect(second.statusCode, HttpStatus.ok);
    expect(
      (second.body['session'] as Map)[MiuCamProtocolV2.talkAttemptId],
      'attempt-b',
    );
    expect(lateFirstStop.body['ok'], isFalse);
    expect(successorAudio.statusCode, HttpStatus.ok);

    final successorStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStop,
      {
        MiuCamProtocolV2.talkAttemptId: 'attempt-b',
        'talkToken': secondToken,
      },
      bearerToken: anne.token,
    );
    expect(successorStop.body['ok'], isTrue);

    final stopBeforeStart = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStop,
      {MiuCamProtocolV2.talkAttemptId: 'attempt-c'},
      bearerToken: anne.token,
    );
    final cancelledStart = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStart,
      {MiuCamProtocolV2.talkAttemptId: 'attempt-c'},
      bearerToken: anne.token,
    );

    expect(stopBeforeStart.body['ok'], isFalse);
    expect(cancelledStart.statusCode, HttpStatus.conflict);
    expect(cancelledStart.body['code'], 'TALK_START_CANCELLED');
  });

  test(
      'v2 lifecycle endpointleri eski trusted bearer ile eksik veya gecersiz attempt kabul etmez',
      () async {
    final tokenService = PairingTokenService();
    // This token exists before the v2-only server starts, mirroring a trusted
    // client persisted by an older app build.
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Eski Anne',
      deviceId: 'legacy-anne',
    );
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    Future<void> expectInvalidAttempt(
      String path,
      Map<String, Object?> body,
      String code,
    ) async {
      final response = await _postJson(
        client,
        base.port,
        path,
        body,
        bearerToken: trusted.token,
        includeAttemptFixture: false,
      );
      expect(response.statusCode, HttpStatus.badRequest, reason: path);
      expect(response.body['ok'], isFalse, reason: path);
      expect(response.body['code'], code, reason: path);
    }

    await expectInvalidAttempt(
      MiuCamProtocolV2.sessionStart,
      {'clientId': trusted.clientId},
      MiuCamProtocolV2.invalidStreamAttemptIdCode,
    );
    await expectInvalidAttempt(
      MiuCamProtocolV2.sessionStart,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: ' invalid',
      },
      MiuCamProtocolV2.invalidStreamAttemptIdCode,
    );

    final activeStream = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'stream-current',
      },
      bearerToken: trusted.token,
    );
    final streamToken = activeStream.body['streamToken']! as String;
    await expectInvalidAttempt(
      MiuCamProtocolV2.sessionStop,
      {'clientId': trusted.clientId},
      MiuCamProtocolV2.invalidStreamAttemptIdCode,
    );
    await expectInvalidAttempt(
      MiuCamProtocolV2.sessionStop,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: <String>[],
      },
      MiuCamProtocolV2.invalidStreamAttemptIdCode,
    );
    expect(tokenService.validateStreamToken(streamToken), isNotNull);

    await expectInvalidAttempt(
      MiuCamProtocolV2.talkStart,
      const {},
      MiuCamProtocolV2.invalidTalkAttemptIdCode,
    );
    await expectInvalidAttempt(
      MiuCamProtocolV2.talkStart,
      {MiuCamProtocolV2.talkAttemptId: 'bad attempt'},
      MiuCamProtocolV2.invalidTalkAttemptIdCode,
    );

    final activeTalk = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStart,
      {MiuCamProtocolV2.talkAttemptId: 'talk-current'},
      bearerToken: trusted.token,
    );
    final talkToken =
        (activeTalk.body['session'] as Map)['talkToken']! as String;
    await expectInvalidAttempt(
      MiuCamProtocolV2.talkStop,
      {'talkToken': talkToken},
      MiuCamProtocolV2.invalidTalkAttemptIdCode,
    );
    await expectInvalidAttempt(
      MiuCamProtocolV2.talkStop,
      {
        'talkToken': talkToken,
        MiuCamProtocolV2.talkAttemptId: '',
      },
      MiuCamProtocolV2.invalidTalkAttemptIdCode,
    );
    final stillActive = await _postBytes(
      client,
      base.port,
      MiuCamProtocolV2.talkAudio,
      Uint8List.fromList([1, 0]),
      query: {'talkToken': talkToken},
    );
    expect(stillActive.statusCode, HttpStatus.ok);

    final exactTalkStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.talkStop,
      {
        'talkToken': talkToken,
        MiuCamProtocolV2.talkAttemptId: 'talk-current',
      },
      bearerToken: trusted.token,
    );
    final exactStreamStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'stream-current',
      },
      bearerToken: trusted.token,
    );
    expect(exactTalkStop.body['ok'], isTrue);
    expect(exactStreamStop.body['ok'], isTrue);
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
      MiuCamProtocolV2.sessionStart,
      {'clientId': trusted.clientId},
      bearerToken: trusted.token,
    );

    expect(start.statusCode, HttpStatus.paymentRequired);
    expect(start.body['code'], 'BROADCAST_ACCESS_LOCKED');
    expect(start.body.containsKey('streamToken'), isFalse);
    expect((start.body['broadcastAccess'] as Map)['locked'], isTrue);
  });

  test('inactive authoritative snapshot server expiry timerini tekrar kurmaz',
      () async {
    SharedPreferences.setMockInitialValues({});
    final access = _ServerTimerBroadcastAccess(
      await SharedPreferences.getInstance(),
      beginSnapshot: _timerSnapshot(active: true, remainingMs: 20),
      authoritativeSnapshot: _timerSnapshot(
        active: false,
        remainingMs: 20,
      ),
    );
    addTearDown(access.dispose);
    final tokenService = PairingTokenService();
    final server = await _testServer(
      tokenService,
      broadcastAccessOverride: access,
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
      MiuCamProtocolV2.sessionStart,
      {'clientId': trusted.clientId},
      bearerToken: trusted.token,
    );
    expect(start.statusCode, HttpStatus.ok);

    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(access.snapshotCalls, 1);
    expect(access.endSessionCalls, 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(access.snapshotCalls, 1, reason: 'inactive timer loop yapmaz');
  });
}

Future<MiuCamServer> _testServer(
  PairingTokenService tokenService, {
  Map<String, Object> initialPreferences = const {},
  bool enableBroadcastAccess = false,
  BroadcastAccessService? broadcastAccessOverride,
}) async {
  SharedPreferences.setMockInitialValues(initialPreferences);
  final preferences = await SharedPreferences.getInstance();
  return MiuCamServer(
    config: ConfigurationService(preferences),
    strings: AppStrings(const Locale('tr')),
    onLog: (_) {},
    onAlert: (_) {},
    tokenService: tokenService,
    httpPort: 0,
    startMediaOnSessionStart: false,
    featureController: BabyMonitorFeatureController(
      roomAudio: RoomAudioCoordinator(sink: _FakePcmAudioSink()),
    ),
    broadcastAccess: broadcastAccessOverride ??
        (enableBroadcastAccess
            ? BroadcastAccessService(
                preferences,
                purchaseGateway: _FakePurchaseGateway(),
              )
            : null),
  );
}

BroadcastAccessSnapshot _timerSnapshot({
  required bool active,
  required int remainingMs,
}) =>
    BroadcastAccessSnapshot(
      unlocked: false,
      active: active,
      freeLimitMs: 1000,
      usedMs: 1000 - remainingMs,
      remainingMs: remainingMs,
      priceLabel: 'test',
      productId: BroadcastAccessConfig.productId,
    );

class _ServerTimerBroadcastAccess extends BroadcastAccessService {
  _ServerTimerBroadcastAccess(
    super.preferences, {
    required this.beginSnapshot,
    required this.authoritativeSnapshot,
  }) : super(purchaseGateway: _FakePurchaseGateway());

  final BroadcastAccessSnapshot beginSnapshot;
  final BroadcastAccessSnapshot authoritativeSnapshot;
  int snapshotCalls = 0;
  int endSessionCalls = 0;

  @override
  Future<BroadcastAccessSnapshot> beginSession(String sessionId) async =>
      beginSnapshot;

  @override
  Future<BroadcastAccessSnapshot> snapshot() async {
    snapshotCalls++;
    return authoritativeSnapshot;
  }

  @override
  Future<BroadcastAccessSnapshot> endSession(String sessionId) async {
    endSessionCalls++;
    return authoritativeSnapshot;
  }

  @override
  Future<BroadcastAccessSnapshot> endAllSessions() async =>
      authoritativeSnapshot;
}

class _FakePcmAudioSink implements PcmAudioSink {
  @override
  Future<void> start({required int sampleRate, required int channels}) async {}

  @override
  Future<Map<String, Object?>> status() async => const {'started': true};

  @override
  Future<void> stop() async {}

  @override
  Future<bool> write(Uint8List pcm16le) async => true;
}

class _FakePurchaseGateway implements BroadcastPurchaseGateway {
  @override
  Future<BroadcastPurchaseResult> purchase({
    required String productId,
    required String priceLabel,
  }) async =>
      const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.purchased,
        verified: true,
        verificationSource: 'test_store',
        verificationFingerprint: 'test-fingerprint',
      );

  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async =>
      const BroadcastPurchaseResult(
        status: BroadcastPurchaseStatus.restored,
        verified: true,
        verificationSource: 'test_store',
        verificationFingerprint: 'test-fingerprint',
      );

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
  bool includeAttemptFixture = true,
}) async {
  final request = await client.postUrl(_uri(port, path, query: query));
  request.headers.contentType = ContentType.json;
  if (bearerToken != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
  }
  request.write(jsonEncode(
    includeAttemptFixture ? _withV2AttemptFixture(path, body) : body,
  ));
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
      () => 'feature-stream-fixture-attempt',
    );
  }
  if (path == MiuCamProtocolV2.talkStart || path == MiuCamProtocolV2.talkStop) {
    fixture.putIfAbsent(
      MiuCamProtocolV2.talkAttemptId,
      () => 'feature-talk-fixture-attempt',
    );
  }
  return fixture;
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
