import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/features/server/pairing/pairing_token_service.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:miucam/services/miucam_server.dart';
import 'package:miucam/services/server/baby_monitor_feature_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final reopen in [false, true]) {
    test(
        'closing pairing rejects an already admitted slow body (reopen=$reopen)',
        () async {
      final tokens = _ObservedTokens();
      final server = await _server(tokens);
      addTearDown(server.dispose);
      final base = Uri.parse(await server.startPairingMode());
      final nonce = tokens.createPairingNonce();
      final admitted = Completer<void>();
      tokens.pairAdmitted = admitted;
      final pending = await _slowPost(base.port, MiuCamProtocolV2.pairConfirm, {
        'pairingNonce': nonce,
        'deviceId': 'new-parent',
        'clientName': 'Parent',
      });
      addTearDown(pending.socket.destroy);
      await admitted.future.timeout(const Duration(seconds: 2));

      await server.stopPairingMode();
      if (reopen) await server.startPairingMode();
      pending.socket.add(pending.remainingBody);
      await pending.socket.flush();
      final response =
          await pending.response.timeout(const Duration(seconds: 2));

      expect(response, startsWith('HTTP/1.1 404'));
      expect(response, contains('PAIRING_NOT_ACTIVE'));
      expect(tokens.pairedClientCount, 0);
      expect(tokens.isPairingNonceActive(nonce), isFalse);
    });
  }

  for (final path in [
    MiuCamProtocolV2.comfortCommand,
    MiuCamProtocolV2.nightLightCommand,
    MiuCamProtocolV2.talkStart,
    MiuCamProtocolV2.talkStop,
  ]) {
    test('revocation during a slow $path body prevents the command', () async {
      final tokens = _ObservedTokens();
      final features = BabyMonitorFeatureController();
      final server = await _server(tokens, features: features);
      addTearDown(server.dispose);
      final base = Uri.parse(await server.startPairingMode());
      final token = await tokens.issueTrustedClientTokenPersisted(
          clientName: 'Parent', deviceId: 'parent');
      final admitted = Completer<void>();
      tokens.authAdmitted = admitted;
      final pending = await _slowPost(
          base.port,
          path,
          {
            'action':
                path == MiuCamProtocolV2.nightLightCommand ? 'on' : 'play',
            'mode': 'screenGlow',
            'trackId': 'rain',
            'talkAttemptId': 'slow-attempt',
          },
          token: token.token);
      addTearDown(pending.socket.destroy);
      await admitted.future.timeout(const Duration(seconds: 2));

      await server.revokeTrustedClient(token.clientId);
      pending.socket.add(pending.remainingBody);
      await pending.socket.flush();
      final response =
          await pending.response.timeout(const Duration(seconds: 2));

      expect(response, startsWith('HTTP/1.1 401'));
      expect(features.comfortAudio.state.playing, isFalse);
      expect(features.nightLight.state.enabled, isFalse);
      expect(features.talkSessions.activeSession, isNull);
    });
  }

  test('pairing closed during persistence cannot publish a late trusted token',
      () async {
    final repository = _GatedRepository();
    final tokens = PairingTokenService(trustedClientRepository: repository);
    final server = await _server(tokens);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.postUrl(Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: base.port,
      path: MiuCamProtocolV2.pairConfirm,
    ));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'pairingNonce': tokens.createPairingNonce(),
      'deviceId': 'pending-parent',
      'clientName': 'Parent',
    }));
    final responseFuture = request.close();
    await repository.started.future.timeout(const Duration(seconds: 2));

    await server.stopPairingMode();
    await server.startPairingMode();
    repository.release.complete();
    final response = await responseFuture.timeout(const Duration(seconds: 2));
    final body = await utf8.decoder.bind(response).join();

    expect(response.statusCode, HttpStatus.notFound);
    expect(body, isNot(contains('trustedClientToken')));
    expect(tokens.pairedClientCount, 0);
    expect(repository.records.single.revoked, isTrue);
    final restarted = PairingTokenService(trustedClientRepository: repository);
    addTearDown(restarted.dispose);
    expect(restarted.pairedClientCount, 0);
  });

  test('public status polls preserve the QR displayed on the room device',
      () async {
    final tokens = PairingTokenService(maxActiveNonces: 1);
    final server = await _server(tokens);
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final qrNonce = tokens.createPairingNonce();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final publicNonces = <String>{};
    for (var index = 0; index < 4; index++) {
      final request = await client.getUrl(Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: base.port,
        path: MiuCamProtocolV2.statusPublic,
      ));
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      publicNonces.add(body['pairingNonce'] as String);
    }

    expect(publicNonces, hasLength(1));
    expect(tokens.validateAndConsumeNonce(qrNonce), isTrue);
  });
}

Future<MiuCamServer> _server(PairingTokenService tokens,
    {BabyMonitorFeatureController? features}) async {
  SharedPreferences.setMockInitialValues({});
  return MiuCamServer(
    config: ConfigurationService(await SharedPreferences.getInstance()),
    strings: AppStrings(const Locale('en')),
    onLog: (_) {},
    onAlert: (_) {},
    tokenService: tokens,
    featureController: features,
    httpPort: 0,
    startMediaOnSessionStart: false,
  );
}

Future<({Socket socket, List<int> remainingBody, Future<String> response})>
    _slowPost(int port, String path, Map<String, Object?> body,
        {String? token}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final response = utf8.decoder.bind(socket).join();
  final bytes = utf8.encode(jsonEncode(body));
  socket.write('POST $path HTTP/1.1\r\n'
      'Host: 127.0.0.1:$port\r\n'
      'Connection: close\r\n'
      'Content-Type: application/json\r\n'
      'Content-Length: ${bytes.length}\r\n'
      '${token == null ? '' : 'Authorization: Bearer $token\r\n'}'
      '\r\n');
  socket.add(bytes.take(1).toList());
  await socket.flush();
  return (socket: socket, remainingBody: bytes.sublist(1), response: response);
}

class _ObservedTokens extends PairingTokenService {
  Completer<void>? pairAdmitted;
  Completer<void>? authAdmitted;

  @override
  bool consumePairConfirmAttempt(String key) {
    final result = super.consumePairConfirmAttempt(key);
    final admitted = pairAdmitted;
    if (result && admitted != null && !admitted.isCompleted) {
      admitted.complete();
    }
    return result;
  }

  @override
  TrustedClientRecord? validateTrustedClientToken(String token) {
    final result = super.validateTrustedClientToken(token);
    final admitted = authAdmitted;
    if (result != null && admitted != null && !admitted.isCompleted) {
      admitted.complete();
    }
    return result;
  }
}

class _GatedRepository implements TrustedClientRepository {
  final started = Completer<void>();
  final release = Completer<void>();
  List<TrustedClientRecord> records = [];

  @override
  List<TrustedClientRecord> readAll() => List.of(records);

  @override
  Future<void> replaceAll(List<TrustedClientRecord> clients) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    records = List.of(clients);
  }
}
