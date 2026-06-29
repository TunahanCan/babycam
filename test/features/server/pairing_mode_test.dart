import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/features/server/media/media_runtime_controller.dart';
import 'package:mimicam/features/server/server_runtime.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:mimicam/services/mimicam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('pairing mode kamera önizlemesini otomatik başlatmaz', () async {
    var mediaStarts = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(onStart: () async => mediaStarts++),
      onStartPairing: () async => 'mimicam://pair?payload=x',
    );

    await runtime.startPairingMode();

    expect(runtime.currentState.phase, ServerRuntimePhase.pairingActive);
    expect(runtime.currentState.cameraActive, isFalse);
    expect(runtime.currentState.microphoneActive, isFalse);
    expect(mediaStarts, 0);
  });

  test('public pairing status sadece HTTP/WS QR bilgisi döner', () async {
    final server = await _testServer();
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final request = await client.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: base.port,
      path: MimiCamProtocolV2.statusPublic,
    ));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    final json = jsonDecode(body) as Map;

    expect(response.statusCode, HttpStatus.ok);
    expect(json['pairing'], isTrue);
    expect(json['pairingNonce'], isNotEmpty);
    expect(json['transport'], 'http_ws');
    expect(json.containsKey('certificateFingerprintSha256'), isFalse);
    final capabilities = Map<String, Object?>.from(json['capabilities'] as Map);
    expect(capabilities['transportPreferred'], 'http_ws');
    expect(capabilities['video'], 'mjpeg');
    expect(capabilities['videoPreferred'], 'mjpeg');
    expect(capabilities['audio'], 'pcm16le');
    expect(capabilities['audioPreferred'], 'pcm16le');

    server.stopPairingMode();
    final inactiveRequest = await client.getUrl(Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: base.port,
      path: MimiCamProtocolV2.statusPublic,
    ));
    final inactiveResponse = await inactiveRequest.close();
    await inactiveResponse.drain<void>();

    expect(inactiveResponse.statusCode, HttpStatus.notFound);
  });
}

Future<MimiCamServer> _testServer() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return MimiCamServer(
    config: ConfigurationService(preferences),
    strings: AppStrings(const Locale('tr')),
    onLog: (_) {},
    onAlert: (_) {},
    httpPort: 0,
    startMediaOnSessionStart: false,
  );
}
