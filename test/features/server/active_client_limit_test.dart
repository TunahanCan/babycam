import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
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
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId},
    );
    final repaired = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
      existingTrustedClientToken: trusted.token,
    );
    final second = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
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
    final runtimeAudioDemands = <bool>[];
    final server = await _testServer(
      tokenService,
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) {
        runtimeStarts++;
        runtimeAudioDemands.add(audio);
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
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId, 'video': true, 'audio': false},
    );
    final failedReplacement = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId, 'video': true, 'audio': true},
    );
    final recovered = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
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
    // The failed replacement may have partially mutated native capture before
    // throwing, so the server must actively restore the prior demand.
    expect(runtimeStarts, 3);
    expect(runtimeAudioDemands, const [false, true, false]);
  });

  test(
      'medya attach etmeden kaybolan client expiry sonrası runtimeı ve sessionı bırakır',
      () async {
    var now = DateTime(2026);
    final tokenService = PairingTokenService(
      now: () => now,
      streamTokenTtl: const Duration(milliseconds: 20),
    );
    var runtimeStarts = 0;
    var runtimeStops = 0;
    final runtimeStopped = Completer<void>();
    final server = await _testServer(
      tokenService,
      streamSessionReaperInterval: const Duration(milliseconds: 5),
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) =>
          runtimeStarts++,
      onStreamSessionStopped: (_) {
        runtimeStops++;
        if (!runtimeStopped.isCompleted) runtimeStopped.complete();
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

    final started = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId},
    );
    expect(started.statusCode, HttpStatus.ok);
    expect(started.body['activeStreamClients'], 1);
    expect(runtimeStarts, 1);

    // The app/process disappears before opening a media transport. No HTTP
    // session/stop arrives; the server-owned reaper must release runtime demand.
    now = now.add(const Duration(seconds: 1));
    await runtimeStopped.future.timeout(const Duration(seconds: 2));

    expect(runtimeStops, 1);
    expect(
      tokenService.validateStreamToken(
        started.body['streamToken']! as String,
      ),
      isNull,
    );

    final idempotentStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      trusted.token,
      {'clientId': trusted.clientId},
    );
    expect(idempotentStop.statusCode, HttpStatus.ok);
    expect(idempotentStop.body['activeStreamClients'], 0);
    expect(runtimeStops, 1);
  });

  test(
      'expired tek slot yeni client start isteğinin ilk denemesinde temizlenir',
      () async {
    var now = DateTime(2026);
    final tokenService = PairingTokenService(
      now: () => now,
      streamTokenTtl: const Duration(milliseconds: 20),
    );
    var runtimeStarts = 0;
    var runtimeStops = 0;
    final server = await _testServer(
      tokenService,
      maxActiveWatchClients: 1,
      // Exercise the in-queue pre-start drain, not the periodic reaper.
      streamSessionReaperInterval: const Duration(hours: 1),
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) =>
          runtimeStarts++,
      onStreamSessionStopped: (_) => runtimeStops++,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final anne = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final baba = tokenService.issueTrustedClientToken(
      clientName: 'Baba',
      deviceId: 'baba',
    );

    final first = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      anne.token,
      {'clientId': anne.clientId},
    );
    expect(first.statusCode, HttpStatus.ok);

    now = now.add(const Duration(seconds: 1));
    final replacement = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      baba.token,
      {'clientId': baba.clientId},
    );

    expect(replacement.statusCode, HttpStatus.ok);
    expect(replacement.body['activeStreamClients'], 1);
    expect(runtimeStarts, 2);
    expect(runtimeStops, 1);
  });

  test(
      'önce gelen attempt stop aynı attemptin geç startını mutasyondan önce reddeder',
      () async {
    final tokenService = PairingTokenService();
    final access = _TrackingBroadcastAccess();
    var runtimeStarts = 0;
    var runtimeStops = 0;
    final server = await _testServer(
      tokenService,
      broadcastAccess: access,
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) =>
          runtimeStarts++,
      onStreamSessionStopped: (_) => runtimeStops++,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );

    final earlyStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      trusted.token,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'attempt-A',
      },
    );
    final lateStart = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'attempt-A',
      },
    );

    expect(earlyStop.statusCode, HttpStatus.ok);
    expect(earlyStop.body['activeStreamClients'], 0);
    expect(lateStart.statusCode, HttpStatus.conflict);
    expect(lateStart.body['code'], 'SESSION_START_CANCELLED');
    expect(runtimeStarts, 0);
    expect(runtimeStops, 0);
    expect(access.beginCalls, 0);
    expect(access.endCalls, 0);
  });

  test('geç stop A aktif attempt B oturumunu kapatmaz', () async {
    final tokenService = PairingTokenService();
    var runtimeStarts = 0;
    var runtimeStops = 0;
    final server = await _testServer(
      tokenService,
      onStreamSessionStarted: (
        _, {
        required video,
        required audio,
        required mediaTransport,
      }) =>
          runtimeStarts++,
      onStreamSessionStopped: (_) => runtimeStops++,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final trusted = tokenService.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );

    final activeB = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'attempt-B',
      },
    );
    final lateStopA = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      trusted.token,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'attempt-A',
      },
    );
    final cancelledA = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'attempt-A',
      },
    );

    expect(activeB.statusCode, HttpStatus.ok);
    expect(activeB.body[MiuCamProtocolV2.streamAttemptId], 'attempt-B');
    expect(lateStopA.statusCode, HttpStatus.ok);
    expect(lateStopA.body['activeStreamClients'], 1);
    expect(cancelledA.statusCode, HttpStatus.conflict);
    expect(
      tokenService.validateStreamToken(activeB.body['streamToken']! as String),
      isNotNull,
    );
    expect(runtimeStarts, 1);
    expect(runtimeStops, 0);

    final exactStopB = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      trusted.token,
      {
        'clientId': trusted.clientId,
        MiuCamProtocolV2.streamAttemptId: 'attempt-B',
      },
    );
    expect(exactStopB.statusCode, HttpStatus.ok);
    expect(exactStopB.body['activeStreamClients'], 0);
    expect(runtimeStops, 1);
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
      MiuCamProtocolV2.sessionStart,
      trusted.token,
      {'clientId': trusted.clientId},
    );
    final report = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.qualityReport,
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

    String? firstToken;
    for (var index = 0; index < 5; index++) {
      final token = tokenService.issueTrustedClientToken(
        clientName: 'Client $index',
        deviceId: 'client_$index',
      );
      firstToken ??= token.token;
      final response = await _postJson(
        client,
        base.port,
        MiuCamProtocolV2.sessionStart,
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
      MiuCamProtocolV2.sessionStart,
      sixth.token,
      {'clientId': sixth.clientId},
    );

    expect(rejected.statusCode, HttpStatus.tooManyRequests);
    expect(rejected.body['code'], 'MAX_ACTIVE_CLIENTS_REACHED');

    final stop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStop,
      firstToken!,
      {'clientId': 'client_0'},
    );
    expect(stop.statusCode, HttpStatus.ok);

    final acceptedAfterStop = await _postJson(
      client,
      base.port,
      MiuCamProtocolV2.sessionStart,
      sixth.token,
      {'clientId': sixth.clientId},
    );
    expect(acceptedAfterStop.statusCode, HttpStatus.ok);
  });

  test(
      'six simultaneous HTTP starts admit five and a removed viewer frees a slot',
      () async {
    final tokenService = PairingTokenService(maxTrustedClients: 10);
    final server = await _testServer(tokenService);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient()..maxConnectionsPerHost = 10;
    addTearDown(() => client.close(force: true));
    final tokens = [
      for (var index = 0; index < 6; index++)
        await tokenService.issueTrustedClientTokenPersisted(
          clientName: 'Phone $index',
          deviceId: 'parent-$index',
        ),
    ];
    final responses = await Future.wait([
      for (final token in tokens)
        _postJson(client, base.port, MiuCamProtocolV2.sessionStart, token.token,
            {'clientId': token.clientId}),
    ]);
    expect(responses.where((response) => response.statusCode == HttpStatus.ok),
        hasLength(5));
    final rejectedIndex = responses.indexWhere(
        (response) => response.statusCode == HttpStatus.tooManyRequests);
    expect(rejectedIndex, isNonNegative);
    expect(responses[rejectedIndex].body['code'], 'MAX_ACTIVE_CLIENTS_REACHED');
    expect(server.activeWatchClientIds, hasLength(5));

    final removedIndex = responses
        .indexWhere((response) => response.statusCode == HttpStatus.ok);
    final removed = tokens[removedIndex];
    final oldStreamToken =
        responses[removedIndex].body['streamToken']! as String;
    await server.revokeTrustedClient(removed.clientId);

    expect(server.activeWatchClientIds, hasLength(4));
    expect(server.activeWatchClientIds, isNot(contains(removed.clientId)));
    final oldBearer = await _postJson(
        client,
        base.port,
        MiuCamProtocolV2.sessionStart,
        removed.token,
        {'clientId': removed.clientId});
    expect(oldBearer.statusCode, HttpStatus.unauthorized);
    await _expectMediaDenied(client, base.port, oldStreamToken);

    final waiting = tokens[rejectedIndex];
    final accepted = await _postJson(
        client,
        base.port,
        MiuCamProtocolV2.sessionStart,
        waiting.token,
        {'clientId': waiting.clientId});
    expect(accepted.statusCode, HttpStatus.ok);
    expect(server.activeWatchClientIds, hasLength(5));
    expect(server.activeWatchClientIds, contains(waiting.clientId));
  });

  test('a failed deletion write still disconnects and rejects both old tokens',
      () async {
    final repository = _ControlledTrustedRepository();
    final tokenService =
        PairingTokenService(trustedClientRepository: repository);
    final stopped = Completer<String>();
    final server = await _testServer(
      tokenService,
      onStreamSessionStarted: (_,
          {required video, required audio, required mediaTransport}) {},
      onStreamSessionStopped: (clientId) {
        if (!stopped.isCompleted) stopped.complete(clientId);
      },
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final token = await tokenService.issueTrustedClientTokenPersisted(
        clientName: 'Anne', deviceId: 'parent-1');
    final started = await _postJson(
        client,
        base.port,
        MiuCamProtocolV2.sessionStart,
        token.token,
        {'clientId': token.clientId});
    expect(started.statusCode, HttpStatus.ok);
    repository.rejectWrites = true;

    await expectLater(server.revokeTrustedClient(token.clientId),
        throwsA(isA<TrustedClientPersistenceException>()));
    expect(await stopped.future.timeout(const Duration(seconds: 2)),
        token.clientId);
    expect(server.activeWatchClientIds, isEmpty);
    expect(tokenService.pendingRevocationClientIds, {token.clientId});
    final refused = await _postJson(
        client,
        base.port,
        MiuCamProtocolV2.sessionStart,
        token.token,
        {'clientId': token.clientId});
    expect(refused.statusCode, HttpStatus.unauthorized);
    await _expectMediaDenied(
        client, base.port, started.body['streamToken']! as String);

    repository.rejectWrites = false;
    await server.revokeTrustedClient(token.clientId);
    expect(server.trustedClients, isEmpty);
    final restarted = PairingTokenService(trustedClientRepository: repository);
    expect(restarted.validateSessionToken(token.token), isFalse);
  });

  test('slow deletion storage cannot keep a removed viewer streaming',
      () async {
    final repository = _ControlledTrustedRepository();
    final tokenService =
        PairingTokenService(trustedClientRepository: repository);
    final stopped = Completer<void>();
    final server = await _testServer(
      tokenService,
      onStreamSessionStarted: (_,
          {required video, required audio, required mediaTransport}) {},
      onStreamSessionStopped: (_) {
        if (!stopped.isCompleted) stopped.complete();
      },
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final token = await tokenService.issueTrustedClientTokenPersisted(
        clientName: 'Anne', deviceId: 'parent-1');
    final started = await _postJson(
        client,
        base.port,
        MiuCamProtocolV2.sessionStart,
        token.token,
        {'clientId': token.clientId});
    expect(started.statusCode, HttpStatus.ok);
    repository.blockNextWrite();
    var removalCompleted = false;
    final removal = server.revokeTrustedClient(token.clientId).then((_) {
      removalCompleted = true;
    });
    addTearDown(repository.releaseBlockedWrite);
    await repository.writeStarted;
    await stopped.future.timeout(const Duration(seconds: 2));

    expect(removalCompleted, isFalse);
    expect(server.activeWatchClientIds, isEmpty);
    expect(tokenService.validateSessionToken(token.token), isFalse);
    await _expectMediaDenied(
        client, base.port, started.body['streamToken']! as String);
    repository.releaseBlockedWrite();
    await removal;
    expect(server.trustedClients, isEmpty);
  });

  for (final queuedPath in [
    MiuCamProtocolV2.sessionStart,
    MiuCamProtocolV2.sessionStop,
  ]) {
    test(
        'a queued $queuedPath rechecks revocation and cannot affect another device',
        () async {
      final tokenService = _ObservedPairingTokenService();
      final firstRuntimeEntered = Completer<void>();
      final releaseFirstRuntime = Completer<void>();
      final runtimeClientIds = <String>[];
      final server = await _testServer(
        tokenService,
        onStreamSessionStarted: (clientId,
            {required video, required audio, required mediaTransport}) async {
          runtimeClientIds.add(clientId);
          if (!firstRuntimeEntered.isCompleted) {
            firstRuntimeEntered.complete();
            await releaseFirstRuntime.future;
          }
        },
      );
      addTearDown(server.dispose);
      addTearDown(() {
        if (!releaseFirstRuntime.isCompleted) releaseFirstRuntime.complete();
      });
      final base = Uri.parse(await server.startPairingMode());
      final client = HttpClient()..maxConnectionsPerHost = 10;
      addTearDown(() => client.close(force: true));
      final first = await tokenService.issueTrustedClientTokenPersisted(
          clientName: 'Anne', deviceId: 'first');
      final removed = await tokenService.issueTrustedClientTokenPersisted(
          clientName: 'Baba', deviceId: 'removed');
      final firstStart = _postJson(
          client,
          base.port,
          MiuCamProtocolV2.sessionStart,
          first.token,
          {'clientId': first.clientId});
      await firstRuntimeEntered.future.timeout(const Duration(seconds: 2));
      final queuedWasAuthorized = Completer<void>();
      tokenService.onValidated = (token) {
        if (token == removed.token && !queuedWasAuthorized.isCompleted) {
          queuedWasAuthorized.complete();
        }
      };
      final queuedRequest = _postJson(client, base.port, queuedPath,
          removed.token, {'clientId': first.clientId});
      await queuedWasAuthorized.future.timeout(const Duration(seconds: 2));

      final removal = server.revokeTrustedClient(removed.clientId);
      expect(tokenService.validateSessionToken(removed.token), isFalse);
      releaseFirstRuntime.complete();
      final firstResponse = await firstStart;
      final removedResponse = await queuedRequest;
      await removal;

      expect(firstResponse.statusCode, HttpStatus.ok);
      expect(removedResponse.statusCode, HttpStatus.unauthorized);
      expect(runtimeClientIds, [first.clientId]);
      expect(server.activeWatchClientIds, {first.clientId});
      expect(
          tokenService.hasValidStreamTokenForClient(removed.clientId), isFalse);
    });
  }
}

class _ObservedPairingTokenService extends PairingTokenService {
  void Function(String token)? onValidated;

  @override
  TrustedClientRecord? validateTrustedClientToken(String token) {
    final result = super.validateTrustedClientToken(token);
    if (result != null) onValidated?.call(token);
    return result;
  }
}

class _ControlledTrustedRepository implements TrustedClientRepository {
  List<TrustedClientRecord> records = [];
  bool rejectWrites = false;
  Completer<void>? _writeStarted;
  Completer<void>? _writeGate;

  Future<void> get writeStarted => _writeStarted!.future;

  void blockNextWrite() {
    _writeStarted = Completer<void>();
    _writeGate = Completer<void>();
  }

  void releaseBlockedWrite() {
    final gate = _writeGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  List<TrustedClientRecord> readAll() => List.of(records);

  @override
  Future<void> replaceAll(List<TrustedClientRecord> clients) async {
    final gate = _writeGate;
    if (gate != null) {
      if (!_writeStarted!.isCompleted) _writeStarted!.complete();
      await gate.future;
      _writeGate = null;
    }
    if (rejectWrites) throw StateError('disk unavailable');
    records = List.of(clients);
  }
}

Future<void> _expectMediaDenied(
    HttpClient client, int port, String token) async {
  for (final path in [MiuCamProtocolV2.audio, MiuCamProtocolV2.video]) {
    final request = await client.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: path,
      queryParameters: {'streamToken': token},
    ));
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.unauthorized);
  }
}

