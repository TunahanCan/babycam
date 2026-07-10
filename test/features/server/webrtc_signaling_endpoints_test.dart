import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/protocol/mimicam_protocol.dart';
import 'package:mimicam/core/protocol/webrtc_signaling.dart';
import 'package:mimicam/features/server/media/webrtc/webrtc_server_gateway.dart';
import 'package:mimicam/features/server/pairing/pairing_token_service.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:mimicam/services/mimicam_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('WebRTC offer, ICE and close routes use the active stream session',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final tokens = PairingTokenService();
    final gateway = _FakeWebRtcServerGateway();
    final server = MimiCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: gateway,
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final started = await _post(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      {
        'video': true,
        'audio': true,
        'mediaTransport': 'webrtc',
      },
      bearer: trusted.token,
    );
    final streamToken = started['streamToken']!.toString();

    final answer = await _post(
      client,
      base.port,
      MimiCamProtocolV2.webRtcOffer,
      {
        'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
        'video': true,
        'audio': true,
      },
      bearer: trusted.token,
      query: {'streamToken': streamToken},
    );
    await _post(
      client,
      base.port,
      MimiCamProtocolV2.webRtcIce,
      {
        'candidate': {
          'candidate': 'candidate:1 1 UDP 1 192.168.1.2 5000 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      },
      bearer: trusted.token,
      query: {'streamToken': streamToken, 'peerId': 'peer-1'},
    );
    final ice = await _get(
      client,
      base.port,
      MimiCamProtocolV2.webRtcIce,
      bearer: trusted.token,
      query: {'streamToken': streamToken, 'peerId': 'peer-1'},
    );
    await _post(
      client,
      base.port,
      MimiCamProtocolV2.webRtcClose,
      const {},
      bearer: trusted.token,
      query: {'streamToken': streamToken, 'peerId': 'peer-1'},
    );

    expect(started['mediaTransport'], 'webrtc');
    expect(answer['peerId'], 'peer-1');
    expect((answer['answer'] as Map)['type'], 'answer');
    expect((ice['iceCandidates'] as List), hasLength(1));
    expect(gateway.remoteCandidates, hasLength(1));
    expect(gateway.closedPeers, ['peer-1']);
  });

  test('healthy WebRTC peer remains authoritative after stream token expiry',
      () async {
    SharedPreferences.setMockInitialValues({
      'config.webrtc_pilot_enabled': true,
    });
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime(2026);
    final tokens = PairingTokenService(
      now: () => now,
      streamTokenTtl: const Duration(milliseconds: 10),
    );
    final server = MimiCamServer(
      config: ConfigurationService(prefs),
      strings: AppStrings(const Locale('tr')),
      onLog: (_) {},
      onAlert: (_) {},
      tokenService: tokens,
      webRtcGateway: _FakeWebRtcServerGateway(),
      startMediaOnSessionStart: false,
      httpPort: 0,
    );
    addTearDown(server.dispose);
    final base = Uri.parse(await server.startPairingMode());
    final trusted = tokens.issueTrustedClientToken(
      clientName: 'Anne',
      deviceId: 'anne',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final started = await _post(
      client,
      base.port,
      MimiCamProtocolV2.sessionStart,
      const {
        'video': true,
        'audio': true,
        'mediaTransport': 'webrtc',
      },
      bearer: trusted.token,
    );
    await _post(
      client,
      base.port,
      MimiCamProtocolV2.webRtcOffer,
      const {
        'offer': {'type': 'offer', 'sdp': 'v=0\r\n'},
        'video': true,
        'audio': true,
      },
      bearer: trusted.token,
      query: {'streamToken': started['streamToken']!.toString()},
    );

    now = now.add(const Duration(seconds: 2));
    final status = await _get(
      client,
      base.port,
      MimiCamProtocolV2.status,
      bearer: trusted.token,
    );

    expect(status['activeStreamClients'], 1);
  });
}

class _FakeWebRtcServerGateway implements WebRtcServerGateway {
  final remoteCandidates = <WebRtcIceCandidateSignal>[];
  final closedPeers = <String>[];
  final localCandidates = <WebRtcIceCandidateSignal>[
    const WebRtcIceCandidateSignal(
      candidate: 'candidate:2 1 UDP 1 192.168.1.3 5001 typ host',
    ),
  ];

  @override
  int get activePeerCount => closedPeers.isEmpty ? 1 : 0;

  @override
  bool get isAvailable => true;

  @override
  Future<void> addRemoteCandidate({
    required String clientId,
    required String peerId,
    required WebRtcIceCandidateSignal candidate,
  }) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<WebRtcOfferResponse> acceptOffer({
    required String clientId,
    required WebRtcOfferRequest request,
  }) async =>
      const WebRtcOfferResponse(
        peerId: 'peer-1',
        answer: WebRtcSignalDescription(type: 'answer', sdp: 'v=0\r\n'),
      );

  @override
  Future<void> closeClient(String clientId) async {}

  @override
  Future<void> closePeer({
    required String clientId,
    required String peerId,
  }) async {
    closedPeers.add(peerId);
  }

  @override
  List<WebRtcIceCandidateSignal> drainLocalCandidates({
    required String clientId,
    required String peerId,
  }) {
    final result = List<WebRtcIceCandidateSignal>.of(localCandidates);
    localCandidates.clear();
    return result;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> initialize() async => true;
}

Future<Map<String, Object?>> _post(
  HttpClient client,
  int port,
  String path,
  Map<String, Object?> body, {
  required String bearer,
  Map<String, String>? query,
}) async {
  final request = await client.postUrl(_uri(port, path, query));
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  request.write(jsonEncode(body));
  return _read(await request.close());
}

Future<Map<String, Object?>> _get(
  HttpClient client,
  int port,
  String path, {
  required String bearer,
  Map<String, String>? query,
}) async {
  final request = await client.getUrl(_uri(port, path, query));
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  return _read(await request.close());
}

Future<Map<String, Object?>> _read(HttpClientResponse response) async {
  final body = await utf8.decoder.bind(response).join();
  expect(response.statusCode, HttpStatus.ok, reason: body);
  return Map<String, Object?>.from(jsonDecode(body) as Map);
}

Uri _uri(int port, String path, Map<String, String>? query) => Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: path,
      queryParameters: query,
    );
