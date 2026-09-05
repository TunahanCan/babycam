import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/webrtc_signaling.dart';
import 'package:miucam/features/server/media/server_media_source.dart';
import 'package:miucam/features/server/media/webrtc/webrtc_server_gateway.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:miucam/services/monetization/broadcast_access_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('post-capture access await cannot restore a revoked HTTP stream',
      () async {
    final harness = await _Harness.start(blockFinalMediaSnapshot: true);
    addTearDown(harness.close);
    final access = harness.access as _BlockingSnapshotAccess;
    final trusted = harness.tokens
        .issueTrustedClientToken(clientName: 'Parent', deviceId: 'parent');
    final start = await harness
        .post(MiuCamProtocolV2.sessionStart, trusted.token, const {});
    final request = await harness.http.getUrl(harness.url(
        MiuCamProtocolV2.video,
        {'streamToken': start.body['streamToken'] as String}));
    final result = request.close();
    addTearDown(() {
      if (!access.release.isCompleted) access.release.complete();
    });
    await access.entered.future.timeout(const Duration(seconds: 2));
    await harness.server.revokeTrustedClient(trusted.clientId);
    access.release.complete();
    final response = await result;
    expect(response.statusCode, HttpStatus.unauthorized);
    await response.drain<void>();
    expect(harness.server.activeWatchClientIds, isEmpty);
  });

  test(
      'last AV transport loss pauses billing before token expiry and reconnect resumes',
      () async {
    final source = _MediaSource();
    final harness = await _Harness.start(mediaSource: source);
    addTearDown(harness.close);
    final trusted = harness.tokens
        .issueTrustedClientToken(clientName: 'Parent', deviceId: 'parent');
    final started = await harness
        .post(MiuCamProtocolV2.sessionStart, trusted.token, const {});
    final streamToken = started.body['streamToken'] as String;
    Future<Socket> attach(String path) async {
      final socket =
          await Socket.connect(InternetAddress.loopbackIPv4, harness.port);
      final header = Completer<void>();
      final bytes = <int>[];
      socket.listen((data) {
        if (header.isCompleted) return;
        bytes.addAll(data);
        final text = latin1.decode(bytes);
        if (text.contains('\r\n\r\n')) {
          expect(text, startsWith('HTTP/1.1 200'));
          header.complete();
        }
      }, onError: (Object _) {});
      final uri = harness.url(path, {'streamToken': streamToken});
      socket.add(utf8.encode(
          'GET ${uri.path}?${uri.query} HTTP/1.1\r\nHost: 127.0.0.1:${harness.port}\r\nConnection: close\r\n\r\n'));
      await header.future.timeout(const Duration(seconds: 2));
      addTearDown(socket.destroy);
      return socket;
    }

    final video = await attach(MiuCamProtocolV2.video);
    final audio = await attach(MiuCamProtocolV2.audio);
    expect(source.videoSink, isNotNull);
    expect(source.audioSink, isNotNull);
    harness.elapsedMs = 100;
    video.destroy();
    source.emit();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect((await harness.access.snapshot()).active, isTrue,
        reason: 'The other live audio channel still counts.');
    audio.destroy();
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while ((await harness.access.snapshot()).active &&
        DateTime.now().isBefore(deadline)) {
      source.emit();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final statusRequest =
        await harness.http.getUrl(harness.url(MiuCamProtocolV2.status));
    statusRequest.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${trusted.token}');
    final statusResponse = await statusRequest.close();
    final status =
        jsonDecode(await utf8.decoder.bind(statusResponse).join()) as Map;
    expect((await harness.access.snapshot()).active, isFalse,
        reason:
            'video=${status['videoClients']} audio=${status['audioClients']} media=${status['mediaConnections']}');
    harness.elapsedMs = 400;
    expect((await harness.access.snapshot()).usedMs, 100);
    expect(harness.server.activeWatchClientIds, contains(trusted.clientId),
        reason:
            'The bootstrap token can remain usable without charging idle time.');
    await attach(MiuCamProtocolV2.audio);
    harness.elapsedMs = 500;
    final resumed = await harness.access.snapshot();
    expect(resumed.active, isTrue);
    expect(resumed.usedMs, 200);
  });

  test(
      'unused bootstrap token costs no time; WebRTC without HTTP media still counts',
      () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final trusted = harness.tokens
        .issueTrustedClientToken(clientName: 'Parent', deviceId: 'parent');
    final start = await harness.post(
        MiuCamProtocolV2.sessionStart,
        trusted.token,
        const {'mediaTransport': 'webrtc', 'video': true, 'audio': true});
    expect(start.status, HttpStatus.ok);
    harness.elapsedMs = 900;
    final idle = await harness.access.snapshot();
    expect(idle.active, isFalse);
    expect(idle.usedMs, 0);
    final offer =
        await harness.post(MiuCamProtocolV2.webRtcOffer, trusted.token, {
      'offer': {'type': 'offer', 'sdp': 'v=0\r\n'}
    }, query: {
      'streamToken': start.body['streamToken'] as String
    });
    expect(offer.status, HttpStatus.ok);
    expect(harness.gateway.activePeerCount, 1);
    harness.elapsedMs = 1000;
    final active = await harness.access.snapshot();
    expect(active.active, isTrue);
    expect(active.usedMs, 100);
  });

  test('replacing a WebRTC peer keeps negotiation metered', () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final trusted = harness.tokens
        .issueTrustedClientToken(clientName: 'Parent', deviceId: 'parent');
    final start = await harness.post(MiuCamProtocolV2.sessionStart,
        trusted.token, const {'mediaTransport': 'webrtc'});
    Future<({int status, Map<String, dynamic> body})> offer() =>
        harness.post(MiuCamProtocolV2.webRtcOffer, trusted.token, {
          'offer': {'type': 'offer', 'sdp': 'v=0\r\n'}
        }, query: {
          'streamToken': start.body['streamToken'] as String
        });
    expect((await offer()).status, HttpStatus.ok);
    final release = Completer<void>();
    final entered = Completer<void>();
    harness.gateway
      ..offerEntered = entered
      ..blockOffer = release.future;
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    harness.elapsedMs = 100;
    final replacing = offer();
    await entered.future.timeout(const Duration(seconds: 2));
    harness.elapsedMs = 200;
    final pending = await harness.access.snapshot();
    expect(pending.active, isTrue);
    expect(pending.usedMs, 200);
    release.complete();
    expect((await replacing).status, HttpStatus.ok);
  });

  test('exhausted room trial rejects event-only analysis before upgrading',
      () async {
    final harness = await _Harness.start(usedMs: 1000);
    addTearDown(harness.close);
    final trusted = harness.tokens
        .issueTrustedClientToken(clientName: 'Parent', deviceId: 'parent');
    final request =
        await harness.http.getUrl(harness.url(MiuCamProtocolV2.events));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${trusted.token}')
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Key', base64Encode(List<int>.filled(16, 1)));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.paymentRequired);
    expect(harness.alertStarted, isEmpty);
    final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    expect(body['code'], 'BROADCAST_ACCESS_LOCKED');
  });

  test('event-only observers consume one shared trial and all close on expiry',
      () async {
    final harness =
        await _Harness.start(freeLimit: const Duration(milliseconds: 250));
    addTearDown(harness.close);
    final closed = <Future<void>>[];
    for (var i = 0; i < 5; i++) {
      final trusted = harness.tokens
          .issueTrustedClientToken(clientName: 'Parent $i', deviceId: '$i');
      final socket = await WebSocket.connect(
          harness.url(MiuCamProtocolV2.events).replace(scheme: 'ws').toString(),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer ${trusted.token}'
          });
      final done = Completer<void>();
      socket.listen((_) {}, onDone: done.complete);
      closed.add(done.future);
      addTearDown(socket.close);
    }
    await _waitUntil(() => harness.alertStarted.length == 5);
    expect((await harness.access.snapshot()).active, isTrue);
    harness.elapsedMs = 250;
    await Future.wait(closed).timeout(const Duration(seconds: 3));
    await _waitUntil(() => harness.alertStopped.length == 5);
    final snapshot = await harness.access.snapshot();
    expect(snapshot.isLocked, isTrue);
    expect(snapshot.active, isFalse);
    expect(snapshot.usedMs, 250);
  });

  test(
      'expiry closes all five AV sessions and WebRTC even after another owner ended ledger',
      () async {
    final harness =
        await _Harness.start(freeLimit: const Duration(milliseconds: 500));
    addTearDown(harness.close);
    final streams = <Future<void>>[];
    final trustedClients = List.generate(
        5,
        (i) => harness.tokens
            .issueTrustedClientToken(clientName: 'Parent $i', deviceId: '$i'));
    for (var i = 0; i < trustedClients.length; i++) {
      final trusted = trustedClients[i];
      final start = await harness.post(
          MiuCamProtocolV2.sessionStart, trusted.token, {
        'video': true,
        'audio': true,
        'mediaTransport': i == 4 ? 'webrtc' : 'mjpeg_wav'
      });
      expect(start.status, HttpStatus.ok);
      final streamToken = start.body['streamToken'] as String;
      if (i == 4) {
        final offer =
            await harness.post(MiuCamProtocolV2.webRtcOffer, trusted.token, {
          'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
          'video': true,
          'audio': true
        }, query: {
          'streamToken': streamToken
        });
        expect(offer.status, HttpStatus.ok);
      } else {
        for (final path in [MiuCamProtocolV2.video, MiuCamProtocolV2.audio]) {
          final request = await harness.http
              .getUrl(harness.url(path, {'streamToken': streamToken}));
          final response = await request.close();
          expect(response.statusCode, HttpStatus.ok);
          streams.add(response.drain<void>());
        }
      }
    }
    expect(harness.server.activeWatchClientIds.length, 5);
    expect(harness.gateway.activePeerCount, 1);
    harness.elapsedMs = 500;
    // ServerRuntime may clear the shared ledger before the HTTP timer runs.
    await harness.access.endAllSessions();
    await Future.wait(streams).timeout(const Duration(seconds: 3));
    await _waitUntil(() => harness.stopped.length == 5);
    expect(harness.gateway.activePeerCount, 0);
    expect(harness.server.activeWatchClientIds.length, 0);
    for (final trusted in trustedClients) {
      final rejected = await harness
          .post(MiuCamProtocolV2.sessionStart, trusted.token, const {});
      expect(rejected.status, HttpStatus.paymentRequired);
    }
  });

  test('event reconnect grace preserves analysis without charging offline time',
      () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final trusted = harness.tokens.issueTrustedClientToken(
      clientName: 'Parent',
      deviceId: 'parent',
    );
    Future<WebSocket> connect() => WebSocket.connect(
          harness.url(MiuCamProtocolV2.events).replace(scheme: 'ws').toString(),
          headers: {HttpHeaders.authorizationHeader: 'Bearer ${trusted.token}'},
        );
    final first = await connect();
    first.listen((_) {});
    await _waitUntil(() => harness.alertStarted.length == 1);
    harness.elapsedMs = 100;
    final idle =
        harness.access.changes.firstWhere((snapshot) => !snapshot.active);
    await first.close();
    await idle.timeout(const Duration(seconds: 2));
    harness.elapsedMs = 400;
    expect((await harness.access.snapshot()).usedMs, 100);
    expect(harness.alertStopped, isEmpty,
        reason: 'The existing analysis grace period is preserved.');

    final second = await connect();
    addTearDown(second.close);
    second.listen((_) {});
    final active = await harness.access.snapshot();
    expect(active.active, isTrue);
    harness.elapsedMs = 500;
    expect((await harness.access.snapshot()).usedMs, 200);
    expect(harness.alertStarted, hasLength(1),
        reason: 'Reconnect resumes billing without restarting armed analysis.');
  });

  test('expiry stops live delivery while another session startup is stalled',
      () async {
    final entered = Completer<void>();
    final finish = Completer<void>();
    var starts = 0;
    final harness = await _Harness.start(
      freeLimit: const Duration(milliseconds: 150),
      streamStart: (_) async {
        if (++starts == 2) {
          entered.complete();
          await finish.future;
        }
      },
    );
    addTearDown(() async {
      if (!finish.isCompleted) finish.complete();
      await harness.close();
    });
    final first = harness.tokens
        .issueTrustedClientToken(clientName: 'First', deviceId: 'first');
    final second = harness.tokens
        .issueTrustedClientToken(clientName: 'Second', deviceId: 'second');
    final started = await harness
        .post(MiuCamProtocolV2.sessionStart, first.token, const {});
    final request = await harness.http.getUrl(harness.url(
        MiuCamProtocolV2.audio,
        {'streamToken': started.body['streamToken'] as String}));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    final streamClosed = response.drain<void>();
    final pending =
        harness.post(MiuCamProtocolV2.sessionStart, second.token, const {});
    await entered.future.timeout(const Duration(seconds: 2));
    harness.elapsedMs = 150;
    await streamClosed.timeout(const Duration(seconds: 1));
    expect(finish.isCompleted, isFalse,
        reason: 'A native operation must not extend other viewers’ trial.');
    finish.complete();
    await pending;
  });

  for (final path in [MiuCamProtocolV2.video, MiuCamProtocolV2.audio]) {
    test('late capture startup cannot attach $path after trial expiry',
        () async {
      final source = _MediaSource();
      final entered = Completer<void>();
      final finish = Completer<void>();
      source.captureEntered = entered;
      source.blockCapture = finish.future;
      final harness = await _Harness.start(
        freeLimit: const Duration(milliseconds: 100),
        mediaSource: source,
      );
      addTearDown(() async {
        if (!finish.isCompleted) finish.complete();
        await harness.close();
      });
      final trusted = harness.tokens
          .issueTrustedClientToken(clientName: 'Parent', deviceId: 'parent');
      final start = await harness
          .post(MiuCamProtocolV2.sessionStart, trusted.token, const {});
      final request = await harness.http.getUrl(harness
          .url(path, {'streamToken': start.body['streamToken'] as String}));
      final response = request.close();
      await entered.future.timeout(const Duration(seconds: 2));
      harness.elapsedMs = 100;
      await _waitUntil(() => harness.stopped.contains(trusted.clientId));
      finish.complete();
      final rejected = await response.timeout(const Duration(seconds: 1));
      expect(rejected.statusCode,
          anyOf(HttpStatus.unauthorized, HttpStatus.paymentRequired));
      await rejected.drain<void>();
      expect(harness.server.activeWatchClientIds, isEmpty);
    });
  }

  test('expiry retires runtime when exact WebRTC peer close fails', () async {
    final harness =
        await _Harness.start(freeLimit: const Duration(milliseconds: 100));
    addTearDown(harness.close);
    harness.gateway.failExactClose = true;
    final trusted = harness.tokens
        .issueTrustedClientToken(clientName: 'Parent', deviceId: 'parent');
    final start = await harness.post(
        MiuCamProtocolV2.sessionStart,
        trusted.token,
        const {'mediaTransport': 'webrtc', 'video': true, 'audio': true});
    final offer =
        await harness.post(MiuCamProtocolV2.webRtcOffer, trusted.token, {
      'offer': {'type': 'offer', 'sdp': 'v=0\r\n'}
    }, query: {
      'streamToken': start.body['streamToken'] as String
    });
    expect(offer.status, HttpStatus.ok);
    harness.elapsedMs = 100;
    await _waitUntil(() => harness.stopped.contains(trusted.clientId));
    expect(harness.gateway.activePeerCount, 0);
    expect(harness.gateway.fallbackClosed, contains(trusted.clientId));
    expect(harness.server.activeWatchClientIds.length, 0);
  });

  test(
      'trusted lifetime restore reopens room broadcasting while preserving five viewer cap',
      () async {
    final harness = await _Harness.start(usedMs: 1000);
    addTearDown(harness.close);
    final clients = List.generate(
        6,
        (i) => harness.tokens
            .issueTrustedClientToken(clientName: 'Parent $i', deviceId: '$i'));
    expect(
        (await harness.post(
                MiuCamProtocolV2.sessionStart, clients.first.token, const {}))
            .status,
        HttpStatus.paymentRequired);
    expect((await harness.access.restorePurchase()).unlocked, isTrue);
    for (final trusted in clients.take(5)) {
      final start = await harness
          .post(MiuCamProtocolV2.sessionStart, trusted.token, const {});
      expect(start.status, HttpStatus.ok);
      expect((start.body['broadcastAccess'] as Map)['unlocked'], isTrue);
    }
    expect(
        (await harness.post(
                MiuCamProtocolV2.sessionStart, clients.last.token, const {}))
            .status,
        HttpStatus.tooManyRequests);
    expect(harness.server.activeWatchClientIds.length, 5);
  });
}

