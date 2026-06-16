import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
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
