import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/features/client/media/client_stream_health_monitor.dart';
import 'package:mimicam/features/client/media/network_quality_monitor.dart';

void main() {
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
      if (request.uri.path == MimiCamProtocolV2.status) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'mediaProfile':
              MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.balanced)
                  .toJson(),
        }));
        await request.response.close();
        return;
      }
      if (request.uri.path == MimiCamProtocolV2.qualityReport) {
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

  test('RTT iyi olsa bile video frame gap 5s ise critical rapor gönderir',
      () async {
    var nowMs = 1000;
    final health = ClientStreamHealthMonitor(nowMs: () => nowMs)
      ..resetForNewWatchSession()
      ..markVideoFrameReceived();
    nowMs += 5000;
    final captured = <Map<String, Object?>>[];
    final server = await _qualityServer(captured);
    addTearDown(() => server.close(force: true));

    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(minutes: 1),
      timeout: const Duration(seconds: 2),
      healthMonitor: health,
    );
    final update = await monitor.watch(_session(server.port)).first;

    expect(update.snapshot.tier, NetworkQualityTier.critical);
    expect(captured.single['networkTier'], NetworkQualityTier.critical.name);
    expect(captured.single['videoFrameGapMs'], 5000);
    expect(captured.single['streamTimedOut'], isTrue);
  });

  test('audio underrun critical rapor gönderir', () async {
    var nowMs = 1000;
    final health = ClientStreamHealthMonitor(nowMs: () => nowMs)
      ..resetForNewWatchSession()
      ..markAudioChunkReceived();
    nowMs += 1500;
    final captured = <Map<String, Object?>>[];
    final server = await _qualityServer(captured);
    addTearDown(() => server.close(force: true));

    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(minutes: 1),
      timeout: const Duration(seconds: 2),
      healthMonitor: health,
    );
    final update = await monitor.watch(_session(server.port)).first;

    expect(update.snapshot.tier, NetworkQualityTier.critical);
    expect(captured.single['audioUnderrun'], isTrue);
  });

  test('ws disconnect en az weak rapor gönderir', () async {
    final health = ClientStreamHealthMonitor(nowMs: () => 1000)
      ..resetForNewWatchSession()
      ..markWsDisconnected();
    final captured = <Map<String, Object?>>[];
    final server = await _qualityServer(captured);
    addTearDown(() => server.close(force: true));

    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(minutes: 1),
      timeout: const Duration(seconds: 2),
      healthMonitor: health,
    );
    final update = await monitor.watch(_session(server.port)).first;

    expect(update.snapshot.tier, NetworkQualityTier.weak);
    expect(captured.single['wsDisconnectCount'], 1);
  });

  test('watch aktif değilken iyi ağda quality report göndermez', () async {
    final health = ClientStreamHealthMonitor(nowMs: () => 1000);
    final captured = <Map<String, Object?>>[];
    final server = await _qualityServer(captured);
    addTearDown(() => server.close(force: true));

    final monitor = NetworkQualityMonitor(
      pollInterval: const Duration(minutes: 1),
      timeout: const Duration(seconds: 2),
      healthMonitor: health,
    );
    final update = await monitor.watch(_session(server.port)).first;

    expect(update.snapshot.tier, NetworkQualityTier.excellent);
    expect(captured, isEmpty);
  });
}

Future<HttpServer> _qualityServer(List<Map<String, Object?>> captured) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == MimiCamProtocolV2.status) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'mediaProfile':
            MediaQualityProfile.forDeviceTier(DeviceCapabilityTier.balanced)
                .toJson(),
      }));
      await request.response.close();
      return;
    }
    if (request.uri.path == MimiCamProtocolV2.qualityReport) {
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
        schemaVersion: MimiCamProtocolV2.schemaVersion,
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
