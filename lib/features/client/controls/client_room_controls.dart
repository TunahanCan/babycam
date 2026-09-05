import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/protocol/device_feature_models.dart';
import '../../../core/protocol/miucam_protocol.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../core/security/secure_random_token_generator.dart';
import '../../server/media/microphone_capture_service.dart';

class RoomMicrophonePermissionException implements Exception {
  const RoomMicrophonePermissionException();

  @override
  String toString() => 'Microphone permission is required for talk.';
}

class ClientRoomControlSnapshot {
  const ClientRoomControlSnapshot({
    this.comfort,
    this.talking = false,
    this.talkBytesSent = 0,
    this.talkBytesDropped = 0,
    this.lastError,
    this.audioDetectionPaused,
  });

  final ComfortAudioState? comfort;
  final bool talking;
  final int talkBytesSent;
  final int talkBytesDropped;
  final Object? lastError;
  final bool? audioDetectionPaused;

  bool get isAudioDetectionPaused =>
      talking || (audioDetectionPaused ?? comfort?.playing ?? false);
}

class ClientRoomControls {
  ClientRoomControls({
    MicrophoneCaptureService? microphone,
    HttpClient Function()? clientFactory,
    this.timeout = const Duration(seconds: 5),
    Duration? talkFlushTimeout,
    Future<void> Function(HttpClientRequest request)? talkRequestFlusher,
    SecureRandomTokenGenerator? talkAttemptTokenGenerator,
  })  : _microphone = microphone ??
            MicrophoneCaptureService(sampleRate: 16000, channels: 1),
        _clientFactory = clientFactory ?? HttpClient.new,
        _talkAttemptTokenGenerator =
            talkAttemptTokenGenerator ?? SecureRandomTokenGenerator(),
        talkFlushTimeout = talkFlushTimeout ?? timeout,
        _talkRequestFlusher =
            talkRequestFlusher ?? ((request) => request.flush());

  final MicrophoneCaptureService _microphone;
  final HttpClient Function() _clientFactory;
  final SecureRandomTokenGenerator _talkAttemptTokenGenerator;
  final Future<void> Function(HttpClientRequest request) _talkRequestFlusher;
  final Duration timeout;
  final Duration talkFlushTimeout;
  final _states = StreamController<ClientRoomControlSnapshot>.broadcast();
  ClientRoomControlSnapshot _state = const ClientRoomControlSnapshot();
  _TalkAttempt? _activeTalkAttempt;
  final Set<_TalkAttempt> _ownedTalkAttempts = {};
  Future<void>? _startInFlight;
  Future<void>? _stopInFlight;
  static const _maxPendingTalkChunks = 12;
  int _talkIntentGeneration = 0;
  bool _disposed = false;
  int _comfortRefreshGeneration = 0;
  int _comfortCommandGeneration = 0;

  ClientRoomControlSnapshot get currentState => _state;
  Stream<ClientRoomControlSnapshot> get states => _states.stream;

  Future<ComfortAudioState?> refreshComfort(PairingSession session) async {
    final generation = ++_comfortRefreshGeneration;
    final json = await _requestJson(
      session,
      MiuCamProtocolV2.comfortState,
      method: 'GET',
    );
    final comfort = ComfortAudioState.fromJson(json?['state']);
    if (_disposed || generation != _comfortRefreshGeneration) return comfort;
    _emit(
        ClientRoomControlSnapshot(
          comfort: comfort,
          talking: _state.talking,
          talkBytesSent: _state.talkBytesSent,
          talkBytesDropped: _state.talkBytesDropped,
          audioDetectionPaused: _readAudioDetectionPaused(json),
        ),
        preserveDetectionState: false);
    return comfort;
  }

