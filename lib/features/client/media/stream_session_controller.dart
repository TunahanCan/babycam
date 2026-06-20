import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import 'client_stream_health_state.dart';

class StreamSessionController {
  StreamSessionController({
    this.healthState,
    this.streamTimeout = const Duration(seconds: 5),
    HttpClient Function(PairingSession session)? clientFactory,
  }) : _clientFactory = clientFactory;

  final ClientStreamHealthState? healthState;
  final Duration streamTimeout;
  final HttpClient Function(PairingSession session)? _clientFactory;
  bool isActive = false;
  String? lastStreamToken;
  int? lastStreamTokenExpiresAtMs;
  HttpClient? _client;
  String? _clientKey;

  Future<void> start(PairingSession session) async {
    final json = await _post(session, MimiCamProtocolV2.sessionStart);
    lastStreamToken = json?['streamToken']?.toString();
    final expiresAtMs = json?['streamTokenExpiresAtMs'];
    lastStreamTokenExpiresAtMs = expiresAtMs is int ? expiresAtMs : null;
    isActive = true;
    healthState?.resetForNewWatchSession();
  }

  Future<void> stop(PairingSession session) async {
    try {
      await _post(session, MimiCamProtocolV2.sessionStop);
    } finally {
      isActive = false;
      healthState?.setWatchActive(false);
      lastStreamToken = null;
      lastStreamTokenExpiresAtMs = null;
      dispose();
    }
  }

  Future<Map<String, Object?>?> _post(
      PairingSession session, String path) async {
    final client = _clientForSession(session);
    final request =
        await client.postUrl(ServerEndpointBuilder(session).http(path));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${session.sessionToken}');
    request.write(jsonEncode({'clientId': session.clientId}));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('$path failed: ${response.statusCode}');
    }
    final body = await utf8.decoder.bind(response).join();
    if (body.trim().isEmpty) return null;
    final json = jsonDecode(body);
    if (json is! Map) return null;
    return Map<String, Object?>.from(json);
  }

  HttpClient _clientForSession(PairingSession session) {
    final key = '${session.httpScheme}://${session.host}:${session.port}';
    if (_client != null && _clientKey == key) return _client!;
    _client?.close(force: true);
    _clientKey = key;
    final factory = _clientFactory;
    if (factory != null) {
      _client = factory(session);
    } else {
      _client = HttpClient();
    }
    _client?.connectionTimeout = streamTimeout;
    return _client!;
  }

  void dispose() {
    _client?.close(force: true);
    _client = null;
    _clientKey = null;
  }
}
