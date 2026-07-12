import 'dart:convert';
import 'dart:async';
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

  test('eşzamanlı pairing start işlemleri tek mutation kuyruğunda çalışır',
      () async {
    final firstStart = Completer<void>();
    var starts = 0;
    final runtime = ServerRuntime(
      mediaRuntime: MediaRuntimeController(),
      onStartPairing: () async {
        starts++;
        if (starts == 1) await firstStart.future;
        return 'mimicam://pair?payload=$starts';
      },
    );
    addTearDown(runtime.dispose);

    final first = runtime.startPairingMode();
    final second = runtime.startPairingMode();
    await Future<void>.delayed(Duration.zero);

    expect(starts, 1);
    firstStart.complete();
    await Future.wait([first, second]);

    expect(starts, 2);
    expect(runtime.currentState.phase, ServerRuntimePhase.pairingActive);
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
    expect(capabilities.containsKey('freeBroadcastLimitMs'), isFalse);
    expect(capabilities.containsKey('oneTimeUnlockPrice'), isFalse);
    expect(capabilities.containsKey('oneTimeUnlockProductId'), isFalse);

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

  test('MimiCamServer eşzamanlı pairing start için tek bind paylaşır',
      () async {
    final server = await _testServer();
    addTearDown(server.dispose);

    final urls = await Future.wait([
      server.startPairingMode(),
      server.startPairingMode(),
    ]);

    expect(urls[0], urls[1]);
    expect(Uri.parse(urls[0]).port, greaterThan(0));
  });

  test('ikinci server aynı production portunu paylaşamaz', () async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();

    final first = await _testServer(httpPort: port);
    final second = await _testServer(httpPort: port);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.startPairingMode();

    await expectLater(
      second.startPairingMode(),
      throwsA(isA<SocketException>()),
    );
  });
}

Future<MimiCamServer> _testServer({int httpPort = 0}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return MimiCamServer(
    config: ConfigurationService(preferences),
    strings: AppStrings(const Locale('tr')),
    onLog: (_) {},
    onAlert: (_) {},
    httpPort: httpPort,
    startMediaOnSessionStart: false,
  );
}
