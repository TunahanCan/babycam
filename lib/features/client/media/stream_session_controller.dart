import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import 'client_stream_health_monitor.dart';

class StreamSessionController {
  StreamSessionController({
    this.healthMonitor,
    this.streamTimeout = const Duration(seconds: 5),
    HttpClient Function(PairingSession session)? clientFactory,
  }) : _clientFactory = clientFactory;

  final ClientStreamHealthMonitor? healthMonitor;
  final Duration streamTimeout;
  final HttpClient Function(PairingSession session)? _clientFactory;
  bool isActive = false;
  String? lastStreamToken;
  int? lastStreamTokenExpiresAtMs;
  HttpClient? _client;
  HttpClient? _mediaClient;
  StreamSubscription<List<int>>? _videoSubscription;
  StreamSubscription<List<int>>? _audioSubscription;
  String? _clientKey;

  Future<void> start(PairingSession session) async {
    final json = await _post(session, MimiCamProtocolV2.sessionStart);
    lastStreamToken = json?['streamToken']?.toString();
    final expiresAtMs = json?['streamTokenExpiresAtMs'];
    lastStreamTokenExpiresAtMs = expiresAtMs is int ? expiresAtMs : null;
    isActive = true;
    healthMonitor?.resetForNewWatchSession();
    final streamToken = lastStreamToken;
    if (streamToken != null && streamToken.isNotEmpty) {
      _startMediaReaders(session, streamToken);
    }
  }

  Future<void> stop(PairingSession session) async {
    try {
      await _post(session, MimiCamProtocolV2.sessionStop);
    } finally {
      isActive = false;
      healthMonitor?.setWatchActive(false);
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
    return _client!;
  }

  void _startMediaReaders(PairingSession session, String streamToken) {
    _videoSubscription?.cancel();
    _audioSubscription?.cancel();
    _mediaClient?.close(force: true);
    _mediaClient = _createClient(session)..connectionTimeout = streamTimeout;
    _openVideoReader(session, streamToken);
    _openAudioReader(session, streamToken);
  }

  Future<void> _openVideoReader(
    PairingSession session,
    String streamToken,
  ) async {
    final client = _mediaClient;
    if (client == null) return;
    try {
      final request = await client.getUrl(ServerEndpointBuilder(session)
          .http(MimiCamProtocolV2.video, query: {'streamToken': streamToken}));
      final response = await request.close().timeout(streamTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Video stream failed: ${response.statusCode}');
      }
      _videoSubscription = response.listen(
        (chunk) {
          if (chunk.isNotEmpty) healthMonitor?.markVideoFrameReceived();
        },
        onError: (_) => healthMonitor?.markStreamTimeout(),
        onDone: () {
          if (isActive) healthMonitor?.markStreamTimeout();
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (isActive) healthMonitor?.markStreamTimeout();
    }
  }

  Future<void> _openAudioReader(
    PairingSession session,
    String streamToken,
  ) async {
    final client = _mediaClient;
    if (client == null) return;
    try {
      final request = await client.getUrl(ServerEndpointBuilder(session)
          .http(MimiCamProtocolV2.audio, query: {'streamToken': streamToken}));
      final response = await request.close().timeout(streamTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Audio stream failed: ${response.statusCode}');
      }
      _audioSubscription = response.listen(
        (chunk) {
          if (chunk.isNotEmpty) healthMonitor?.markAudioChunkReceived();
        },
        onError: (_) => healthMonitor?.markAudioUnderrun(),
        onDone: () {
          if (isActive) healthMonitor?.markAudioUnderrun();
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (isActive) healthMonitor?.markAudioUnderrun();
    }
  }

  HttpClient _createClient(PairingSession session) {
    final factory = _clientFactory;
    return factory == null ? HttpClient() : factory(session);
  }

  void dispose() {
    _videoSubscription?.cancel();
    _videoSubscription = null;
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _mediaClient?.close(force: true);
    _mediaClient = null;
    _client?.close(force: true);
    _client = null;
    _clientKey = null;
  }
}