class _Harness {
  final http = HttpClient();
  final tokens = PairingTokenService(maxTrustedClients: 6);
  final gateway = _Gateway();
  final alertStarted = <String>[];
  final alertStopped = <String>[];
  final stopped = <String>[];
  late final BroadcastAccessService access;
  late final MiuCamServer server;
  late final int port;
  int elapsedMs = 0;

  static Future<_Harness> start(
      {int usedMs = 0,
      Duration freeLimit = const Duration(seconds: 1),
      Future<void> Function(String clientId)? streamStart,
      ServerMediaSource? mediaSource,
      bool blockFinalMediaSnapshot = false}) async {
    SharedPreferences.setMockInitialValues({
      'broadcast_access.used_ms': usedMs,
      'config.webrtc_pilot_enabled': true
    });
    final prefs = await SharedPreferences.getInstance();
    final harness = _Harness();
    harness.access = blockFinalMediaSnapshot
        ? _BlockingSnapshotAccess(prefs, () => harness.elapsedMs)
        : BroadcastAccessService(prefs,
            freeLimit: freeLimit,
            purchaseGateway: _PurchaseGateway(),
            monotonicNowMs: () => harness.elapsedMs);
    harness.server = MiuCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: harness.tokens,
      httpPort: 0,
      startMediaOnSessionStart: false,
      mediaSource: mediaSource ?? _MediaSource(),
      webRtcGateway: harness.gateway,
      webRtcCleanupTimeout: const Duration(milliseconds: 30),
      broadcastAccess: harness.access,
      onStreamSessionStarted: (clientId,
          {required video, required audio, required mediaTransport}) async {
        await streamStart?.call(clientId);
      },
      onStreamSessionStopped: harness.stopped.add,
      onAlertClientConnected: harness.alertStarted.add,
      onAlertClientDisconnected: harness.alertStopped.add,
    );
    harness.port = Uri.parse(await harness.server.startPairingMode()).port;
    return harness;
  }

  Uri url(String path, [Map<String, String>? query]) => Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: path,
      queryParameters: query);

  Future<({int status, Map<String, dynamic> body})> post(
      String path, String bearer, Map<String, Object?> body,
      {Map<String, String>? query}) async {
    final request = await http.postUrl(url(path, query));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $bearer')
      ..contentType = ContentType.json;
    request.write(jsonEncode({
      if (path == MiuCamProtocolV2.sessionStart)
        MiuCamProtocolV2.streamAttemptId: 'broadcast-test',
      ...body,
    }));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (
      status: response.statusCode,
      body: text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>
    );
  }

  Future<void> close() async {
    http.close(force: true);
    await server.dispose();
    await access.dispose();
  }
}