Future<MiuCamServer> _testServer(
  PairingTokenService tokenService, {
  FutureOr<void> Function(
    String clientId, {
    required bool video,
    required bool audio,
    required String mediaTransport,
  })? onStreamSessionStarted,
  FutureOr<void> Function(String clientId)? onStreamSessionStopped,
  BroadcastAccessService? broadcastAccess,
  Duration streamSessionReaperInterval = const Duration(seconds: 5),
  int maxActiveWatchClients = 5,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return MiuCamServer(
    config: ConfigurationService(preferences),
    strings: AppStrings(const Locale('tr')),
    onLog: (_) {},
    onAlert: (_) {},
    onStreamSessionStarted: onStreamSessionStarted,
    onStreamSessionStopped: onStreamSessionStopped,
    broadcastAccess: broadcastAccess,
    tokenService: tokenService,
    streamSessionReaperInterval: streamSessionReaperInterval,
    maxActiveWatchClients: maxActiveWatchClients,
    httpPort: 0,
    startMediaOnSessionStart: false,
  );
}

class _TrackingBroadcastAccess implements BroadcastAccessService {
  int beginCalls = 0;
  int endCalls = 0;

  @override
  Future<BroadcastAccessSnapshot> beginSession(String sessionId) async {
    beginCalls++;
    return _snapshot(active: true);
  }

  @override
  Future<BroadcastAccessSnapshot> endSession(String sessionId) async {
    endCalls++;
    return _snapshot(active: false);
  }

  @override
  Future<BroadcastAccessSnapshot> endAllSessions() async =>
      _snapshot(active: false);

  @override
  Future<BroadcastAccessSnapshot> snapshot() async => _snapshot(active: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  static BroadcastAccessSnapshot _snapshot({required bool active}) =>
      BroadcastAccessSnapshot(
        unlocked: false,
        active: active,
        freeLimitMs: BroadcastAccessConfig.freeLimit.inMilliseconds,
        usedMs: 0,
        remainingMs: BroadcastAccessConfig.freeLimit.inMilliseconds,
        priceLabel: BroadcastAccessConfig.oneTimePriceLabel,
        productId: BroadcastAccessConfig.productId,
      );
}

Future<({int statusCode, Map<String, Object?> body})> _postJson(
  HttpClient client,
  int port,
  String path,
  String token,
  Map<String, Object?> body, {
  bool includeAttemptFixture = true,
}) async {
  final request = await client.postUrl(Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: path,
  ));
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
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
      () => 'active-client-fixture-attempt',
    );
  }
  return fixture;
}
