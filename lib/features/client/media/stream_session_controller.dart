import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/miucam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../services/monetization/broadcast_access_service.dart';
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
    if (isActive || _webRtcHandle != null) {
      await stop(session);
    }
    final webRtcRequested = _supportsWebRtc(session) &&
        _webRtcConnector != null &&
        await _webRtcConnector.initialize();
    var json = await _post(
      session,
      MiuCamProtocolV2.sessionStart,
      requestBody: {
        'clientId': session.clientId,
        'video': true,
        'audio': audioEnabled,
        'mediaTransport': webRtcRequested ? 'webrtc' : 'mjpeg_wav',
      },
    );
    var token = json?['streamToken']?.toString();
    if (token == null || token.isEmpty) {
      await _rollbackStartedSession(session);
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
          broadcastAccess: _broadcastAccessFrom(json),
        );
      }
      fallbackReason = selection.fallbackReason;
      try {
        await _post(session, MiuCamProtocolV2.sessionStop);
      } catch (_) {
        // The replacement start is serialized by the server and supersedes the
        // same client id. Continue so a lost stop response does not disable the
        // documented MJPEG/WAV fallback.
      }
      json = await _post(
        session,
        MiuCamProtocolV2.sessionStart,
        requestBody: {
          'clientId': session.clientId,
          'video': true,
          'audio': audioEnabled,
          'mediaTransport': 'mjpeg_wav',
        },
      );
      token = json?['streamToken']?.toString();
      if (token == null || token.isEmpty) {
        await _rollbackStartedSession(session);
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
      broadcastAccess: _broadcastAccessFrom(json),
    );
  }

  Future<void> stop(PairingSession session) async {
    Object? firstError;
    try {
      try {
        await _webRtcHandle?.close();
      } catch (error) {
        firstError = error;
      }
      _webRtcHandle = null;
      try {
        await _post(session, MiuCamProtocolV2.sessionStop);
      } catch (error) {
        firstError ??= error;
      }
    } finally {
      isActive = false;
      healthState?.setWatchActive(false);
      lastStreamToken = null;
      lastStreamTokenExpiresAtMs = null;
      dispose();
    }
    if (firstError != null) throw firstError;
  }

  Future<void> _rollbackStartedSession(PairingSession session) async {
    try {
      await _post(session, MiuCamProtocolV2.sessionStop);
    } catch (_) {
      // The malformed success response is already the primary failure. The
      // server serializes session replacement, so a later start can recover
      // even when this best-effort rollback response is lost.
    } finally {
      isActive = false;
      lastStreamToken = null;
      lastStreamTokenExpiresAtMs = null;
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
      final errorJson = _jsonObject(body);
      if (response.statusCode == HttpStatus.paymentRequired &&
          errorJson?['code'] == 'BROADCAST_ACCESS_LOCKED' &&
          errorJson?['broadcastAccess'] is Map) {
        throw BroadcastAccessLockedException(
          BroadcastAccessSnapshot.fromJson(
            Map<Object?, Object?>.from(
              errorJson!['broadcastAccess'] as Map,
            ),
          ),
        );
      }
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

  Map<String, Object?>? _jsonObject(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  BroadcastAccessSnapshot? _broadcastAccessFrom(
    Map<String, Object?>? json,
  ) {
    final value = json?['broadcastAccess'];
    return value is Map
        ? BroadcastAccessSnapshot.fromJson(Map<Object?, Object?>.from(value))
        : null;
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