  Future<ComfortAudioState?> setComfort(
    PairingSession session, {
    required String action,
    String? trackId,
    double? volume,
    bool? loop,
  }) async {
    final generation = ++_comfortCommandGeneration;
    _comfortRefreshGeneration++;
    final json = await _requestJson(
      session,
      MiuCamProtocolV2.comfortCommand,
      method: 'POST',
      body: {
        'action': action,
        if (trackId != null) 'trackId': trackId,
        if (volume != null) 'volume': volume,
        if (loop != null) 'loop': loop,
      },
    );
    final comfort = ComfortAudioState.fromJson(json?['state']);
    if (_disposed || generation != _comfortCommandGeneration) return comfort;
    _comfortRefreshGeneration++;
    _emit(
        ClientRoomControlSnapshot(
          comfort: comfort ?? _state.comfort,
          talking: _state.talking,
          talkBytesSent: _state.talkBytesSent,
          talkBytesDropped: _state.talkBytesDropped,
          audioDetectionPaused: _readAudioDetectionPaused(json),
        ),
        preserveDetectionState: false);
    return comfort;
  }

  Future<void> startTalking(PairingSession session) async {
    if (_disposed || _state.talking) return;
    final stopping = _stopInFlight;
    if (stopping != null) {
      try {
        await stopping;
      } catch (_) {
        // Local cleanup is final even when the remote stop reported an error.
      }
      if (_disposed || _state.talking) return;
    }
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    final generation = ++_talkIntentGeneration;
    final attempt = _TalkAttempt(
      session: session,
      id: _talkAttemptTokenGenerator.generateHex(byteCount: 16),
      generation: generation,
    );
    _ownedTalkAttempts.add(attempt);
    final operation = _startTalking(attempt);
    _startInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_startInFlight, operation)) _startInFlight = null;
    }
  }

  Future<void> _startTalking(
    _TalkAttempt attempt,
  ) async {
    final session = attempt.session;
    final generation = attempt.generation;
    late final bool hasPermission;
    try {
      hasPermission = await _microphone.ensurePermission(
        preserveResolvedDecisionWhenCancelled: true,
      );
    } catch (_) {
      _ownedTalkAttempts.remove(attempt);
      rethrow;
    }
    if (!hasPermission) {
      _ownedTalkAttempts.remove(attempt);
      throw const RoomMicrophonePermissionException();
    }
    if (!_isTalkIntentCurrent(generation)) {
      _ownedTalkAttempts.remove(attempt);
      return;
    }

    String token;
    try {
      // From this point a concurrent stop must send an attempt-scoped
      // tombstone: the request may reach the room after local cancellation.
      attempt.startRequestIssued = true;
      final start = await _requestJson(
        session,
        MiuCamProtocolV2.talkStart,
        method: 'POST',
        body: {
          'sampleRate': 16000,
          'channels': 1,
          'codec': 'pcm_s16le',
          MiuCamProtocolV2.talkAttemptId: attempt.id,
        },
      );
      final sessionJson = start?['session'];
      final echoedAttemptId = sessionJson is Map
          ? sessionJson[MiuCamProtocolV2.talkAttemptId]
          : null;
      if (session.payload.schemaVersion >= MiuCamProtocolV2.schemaVersion &&
          (echoedAttemptId is! String || echoedAttemptId != attempt.id)) {
        throw StateError(
          'Talk start did not confirm the current attempt id.',
        );
      }
      final candidate = sessionJson is Map
          ? sessionJson['talkToken']?.toString().trim()
          : null;
      if (candidate == null || candidate.isEmpty) {
        throw StateError('Talk start did not return a talk token.');
      }
      token = candidate;
      attempt.token = token;
    } catch (error, stackTrace) {
      await _stopTalkAttemptBestEffort(attempt);
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (!_isTalkIntentCurrent(generation)) {
      await _stopTalkAttemptBestEffort(attempt);
      return;
    }
    // Store cleanup ownership as soon as the room has created the session.
    // Every following failure can now issue /talk/stop instead of orphaning it.
    _activeTalkAttempt = attempt;

    try {
      if (!_isTalkIntentCurrent(generation)) {
        await _abortTalkAttempt(attempt);
        return;
      }
      final client = _clientFactory()..connectionTimeout = timeout;
      attempt.audioClient = client;
      final uri = ServerEndpointBuilder(session).http(
        MiuCamProtocolV2.talkAudio,
        query: {'talkToken': token},
      );
      final request = await client.postUrl(uri).timeout(timeout);
      attempt.audioRequest = request;
      if (!_isTalkIntentCurrent(generation)) {
        await _abortTalkAttempt(attempt);
        return;
      }
      request.headers
        ..contentType = ContentType('audio', 'L16', parameters: {
          'rate': '16000',
          'channels': '1',
        })
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(
          HttpHeaders.authorizationHeader,
          'Bearer ${session.sessionToken}',
        );
      final started = await _microphone.start(
        onChunk: (chunk) {
          if (identical(_activeTalkAttempt, attempt)) {
            _enqueueTalkChunk(attempt, chunk.streamPcm16le);
          }
        },
        onError: (error, _) {
          if (!identical(_activeTalkAttempt, attempt)) return;
          _emit(ClientRoomControlSnapshot(
            comfort: _state.comfort,
            talking: false,
            talkBytesSent: _state.talkBytesSent,
            talkBytesDropped: _state.talkBytesDropped,
            lastError: error,
          ));
          unawaited(stopTalking().catchError((_) {}));
        },
      );
      if (!started) {
        if (!_isTalkIntentCurrent(generation)) {
          await _abortTalkAttempt(attempt);
          return;
        }
        if (_microphone.snapshot.permissionGranted == false) {
          throw const RoomMicrophonePermissionException();
        }
        throw StateError('Microphone permission is required for talk.');
      }
      if (!_isTalkIntentCurrent(generation)) {
        await _abortTalkAttempt(attempt);
        return;
      }
      _emit(ClientRoomControlSnapshot(
        comfort: _state.comfort,
        talking: true,
        talkBytesSent: _state.talkBytesSent,
        talkBytesDropped: _state.talkBytesDropped,
      ));
    } catch (error) {
      await _abortTalkAttempt(attempt);
      rethrow;
    }
  }

  Future<bool> _stopTalkAttemptBestEffort(_TalkAttempt attempt) async {
    try {
      await _requestJson(
        attempt.session,
        MiuCamProtocolV2.talkStop,
        method: 'POST',
        body: {
          MiuCamProtocolV2.talkAttemptId: attempt.id,
          if (attempt.token != null) 'talkToken': attempt.token,
        },
      );
      _ownedTalkAttempts.remove(attempt);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopTalking() {
    final inFlight = _stopInFlight;
    if (inFlight != null) return inFlight;

    _talkIntentGeneration++;
    // The underlying microphone service invalidates and detaches a native
    // start that outlives its cleanup timeout. Mirror that ownership boundary
    // here so a permanently pending old intent cannot poison the next press.
    _startInFlight = null;
    // Invalidates a pending permission/capture operation synchronously before
    // any remote cleanup awaits network or recorder work.
    final activeAttempt = _activeTalkAttempt;
    final attempts = Set<_TalkAttempt>.from(_ownedTalkAttempts);
    _activeTalkAttempt = null;
    final microphoneStop = _microphone.stop();
    late final Future<void> operation;
    operation = _stopTalking(
      microphoneStop: microphoneStop,
      activeAttempt: activeAttempt,
      attempts: attempts,
    ).whenComplete(() {
      if (identical(_stopInFlight, operation)) _stopInFlight = null;
    });
    _stopInFlight = operation;
    return operation;
  }

  Future<void> _stopTalking({
    required Future<void> microphoneStop,
    required _TalkAttempt? activeAttempt,
    required Set<_TalkAttempt> attempts,
  }) async {
    // Claim remote cleanup ownership before awaiting so a cancelled start
    // cannot issue a duplicate stop for the same lease.
    Object? error;

    Future<bool> attempt(Future<void> Function() operation) async {
      try {
        await operation();
        return true;
      } catch (caught) {
        error ??= caught;
        return false;
      }
    }

    Future<void> closeActiveUpload() async {
      if (activeAttempt == null) return;
      final pumpDrained = await attempt(
        () => _drainTalkPump(activeAttempt).timeout(talkFlushTimeout),
      );
      if (!pumpDrained) {
        // A blocked socket must not retain stop ownership. Force-closing the
        // streaming client lets the independent /talk/stop request proceed.
        activeAttempt.audioClient?.close(force: true);
      } else {
        final request = activeAttempt.audioRequest;
        activeAttempt.audioRequest = null;
        if (request != null) {
          await attempt(() async {
            final response = await request.close().timeout(timeout);
            final body =
                await utf8.decoder.bind(response).join().timeout(timeout);
            if (response.statusCode != HttpStatus.ok) {
              throw StateError(
                'Talk audio failed: ${response.statusCode} ${body.trim()}',
              );
            }
          });
        }
      }
      activeAttempt.audioClient?.close(force: true);
      activeAttempt.audioClient = null;
    }

    final pendingRemoteStops = <_TalkAttempt, Future<bool>>{
      for (final owned in attempts)
        if (!identical(owned, activeAttempt) && owned.startRequestIssued)
          owned: _stopTalkAttemptBestEffort(owned),
    };
    for (final owned in attempts) {
      if (!owned.startRequestIssued) {
        _ownedTalkAttempts.remove(owned);
      }
    }
    try {
      // Recorder/platform teardown and room/socket teardown deliberately run
      // independently. A stuck recorder must never retain a server talk lease.
      await Future.wait([
        attempt(() => microphoneStop.timeout(timeout)),
        closeActiveUpload(),
        ...pendingRemoteStops.values.map((stop) async {
          if (!await stop) {
            error ??=
                StateError('A pending talk attempt could not be stopped.');
          }
        }),
      ]);
      if (activeAttempt != null &&
          !await _stopTalkAttemptBestEffort(activeAttempt)) {
        error ??= StateError('The active talk session could not be stopped.');
      }
    } finally {
      activeAttempt?.audioClient?.close(force: true);
      activeAttempt?.audioClient = null;
      activeAttempt?.audioRequest = null;
      if (identical(_activeTalkAttempt, activeAttempt)) {
        _activeTalkAttempt = null;
      }
      activeAttempt?.clearPump();
      _emit(ClientRoomControlSnapshot(
        comfort: _state.comfort,
        talking: false,
        talkBytesSent: _state.talkBytesSent,
        talkBytesDropped: _state.talkBytesDropped,
        lastError: error,
      ));
    }
    final terminalError = error;
    if (terminalError != null) throw terminalError;
  }

  bool _isTalkIntentCurrent(int generation) =>
      !_disposed && generation == _talkIntentGeneration;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await stopTalking();
    } catch (_) {}
    await _microphone.dispose();
    await _states.close();
  }

  Future<Map<String, Object?>?> _requestJson(
    PairingSession session,
    String path, {
    required String method,
    Map<String, Object?>? body,
  }) async {
    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final uri = ServerEndpointBuilder(session).http(path);
      final request = method == 'GET'
          ? await client.getUrl(uri).timeout(timeout)
          : await client.postUrl(uri).timeout(timeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${session.sessionToken}',
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final responseBody =
          await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('$path failed: ${response.statusCode} $responseBody');
      }
      if (responseBody.trim().isEmpty) return null;
      final decoded = jsonDecode(responseBody);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _abortTalkAttempt(_TalkAttempt attempt) async {
    final ownsActiveState = identical(_activeTalkAttempt, attempt);
    if (ownsActiveState) {
      _activeTalkAttempt = null;
    }
    final microphoneStop =
        ownsActiveState ? _microphone.stop() : Future<void>.value();
    // This is a failure path, so there is no useful audio body to drain.
    // Waiting for request.close() can deadlock with a room endpoint that waits
    // for the streaming body before accepting the independent stop request.
    attempt.audioClient?.close(force: true);
    attempt.audioClient = null;
    attempt.audioRequest = null;
    final roomStop = _stopTalkAttemptBestEffort(attempt);
    await Future.wait([
      microphoneStop.timeout(timeout).catchError((_) {}),
      roomStop,
    ]);
    if (ownsActiveState) attempt.clearPump();
  }

  void _enqueueTalkChunk(_TalkAttempt attempt, Uint8List chunk) {
    if (!identical(_activeTalkAttempt, attempt) ||
        attempt.audioRequest == null ||
        chunk.isEmpty) {
      return;
    }
    if (attempt.pendingChunks.length >= _maxPendingTalkChunks) {
      final dropped = attempt.pendingChunks.removeFirst();
      _emit(ClientRoomControlSnapshot(
        comfort: _state.comfort,
        talking: true,
        talkBytesSent: _state.talkBytesSent,
        talkBytesDropped: _state.talkBytesDropped + dropped.length,
      ));
    }
    attempt.pendingChunks.addLast(Uint8List.fromList(chunk));
    _ensureTalkPump(attempt);
  }

  void _ensureTalkPump(_TalkAttempt attempt) {
    if (attempt.flushInFlight != null) return;
    if (attempt.pendingChunks.isEmpty || attempt.audioRequest == null) return;
    late final Future<void> pump;
    pump = _pumpTalkChunks(attempt).catchError((Object error) {
      attempt.pumpError = error;
      attempt.pendingChunks.clear();
    }).whenComplete(() {
      if (identical(attempt.flushInFlight, pump)) {
        attempt.flushInFlight = null;
      }
      if (attempt.pumpError == null &&
          attempt.pendingChunks.isNotEmpty &&
          attempt.audioRequest != null) {
        scheduleMicrotask(() => _ensureTalkPump(attempt));
      } else if (attempt.pumpError != null &&
          identical(_activeTalkAttempt, attempt)) {
        scheduleMicrotask(() {
          unawaited(stopTalking().catchError((_) {}));
        });
      }
    });
    attempt.flushInFlight = pump;
  }

  Future<void> _drainTalkPump(_TalkAttempt attempt) async {
    while (attempt.flushInFlight != null || attempt.pendingChunks.isNotEmpty) {
      _ensureTalkPump(attempt);
      final current = attempt.flushInFlight;
      if (current == null) break;
      await current;
    }
    final error = attempt.pumpError;
    if (error != null) throw error;
  }

  Future<void> _pumpTalkChunks(_TalkAttempt attempt) async {
    final request = attempt.audioRequest;
    if (request == null) return;
    while (attempt.pendingChunks.isNotEmpty &&
        identical(attempt.audioRequest, request)) {
      final chunk = attempt.pendingChunks.removeFirst();
      request.add(chunk);
      attempt.chunksSinceFlush++;
      _emit(ClientRoomControlSnapshot(
        comfort: _state.comfort,
        talking: true,
        talkBytesSent: _state.talkBytesSent + chunk.length,
        talkBytesDropped: _state.talkBytesDropped,
      ));
    }
    if (attempt.chunksSinceFlush > 0 &&
        identical(attempt.audioRequest, request)) {
      attempt.chunksSinceFlush = 0;
      await _talkRequestFlusher(request).timeout(talkFlushTimeout);
    }
  }

  bool? _readAudioDetectionPaused(Map<String, Object?>? json) {
    final detection = json?['audioDetection'];
    final paused = detection is Map ? detection['paused'] : null;
    return paused is bool ? paused : null;
  }

  void _emit(
    ClientRoomControlSnapshot state, {
    bool preserveDetectionState = true,
  }) {
    _state = ClientRoomControlSnapshot(
      comfort: state.comfort,
      talking: state.talking,
      talkBytesSent: state.talkBytesSent,
      talkBytesDropped: state.talkBytesDropped,
      lastError: state.lastError,
      audioDetectionPaused: state.audioDetectionPaused ??
          (preserveDetectionState ? _state.audioDetectionPaused : null),
    );
    if (!_states.isClosed) _states.add(_state);
  }
}

class _TalkAttempt {
  _TalkAttempt({
    required this.session,
    required this.id,
    required this.generation,
  });

  final PairingSession session;
  final String id;
  final int generation;
  String? token;
  HttpClient? audioClient;
  HttpClientRequest? audioRequest;
  bool startRequestIssued = false;
  final pendingChunks = ListQueue<Uint8List>();
  Future<void>? flushInFlight;
  Object? pumpError;
  int chunksSinceFlush = 0;

  void clearPump() {
    pendingChunks.clear();
    flushInFlight = null;
    pumpError = null;
    chunksSinceFlush = 0;
  }
}
