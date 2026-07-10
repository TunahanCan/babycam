import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import 'active_stream_session.dart';
import 'client_stream_health_state.dart';
import 'webrtc/webrtc_client_connector.dart';
import 'webrtc/webrtc_transport_selector.dart';

class StreamSessionController {
  StreamSessionController({
    this.healthState,
    this.streamTimeout = const Duration(seconds: 5),
    HttpClient Function(PairingSession session)? clientFactory,
    WebRtcClientConnector? webRtcConnector,
  })  : _clientFactory = clientFactory,
        _webRtcConnector = webRtcConnector;

  final ClientStreamHealthState? healthState;
  final Duration streamTimeout;
  final HttpClient Function(PairingSession session)? _clientFactory;
  final WebRtcClientConnector? _webRtcConnector;
  bool isActive = false;
  String? lastStreamToken;
  int? lastStreamTokenExpiresAtMs;
  HttpClient? _client;
  String? _clientKey;
  WebRtcClientMediaHandle? _webRtcHandle;

  Future<ActiveStreamSession?> start(
    PairingSession session, {
    bool audioEnabled = false,
  }) async {
    final webRtcRequested = _supportsWebRtc(session) &&
        _webRtcConnector != null &&
        await _webRtcConnector.initialize();
    var json = await _post(
      session,
      MimiCamProtocolV2.sessionStart,
      requestBody: {
        'clientId': session.clientId,
        'video': true,
        'audio': audioEnabled,
        'mediaTransport': webRtcRequested ? 'webrtc' : 'mjpeg_wav',
      },
    );
    var token = json?['streamToken']?.toString();
    if (token == null || token.isEmpty) {
      isActive = false;
      lastStreamToken = null;
      lastStreamTokenExpiresAtMs = null;
      throw StateError('Session start did not return a stream token.');
    }
    Object? fallbackReason;
    if (webRtcRequested) {
      final selection = await WebRtcTransportSelector(
        connector: _webRtcConnector,
      ).select(
        pilotEnabled: true,
        session: session,
        streamToken: token,
        video: true,
        audio: audioEnabled,
      );
      if (selection.transport == ClientMediaTransport.webRtc &&
          selection.webRtc != null) {
        _webRtcHandle = selection.webRtc;
        lastStreamToken = token;
        final expiresAtMs = json?['streamTokenExpiresAtMs'];
        lastStreamTokenExpiresAtMs = expiresAtMs is int ? expiresAtMs : null;
        isActive = true;
        healthState?.resetForNewWatchSession();
        return ActiveStreamSession(
          streamToken: token,
          expiresAtMs: lastStreamTokenExpiresAtMs,
          audioEnabled: audioEnabled,
          transport: ClientMediaTransport.webRtc,
          webRtc: selection.webRtc,
        );
      }
      fallbackReason = selection.fallbackReason;
      await _post(session, MimiCamProtocolV2.sessionStop);
      json = await _post(
        session,
        MimiCamProtocolV2.sessionStart,
        requestBody: {
          'clientId': session.clientId,
          'video': true,
          'audio': audioEnabled,
          'mediaTransport': 'mjpeg_wav',
        },
      );
      token = json?['streamToken']?.toString();
      if (token == null || token.isEmpty) {
        throw StateError('Fallback session did not return a stream token.');
      }
    }
    lastStreamToken = token;
    final expiresAtMs = json?['streamTokenExpiresAtMs'];
    lastStreamTokenExpiresAtMs = expiresAtMs is int ? expiresAtMs : null;
    isActive = true;
    healthState?.resetForNewWatchSession();
    return ActiveStreamSession(
      streamToken: token,
      expiresAtMs: lastStreamTokenExpiresAtMs,
      audioEnabled: audioEnabled,
      transportFallbackReason: fallbackReason,
    );
  }

  Future<void> stop(PairingSession session) async {
    try {
      await _webRtcHandle?.close();
      _webRtcHandle = null;
      await _post(session, MimiCamProtocolV2.sessionStop);
    } finally {
      isActive = false;
      healthState?.setWatchActive(false);
      lastStreamToken = null;
      lastStreamTokenExpiresAtMs = null;
      dispose();
    }
  }

  bool _supportsWebRtc(PairingSession session) {
    final capabilities = session.payload.capabilities;
    final webRtc = capabilities['webrtc'];
    if (webRtc is Map && webRtc['enabled'] == true) return true;
    final transports = capabilities['mediaTransports'];
    return transports is Iterable &&
        transports.any((value) => value == 'webrtc');
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
    final response = await request.close().timeout(streamTimeout);
    final body = await utf8.decoder.bind(response).join().timeout(
          streamTimeout,
        );
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