class _Gateway implements WebRtcServerGateway {
  final peers = <String, String>{};
  final fallbackClosed = <String>[];
  bool failExactClose = false;
  Completer<void>? offerEntered;
  Future<void>? blockOffer;
  @override
  bool get isAvailable => true;
  @override
  int get activePeerCount => peers.length;
  @override
  Future<bool> initialize() async => true;
  @override
  Future<WebRtcOfferResponse> acceptOffer(
      {required String clientId, required WebRtcOfferRequest request}) async {
    if (offerEntered?.isCompleted == false) offerEntered!.complete();
    await blockOffer;
    final id = 'peer-$clientId';
    peers[id] = clientId;
    return WebRtcOfferResponse(
        peerId: id,
        answer: const WebRtcSignalDescription(type: 'answer', sdp: 'v=0\r\n'));
  }

  @override
  Future<void> addRemoteCandidate(
      {required String clientId,
      required String peerId,
      required WebRtcIceCandidateSignal candidate}) async {}
  @override
  List<WebRtcIceCandidateSignal> drainLocalCandidates(
          {required String clientId, required String peerId}) =>
      [];
  @override
  Future<void> closePeer(
      {required String clientId, required String peerId}) async {
    if (failExactClose) throw StateError('Native peer close failed');
    peers.remove(peerId);
  }

