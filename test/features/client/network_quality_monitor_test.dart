import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/adaptive_media_profile.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/features/client/media/client_stream_health_state.dart';
import 'package:miucam/features/client/media/network_quality_monitor.dart';

void main() {
  test('timed out status polls close old sockets before the next poll',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>{};
    var maximumOpenSockets = 0;
    var requests = 0;
    server.listen((socket) {
      sockets.add(socket);
      maximumOpenSockets = maximumOpenSockets < sockets.length
          ? sockets.length
          : maximumOpenSockets;
      var receivedHeaders = false;
      var data = '';
      socket.listen((chunk) {
        data += utf8.decode(chunk);
        if (!receivedHeaders && data.contains('\r\n\r\n')) {
          receivedHeaders = true;
          requests++;
          // Keep the TCP connection alive without answering HTTP headers.
        }
      }, onDone: () {
        sockets.remove(socket);
        socket.destroy();
      });
    });
    addTearDown(() async {
      for (final socket in sockets.toList()) {
        socket.destroy();
      }
      await server.close();
    });
    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(milliseconds: 30),
      timeout: const Duration(milliseconds: 80),
    );

    final updates = await monitor.watch(_session(server.port)).take(3).toList();

    expect(updates.map((update) => update.snapshot.consecutiveFailures),
        [1, 2, 3]);
    expect(requests, 3);
    expect(maximumOpenSockets, 1,
        reason: 'A timeout must terminate its pending request, not leave it '
            'alive alongside every later status poll.');
  });

  test('NetworkQualityMonitor status ölçer ve kalite raporunu servera yollar',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var reportReceived = false;

    server.listen((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer token',
      );
      if (request.uri.path == MiuCamProtocolV2.status) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'mediaProfile':
              MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.balanced)
                  .toJson(),
        }));
        await request.response.close();
        return;
      }
      if (request.uri.path == MiuCamProtocolV2.qualityReport) {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body, isA<Map>());
        expect((body as Map)['tier'], isNotEmpty);
        reportReceived = true;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'ok': true,
          'mediaProfile':
              MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.legacy)
                  .adaptForNetwork(NetworkQualityTier.weak)
                  .toJson(),
        }));
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(minutes: 1),
      timeout: const Duration(seconds: 2),
    );
    final update = await monitor.watch(_session(server.port)).first;

    expect(reportReceived, isTrue);
    expect(update.snapshot.tier, NetworkQualityTier.excellent);
    expect(update.serverProfile?.audioFirst, isTrue);
  });

  test('polling recovers after a timeout and reuses healthy connections',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final clientPorts = <int>[];
    server.listen((request) async {
      clientPorts.add(request.connectionInfo!.remotePort);
      if (clientPorts.length == 1) return;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true}));
      await request.response.close();
    });
    final monitor = NetworkQualityMonitor(
      healthState: ClientStreamHealthState(),
      pollInterval: const Duration(milliseconds: 10),
      timeout: const Duration(milliseconds: 200),
    );

    final updates = await monitor.watch(_session(server.port)).take(3).toList();

    expect(updates.map((update) => update.snapshot.consecutiveFailures),
        [1, 0, 0]);
    expect(clientPorts, hasLength(3));
    expect(clientPorts[0], isNot(clientPorts[1]));
    expect(clientPorts[1], clientPorts[2],
        reason: 'Successful status polls retain their keep-alive socket.');
  });

  test('RTT iyi olsa bile video frame gap 5s ise critical rapor gönderir',
      () async {
    var nowMs = 1000;
    final health = ClientStreamHealthState(nowMs: () => nowMs)
      ..resetForNewWatchSession()
      ..markVideoFrameReceived();
    nowMs += 5000;
    final captured = <Map<String, Object?>>[];
    final server = await _qualityServer(captured);
    addTearDown(() => server.close(force: true));

    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(minutes: 1),
      timeout: const Duration(seconds: 2),
      healthState: health,
    );
    final update = await monitor.watch(_session(server.port)).first;

    expect(update.snapshot.tier, NetworkQualityTier.critical);
    expect(captured.single['networkTier'], NetworkQualityTier.critical.name);
    expect(captured.single['videoFrameGapMs'], 5000);
    expect(captured.single['streamTimedOut'], isTrue);
  });

  test('audio underrun critical rapor gönderir', () async {
    var nowMs = 1000;
    final health = ClientStreamHealthState(nowMs: () => nowMs)
      ..resetForNewWatchSession()
      ..markAudioChunkReceived()
      ..updateAudioPipelineStatus({
        'networkBytesReceived': 128,
        'pcmChunksParsed': 2,
        'nativeBytesWritten': 64,
      });
    nowMs += 1500;
    final captured = <Map<String, Object?>>[];
    final server = await _qualityServer(captured);
    addTearDown(() => server.close(force: true));

    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(minutes: 1),
      timeout: const Duration(seconds: 2),
      healthState: health,
    );
    final update = await monitor.watch(_session(server.port)).first;

    expect(update.snapshot.tier, NetworkQualityTier.critical);
    expect(captured.single['audioUnderrun'], isTrue);
    expect(captured.single['audioPipeline'], {
      'networkBytesReceived': 128,
      'pcmChunksParsed': 2,
      'nativeBytesWritten': 64,
    });
  });

  test('ws disconnect en az weak rapor gönderir', () async {
    final health = ClientStreamHealthState(nowMs: () => 1000)
      ..resetForNewWatchSession()
      ..markWsDisconnected();
    final captured = <Map<String, Object?>>[];
    final server = await _qualityServer(captured);
    addTearDown(() => server.close(force: true));

    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(minutes: 1),
      timeout: const Duration(seconds: 2),
      healthState: health,
    );
    final update = await monitor.watch(_session(server.port)).first;

    expect(update.snapshot.tier, NetworkQualityTier.weak);
    expect(captured.single['wsDisconnectCount'], 1);
  });

  test('watch aktif değilken iyi ağda quality report göndermez', () async {
    final health = ClientStreamHealthState(nowMs: () => 1000);
    final captured = <Map<String, Object?>>[];
    final server = await _qualityServer(captured);
    addTearDown(() => server.close(force: true));

    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(minutes: 1),
      timeout: const Duration(seconds: 2),
      healthState: health,
    );
    final update = await monitor.watch(_session(server.port)).first;

    expect(update.snapshot.tier, NetworkQualityTier.excellent);
    expect(captured, isEmpty);
  });

  test('client olusturulamiyorsa stream hata yerine offline snapshot verir',
      () async {
    final monitor = NetworkQualityMonitor(
      clientFactory: (_) => throw UnsupportedError('web HttpClient yok'),
    );

    final update = await monitor.watch(_session(8080)).first;

    expect(update.snapshot.tier, NetworkQualityTier.unknown);
    expect(update.snapshot.consecutiveFailures, 1);
  });

  test('aktif watch ayni kalite seviyesinde quality POSTlarini throttle eder',
      () async {
    final health = ClientStreamHealthState(nowMs: () => 1000)
      ..setWatchActive(true);
    var statusRequests = 0;
    var reportRequests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == MiuCamProtocolV2.status) {
        statusRequests++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
      } else if (request.uri.path == MiuCamProtocolV2.qualityReport) {
        reportRequests++;
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final monitor = NetworkQualityMonitor(
      healthState: health,
      livePollInterval: const Duration(milliseconds: 5),
      qualityReportInterval: const Duration(hours: 1),
      timeout: const Duration(seconds: 2),
    );

    final updates = await monitor.watch(_session(server.port)).take(3).toList();

    expect(updates, hasLength(3));
    expect(statusRequests, 3);
    expect(reportRequests, 1);
  });

  test('kalite seviyesi kotulesince throttle beklemeden rapor yollar',
      () async {
    final health = ClientStreamHealthState(nowMs: () => 1000)
      ..setWatchActive(true);
    final captured = <Map<String, Object?>>[];
    final server = await _qualityServer(captured);
    addTearDown(() => server.close(force: true));
    final monitor = NetworkQualityMonitor(
      healthState: health,
      livePollInterval: const Duration(milliseconds: 5),
      qualityReportInterval: const Duration(hours: 1),
      timeout: const Duration(seconds: 2),
    );
    final iterator = StreamIterator(monitor.watch(_session(server.port)));
    addTearDown(iterator.cancel);

    expect(await iterator.moveNext(), isTrue);
    health.markWsDisconnected();
    expect(await iterator.moveNext(), isTrue);

    expect(captured, hasLength(2));
    expect(captured.last['networkTier'], NetworkQualityTier.weak.name);
  });
}

Future<HttpServer> _qualityServer(List<Map<String, Object?>> captured) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == MiuCamProtocolV2.status) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'mediaProfile':
            MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.balanced)
                .toJson(),
      }));
      await request.response.close();
      return;
    }
    if (request.uri.path == MiuCamProtocolV2.qualityReport) {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      captured.add(Map<String, Object?>.from(body as Map));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ok': true,
        'mediaProfile':
            MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.legacy)
                .adaptForNetwork(NetworkQualityTier.weak)
                .toJson(),
      }));
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  });
  return server;
}

PairingSession _session(int port) => PairingSession(
      payload: PairingPayload(
        schemaVersion: MiuCamProtocolV2.schemaVersion,
        host: InternetAddress.loopbackIPv4.address,
        port: port,
        deviceId: 'server',
        deviceName: 'Bebek Odası',
        pairingNonce: 'nonce',
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        capabilities: const {'transport': 'http'},
      ),
      sessionToken: 'token',
    );
