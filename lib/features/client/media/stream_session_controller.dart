import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/protocol/miucam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../core/security/secure_random_token_generator.dart';
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
    SecureRandomTokenGenerator? attemptTokenGenerator,
  })  : _clientFactory = clientFactory,
        _webRtcConnector = webRtcConnector,
        _attemptTokenGenerator =
            attemptTokenGenerator ?? SecureRandomTokenGenerator();

  final ClientStreamHealthState? healthState;
  final Duration streamTimeout;
  final HttpClient Function(PairingSession session)? _clientFactory;
  final WebRtcClientConnector? _webRtcConnector;
  final SecureRandomTokenGenerator _attemptTokenGenerator;
  bool isActive = false;
  String? lastStreamToken;
  int? lastStreamTokenExpiresAtMs;
  HttpClient? _client;
  String? _clientKey;
  WebRtcClientMediaHandle? _webRtcHandle;
  Future<ActiveStreamSession?>? _startOperation;
  Future<void>? _stopOperation;
  _OwnedStreamAttempt? _pendingAttempt;
  int? _pendingAttemptGeneration;
  _OwnedStreamAttempt? _activeAttempt;
  final _attemptsToStop = <_OwnedStreamAttempt>{};
  int _operationGeneration = 0;
  bool _lastStopHadLocalFailure = false;

  Future<ActiveStreamSession?> start(
    PairingSession session, {
    bool audioEnabled = false,
  }) async {
    if (isActive ||
        _webRtcHandle != null ||
        _startOperation != null ||
        _stopOperation != null ||
        _attemptsToStop.isNotEmpty) {
      try {
        await stop(session);
      } catch (error, stackTrace) {
        final sameOwnerStillNeedsCleanup =
            _attemptsToStop.any((attempt) => attempt.isOwnedBy(session));
        if (_lastStopHadLocalFailure || sameOwnerStillNeedsCleanup) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        // A previously paired room may be permanently offline. Its attempt
        // remains retained for later cleanup, but must not prevent a newly
        // paired room—with a different server/client owner—from starting.
      }
    }
    final generation = ++_operationGeneration;
    final attempt = _trackAttempt(session);
    _pendingAttempt = attempt;
    _pendingAttemptGeneration = generation;
    late final Future<ActiveStreamSession?> operation;
    operation = _startAttempt(
      audioEnabled: audioEnabled,
      generation: generation,
      initialAttempt: attempt,
    ).whenComplete(() {
      if (identical(_startOperation, operation)) {
        _startOperation = null;
      }
    });
    _startOperation = operation;
    try {
      return await operation;
    } finally {
      if (_pendingAttemptGeneration == generation) {
        _pendingAttempt = null;
        _pendingAttemptGeneration = null;
      }
    }
  }

  Future<ActiveStreamSession?> _startAttempt({
    required bool audioEnabled,
    required int generation,
    required _OwnedStreamAttempt initialAttempt,
  }) async {
    var attempt = initialAttempt;
    final session = attempt.session;
    final webRtcConnector = _webRtcConnector;
    final supportsWebRtc = _supportsWebRtc(session) && webRtcConnector != null;
    var webRtcRequested = false;
    if (supportsWebRtc) {
      try {
        webRtcRequested =
            await webRtcConnector.initialize().timeout(streamTimeout);
      } catch (_) {
        // Capability probing is an optional pilot. A bounded failure falls
        // back to the production MJPEG/WAV transport.
      }
    }
    _ensureCurrent(generation);
    var json = await _startRemoteAttempt(
      attempt,
      body: {
        'clientId': session.clientId,
        'video': true,
        'audio': audioEnabled,
        'mediaTransport': webRtcRequested ? 'webrtc' : 'mjpeg_wav',
        MiuCamProtocolV2.streamAttemptId: attempt.id,
      },
    );
    _ensureCurrent(generation);
    var token = json?['streamToken']?.toString();
    if (token == null || token.isEmpty) {
      await _rollbackStartedSession(attempt);
      throw StateError('Session start did not return a stream token.');
    }
    Object? fallbackReason;
    if (webRtcRequested) {
      final connector = webRtcConnector!;
      final selectionOperation = WebRtcTransportSelector(
        connector: connector,
      ).select(
        pilotEnabled: true,
        session: session,
        streamToken: token,
        video: true,
        audio: audioEnabled,
      );
      late final WebRtcTransportSelection selection;
      try {
        selection = await selectionOperation.timeout(streamTimeout);
      } on TimeoutException catch (error) {
        // Keep ownership of any handle that wins the timeout race, and close
        // it when the original Future eventually settles.
        unawaited(selectionOperation.then<void>(
          (lateSelection) async {
            try {
              await lateSelection.webRtc?.close().timeout(streamTimeout);
            } catch (_) {}
          },
          onError: (Object _, StackTrace __) {},
        ));
        try {
          final cancellation = connector.cancelPendingConnections();
          unawaited(cancellation.timeout(streamTimeout).catchError((_) {}));
        } catch (_) {}
        selection = WebRtcTransportSelection(
          transport: ClientMediaTransport.mjpegWav,
          fallbackReason: error,
        );
      }
      if (!_isCurrent(generation)) {
        try {
          await selection.webRtc?.close().timeout(streamTimeout);
        } catch (_) {}
        throw const _StreamStartInterrupted();
      }
      if (selection.transport == ClientMediaTransport.webRtc &&
          selection.webRtc != null) {
        _webRtcHandle = selection.webRtc;
        _activeAttempt = attempt;
        _pendingAttempt = null;
        _pendingAttemptGeneration = null;
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
        await _post(
          session,
          MiuCamProtocolV2.sessionStop,
          requestBody: _stopBody(attempt),
        );
        _forgetAttempt(attempt);
      } catch (_) {
        // The replacement start is serialized by the server and supersedes the
        // same client id. Continue so a lost stop response does not disable the
        // documented MJPEG/WAV fallback.
      }
      _ensureCurrent(generation);
      attempt = _trackAttempt(session);
      _pendingAttempt = attempt;
      _pendingAttemptGeneration = generation;
      json = await _startRemoteAttempt(
        attempt,
        body: {
          'clientId': session.clientId,
          'video': true,
          'audio': audioEnabled,
          'mediaTransport': 'mjpeg_wav',
          MiuCamProtocolV2.streamAttemptId: attempt.id,
        },
      );
      _ensureCurrent(generation);
      token = json?['streamToken']?.toString();
      if (token == null || token.isEmpty) {
        await _rollbackStartedSession(attempt);
        throw StateError('Fallback session did not return a stream token.');
      }
    }
    _activeAttempt = attempt;
    _pendingAttempt = null;
    _pendingAttemptGeneration = null;
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

  Future<void> stop(PairingSession session) {
    final current = _stopOperation;
    if (current != null) return current;
    late final Future<void> operation;
    operation = _stop(session).whenComplete(() {
      if (identical(_stopOperation, operation)) _stopOperation = null;
    });
    _stopOperation = operation;
    return operation;
  }

  Future<void> _stop(PairingSession session) async {
    _lastStopHadLocalFailure = false;
    _operationGeneration++;
    final pendingStart = _startOperation;
    _startOperation = null;
    final pendingAttempt = _pendingAttempt;
    final activeAttempt = _activeAttempt;
    _pendingAttempt = null;
    _pendingAttemptGeneration = null;
    _activeAttempt = null;
    final attempts = <_OwnedStreamAttempt>{
      ..._attemptsToStop,
      if (pendingAttempt != null) pendingAttempt,
      if (activeAttempt != null) activeAttempt,
    };
    Future<void>? pendingWebRtcCancellation;
    try {
      pendingWebRtcCancellation = _webRtcConnector?.cancelPendingConnections();
    } catch (error, stackTrace) {
      pendingWebRtcCancellation = Future<void>.error(error, stackTrace);
    }
    final handle = _webRtcHandle;
    _webRtcHandle = null;
    isActive = false;
    healthState?.setWatchActive(false);
    lastStreamToken = null;
    lastStreamTokenExpiresAtMs = null;
    // Abort pending local work synchronously. A matching server-side attempt
    // tombstone makes the detached stop safe even if it reaches the room
    // before bytes buffered by the old start connection.
    dispose();

    Object? firstLocalError;
    Object? firstOwnedAttemptError;
    Future<void> cancelPendingWebRtc() async {
      try {
        await pendingWebRtcCancellation?.timeout(streamTimeout);
      } catch (error) {
        firstLocalError ??= error;
      }
    }

    Future<void> closeLocalHandle() async {
      try {
        await handle?.close().timeout(streamTimeout);
      } catch (error) {
        firstLocalError ??= error;
      }
    }

    Future<Object?> stopAttempt(_OwnedStreamAttempt attempt) async {
      final stopSession = attempt.authorizedSessionFor(session);
      try {
        await _postDetached(
          stopSession,
          MiuCamProtocolV2.sessionStop,
          requestBody: _stopBody(attempt, sessionOverride: stopSession),
        );
        return null;
      } catch (error) {
        return error;
      }
    }

    final immediateStops = <_OwnedStreamAttempt, Future<Object?>>{
      for (final attempt in attempts) attempt: stopAttempt(attempt),
    };
    final startSettled = () async {
      if (pendingStart == null) return;
      try {
        await pendingStart.timeout(streamTimeout);
      } catch (_) {
        // The generation and attempt tombstone are the cancellation authority.
      }
    }();

    await Future.wait([
      cancelPendingWebRtc(),
      closeLocalHandle(),
      startSettled,
      ...immediateStops.values.map((operation) async {
        await operation;
      }),
    ]);

    final retryStops = <_OwnedStreamAttempt, Future<Object?>>{
      if (pendingStart != null)
        for (final attempt in attempts)
          if (await immediateStops[attempt]! != null)
            attempt: stopAttempt(attempt),
    };
    await Future.wait(retryStops.values);

    for (final attempt in attempts) {
      final immediateError = await immediateStops[attempt]!;
      final retry = retryStops[attempt];
      final retryError = retry == null ? null : await retry;
      if (immediateError == null || (retry != null && retryError == null)) {
        _forgetAttempt(attempt);
      } else if (attempt.isOwnedBy(session)) {
        firstOwnedAttemptError ??= retryError ?? immediateError;
      }
    }
    _lastStopHadLocalFailure = firstLocalError != null;
    final terminalError = firstLocalError ?? firstOwnedAttemptError;
    if (terminalError != null) throw terminalError;
  }

  Future<void> _rollbackStartedSession(
    _OwnedStreamAttempt attempt,
  ) async {
    final stopped = await _stopAttemptBestEffort(attempt);
    if (!stopped) {
      // The malformed success response is already the primary failure. The
      // server serializes session replacement, so a later start can recover
      // even when this best-effort rollback response is lost.
    }
    isActive = false;
    lastStreamToken = null;
    lastStreamTokenExpiresAtMs = null;
  }

  bool _supportsWebRtc(PairingSession session) {
    final capabilities = session.payload.capabilities;
    final webRtc = capabilities['webrtc'];
    if (webRtc is Map && webRtc['enabled'] == true) return true;
    final transports = capabilities['mediaTransports'];
    return transports is Iterable &&
        transports.any((value) => value == 'webrtc');
  }

  bool _isCurrent(int generation) => generation == _operationGeneration;

  void _ensureCurrent(int generation) {
    if (!_isCurrent(generation)) throw const _StreamStartInterrupted();
  }

  Future<Map<String, Object?>?> _startRemoteAttempt(
    _OwnedStreamAttempt attempt, {
    required Map<String, Object?> body,
  }) async {
    final session = attempt.session;
    try {
      final json = await _post(
        session,
        MiuCamProtocolV2.sessionStart,
        requestBody: body,
      );
      final echoedAttemptId = json?[MiuCamProtocolV2.streamAttemptId];
      if (session.payload.schemaVersion >= MiuCamProtocolV2.schemaVersion &&
          (echoedAttemptId is! String || echoedAttemptId != attempt.id)) {
        throw StateError(
          'Session start did not confirm the current attempt id.',
        );
      }
      return json;
    } catch (error, stackTrace) {
      await _stopAttemptBestEffort(attempt);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> _stopAttemptBestEffort(
    _OwnedStreamAttempt attempt,
  ) async {
    try {
      await _postDetached(
        attempt.session,
        MiuCamProtocolV2.sessionStop,
        requestBody: _stopBody(attempt),
      );
      _forgetAttempt(attempt);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, Object?>?> _post(
    PairingSession session,
    String path, {
    Map<String, Object?>? requestBody,
  }) async {
    final client = _clientForSession(session);
    try {
      return await _postWithClient(
        client,
        session,
        path,
        requestBody: requestBody,
      ).timeout(streamTimeout);
    } catch (_) {
      if (identical(_client, client)) dispose();
      rethrow;
    }
  }

  Future<Map<String, Object?>?> _postDetached(
    PairingSession session,
    String path, {
    Map<String, Object?>? requestBody,
  }) async {
    final factory = _clientFactory;
    final client = factory?.call(session) ?? HttpClient();
    client.connectionTimeout = streamTimeout;
    try {
      return await _postWithClient(
        client,
        session,
        path,
        requestBody: requestBody,
      ).timeout(streamTimeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>?> _postWithClient(
    HttpClient client,
    PairingSession session,
    String path, {
    Map<String, Object?>? requestBody,
  }) async {
    final request = await client
        .postUrl(ServerEndpointBuilder(session).http(path))
        .timeout(streamTimeout);
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

  Map<String, Object?> _stopBody(
    _OwnedStreamAttempt attempt, {
    PairingSession? sessionOverride,
  }) =>
      {
        'clientId': (sessionOverride ?? attempt.session).clientId,
        MiuCamProtocolV2.streamAttemptId: attempt.id,
      };

  String _newAttemptId() => _attemptTokenGenerator.generateHex(byteCount: 16);

  _OwnedStreamAttempt _trackAttempt(PairingSession session) {
    final attempt = _OwnedStreamAttempt(
      session: session,
      id: _newAttemptId(),
    );
    _attemptsToStop.add(attempt);
    return attempt;
  }

  void _forgetAttempt(_OwnedStreamAttempt attempt) {
    _attemptsToStop.remove(attempt);
  }

  void dispose() {
    _client?.close(force: true);
    _client = null;
    _clientKey = null;
  }
}

class _StreamStartInterrupted implements Exception {
  const _StreamStartInterrupted();
}

class _OwnedStreamAttempt {
  const _OwnedStreamAttempt({
    required this.session,
    required this.id,
  });

  final PairingSession session;
  final String id;

  /// A token renewal may provide fresher credentials for the same exact
  /// client/server owner. A session from another pairing must never redirect
  /// this attempt's cleanup to its endpoint.
  PairingSession authorizedSessionFor(PairingSession requested) {
    return isOwnedBy(requested) ? requested : session;
  }

  bool isOwnedBy(PairingSession requested) {
    return requested.clientId == session.clientId &&
        requested.deviceId == session.deviceId &&
        requested.httpScheme == session.httpScheme &&
        requested.host == session.host &&
        requested.port == session.port;
  }
}