  @override
  Future<void> closeClient(String clientId) async {
    peers.removeWhere((_, owner) => owner == clientId);
    fallbackClosed.add(clientId);
  }

  @override
  Future<void> dispose() async {
    peers.clear();
  }
}

class _PurchaseGateway implements BroadcastPurchaseGateway {
  @override
  Future<BroadcastPurchaseResult> purchase(
          {required String productId, required String priceLabel}) =>
      restore(productId: productId);
  @override
  Future<BroadcastPurchaseResult> restore({required String productId}) async =>
      BroadcastPurchaseResult(
          status: BroadcastPurchaseStatus.restored,
          verified: true,
          verificationSource: 'google_play',
          verificationFingerprint: 'f' * 64,
          entitlementId: 'room-test');
  @override
  Future<void> dispose() async {}
}

class _MediaSource extends ServerMediaSource {
  Completer<void>? captureEntered;
  Future<void>? blockCapture;
  ServerVideoFrameSink? videoSink;
  ServerAudioChunkSink? audioSink;

  void emit() {
    videoSink?.call(Uint8List.fromList([255, 216, 255, 217]));
    audioSink?.call(Uint8List(320));
  }

  @override
  bool get isActive => true;
  @override
  ServerMediaSourceSnapshot get snapshot => const ServerMediaSourceSnapshot(
      active: true,
      videoFrames: 0,
      audioChunks: 0,
      lastVideoFrameAtMs: null,
      lastVideoFrameBytes: 0,
      lastAudioChunkAtMs: null,
      lastAudioChunkBytes: 0,
      lastError: null);
  @override
  Future<void> reconcile(
      {required bool video,
      required bool audio,
      required ServerVideoFrameSink onVideoFrame,
      required ServerAudioChunkSink onAudioChunk,
      ServerMediaErrorSink? onError}) async {
    videoSink = onVideoFrame;
    audioSink = onAudioChunk;
    if (video || audio) {
      if (captureEntered?.isCompleted == false) captureEntered!.complete();
      await blockCapture;
    }
  }

  @override
  Future<void> stop() async {}
  @override
  void resetDiagnostics() {}
}

class _BlockingSnapshotAccess extends BroadcastAccessService {
  _BlockingSnapshotAccess(super.preferences, int Function() monotonicNowMs)
      : super(
            purchaseGateway: _PurchaseGateway(),
            monotonicNowMs: monotonicNowMs,
            freeLimit: const Duration(seconds: 1));
  final entered = Completer<void>();
  final release = Completer<void>();
  var calls = 0;

  @override
  Future<BroadcastAccessSnapshot> snapshot() async {
    final current = await super.snapshot();
    if (++calls == 3) {
      entered.complete();
      await release.future;
    }
    return current;
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}
