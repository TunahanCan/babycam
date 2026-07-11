// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/features/server/pairing/server_qr_payload_builder.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:mimicam/services/mimicam_server.dart';
import 'package:mimicam/services/network_address_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Starts the production MimiCam HTTP/WebSocket server in Flutter's headless
/// test engine. Camera and microphone runtimes are deliberately never started.
///
/// Physical-device mode (keeps running until Ctrl+C):
///   flutter test --no-pub tool/notification_e2e_server.dart
///
/// Automated transport self-test (starts, posts one alert, then exits):
///   flutter test --no-pub \
///     --dart-define=MIMICAM_NOTIFICATION_E2E_ONESHOT=true \
///     tool/notification_e2e_server.dart
void main() {
  _NotificationE2EBinding();

  test(
    'headless MimiCam notification verification server',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final tokenService = PairingTokenService();
      final controller = tokenService.issueTrustedClientToken(
        clientName: 'Notification E2E Controller',
        deviceId: 'notification_e2e_controller',
      );
      final configuredPort = int.tryParse(const String.fromEnvironment(
            'MIMICAM_NOTIFICATION_E2E_PORT',
            defaultValue: '0',
          )) ??
          0;
      final server = MimiCamServer(
        config: ConfigurationService(preferences),
        strings: AppStrings(const Locale('tr')),
        onLog: (message) => print('MIMICAM_SERVER_LOG $message'),
        onAlert: (message) => print('MIMICAM_SERVER_ALERT $message'),
        tokenService: tokenService,
        serverDeviceIdProvider: () async => 'notification_e2e_server',
        httpPort: configuredPort,
        startMediaOnSessionStart: false,
      );
      addTearDown(server.dispose);

      final advertisedUrl = Uri.parse(await server.startPairingMode());
      final port = advertisedUrl.port;
      final candidates = await _lanAuthorities(port);
      final primaryAuthority = advertisedUrl.authority;
      final pairAuthorities = <String>{
        primaryAuthority,
        ...candidates,
      }.toList(growable: false);
      final baseUri = advertisedUrl.replace(path: '/', query: null);
      final configuredMarker = const String.fromEnvironment(
        'MIMICAM_NOTIFICATION_E2E_MARKER',
      ).trim();
      final marker = configuredMarker.isEmpty
          ? 'MIMICAM-E2E-${DateTime.now().millisecondsSinceEpoch}'
          : configuredMarker;
      final pairingUri = ServerQrPayloadBuilder(
        tokenService: tokenService,
        deviceId: 'notification_e2e_server',
        deviceName: 'MimiCam Bildirim Testi',
      )
          .build(
            host: advertisedUrl.host,
            port: port,
            ttl: const Duration(hours: 1),
            capabilities: server.mediaCapabilities,
          )
          .toUriString();
      final alertUri = baseUri.resolve(MimiCamProtocolV2.testAlert);

      final ready = <String, Object?>{
        'pairAddress': primaryAuthority,
        'pairAddressAlternatives': pairAuthorities,
        'baseUrl': baseUri.toString(),
        'pairingUri': pairingUri,
        'controllerClientId': controller.clientId,
        'controllerBearerToken': controller.token,
        'controllerTokenExpiresAtMs': controller.expiresAtMs,
        'testAlertUrl': alertUri.toString(),
        'testMarker': marker,
        'mediaRuntimeStarted': false,
      };
      print('MIMICAM_NOTIFICATION_E2E_READY ${jsonEncode(ready)}');
      print('PAIR_ADDRESS $primaryAuthority');
      for (final alternative in pairAuthorities.skip(1)) {
        print('PAIR_ADDRESS_ALTERNATIVE $alternative');
      }
      print('PAIRING_URI $pairingUri');
      print('CONTROL_BEARER_TOKEN ${controller.token}');
      print(
        "TRIGGER_ALERT curl -fsS -X POST '$alertUri' "
        "-H 'Authorization: Bearer ${controller.token}' "
        "-H 'Content-Type: application/json' "
        "--data-binary '${jsonEncode({'message': marker})}'",
      );

      if (const bool.fromEnvironment(
        'MIMICAM_NOTIFICATION_E2E_ONESHOT',
      )) {
        final result = await _runTransportSelfTest(
          port: port,
          controllerToken: controller.token,
          marker: marker,
        );
        print('MIMICAM_NOTIFICATION_E2E_SELF_TEST ${jsonEncode(result)}');
        expect(result['ok'], isTrue, reason: jsonEncode(result));
        return;
      }

      print(
        'WAITING_FOR_PHYSICAL_CLIENT Pair the Android Client with '
        '$primaryAuthority, then run TRIGGER_ALERT in another terminal. '
        'Press Ctrl+C when verification is complete.',
      );
      await Completer<void>().future;
    },
    timeout: Timeout.none,
  );
}

class _NotificationE2EBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

Future<List<String>> _lanAuthorities(int port) async {
  final interfaces = await NetworkInterface.list(includeLoopback: false);
  final candidates = <NetworkAddressCandidate>[
    for (final interface in interfaces)
      for (final address in interface.addresses)
        NetworkAddressCandidate(
          interfaceName: interface.name,
          address: address.address,
        ),
  ];
  return NetworkAddressProvider.rankedLocalEndpoints(
    candidates,
    port: port,
  ).map((endpoint) => endpoint.authority).toList(growable: false);
}

Future<Map<String, Object?>> _runTransportSelfTest({
  required int port,
  required String controllerToken,
  required String marker,
}) async {
  final socket = await WebSocket.connect(
    Uri(
      scheme: 'ws',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: MimiCamProtocolV2.events,
    ).toString(),
    headers: {
      HttpHeaders.authorizationHeader: 'Bearer $controllerToken',
    },
  ).timeout(const Duration(seconds: 5));
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final eventFuture = socket.first.timeout(const Duration(seconds: 5));
    final response = await _postAlert(
      client,
      port: port,
      controllerToken: controllerToken,
      marker: marker,
    );
    final rawEvent = await eventFuture;
    final event = rawEvent is String ? jsonDecode(rawEvent) : null;
    final delivered = (response['deliveredWebSocketClients'] as num?)?.toInt();
    final eventMessage = event is Map ? event['message']?.toString() : null;
    final eventId = event is Map ? event['id']?.toString() : null;
    return {
      'ok': response['ok'] == true &&
          delivered != null &&
          delivered >= 1 &&
          eventMessage == marker,
      'httpOk': response['ok'] == true,
      'deliveredWebSocketClients': delivered,
      'eventId': eventId,
      'eventMessage': eventMessage,
      'marker': marker,
    };
  } finally {
    client.close(force: true);
    await socket.close();
  }
}

Future<Map<String, Object?>> _postAlert(
  HttpClient client, {
  required int port,
  required String controllerToken,
  required String marker,
}) async {
  final uri = Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: port,
    path: MimiCamProtocolV2.testAlert,
  );
  final request = await client.postUrl(uri).timeout(const Duration(seconds: 5));
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $controllerToken');
  request.write(jsonEncode({'message': marker}));
  final response = await request.close().timeout(const Duration(seconds: 5));
  final body = await utf8.decoder
      .bind(response)
      .join()
      .timeout(const Duration(seconds: 5));
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException(
      '/test/alert returned HTTP ${response.statusCode}: $body',
      uri: uri,
    );
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map) throw const FormatException('Expected JSON object.');
  return Map<String, Object?>.from(decoded);
}
