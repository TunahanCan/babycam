import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import 'active_stream_session.dart';
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

  Future<ActiveStreamSession?> start(
    PairingSession session, {
    bool audioEnabled = false,
  }) async {
    final json = await _post(
      session,
      MimiCamProtocolV2.sessionStart,
      requestBody: {
        'clientId': session.clientId,
        'video': true,
        'audio': audioEnabled,
      },
    );
    lastStreamToken = json?['streamToken']?.toString();
    final expiresAtMs = json?['streamTokenExpiresAtMs'];
    lastStreamTokenExpiresAtMs = expiresAtMs is int ? expiresAtMs : null;
    isActive = true;
    healthState?.resetForNewWatchSession();
    final token = lastStreamToken;
    if (token == null || token.isEmpty) return null;
    return ActiveStreamSession(
      streamToken: token,
      expiresAtMs: lastStreamTokenExpiresAtMs,
      audioEnabled: audioEnabled,
    );
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
    PairingSession session,
    String path, {
    Map<String, Object?>? requestBody,
  }) async {
    final client = _clientForSession(session);
    final request =
        await client.postUrl(ServerEndpointBuilder(session).http(path));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${session.sessionToken}');
    request.write(jsonEncode(requestBody ?? {'clientId': session.clientId}));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      final detail = _errorDetail(body);
      throw StateError(
        detail == null
            ? '$path failed: ${response.statusCode}'
            : '$path failed: ${response.statusCode} - $detail',
      );
    }
    if (body.trim().isEmpty) return null;
    final json = jsonDecode(body);
    if (json is! Map) return null;
    return Map<String, Object?>.from(json);
  }

  String? _errorDetail(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final message = json['message']?.toString().trim();
        if (message != null && message.isNotEmpty) return message;
        final code = json['code']?.toString().trim();
        if (code != null && code.isNotEmpty) return code;
      }
    } catch (_) {
      return body.trim();
    }
    return body.trim();
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
